-- 402: 利用時間の一時変更申請(Phase5・AC-05・2026-08-31俊承認)。
--   保護者が「その日だけ登降園時刻を変えたい」を parent_requests(既存基盤)へ申請
--   → 園(主任以上)が承認 → 対象日の child_daily_attendance の日別override
--   (scheduled_start_at/scheduled_end_at)へ upsert → 186ボードが override 優先で表示(AC-05)。
--   契約時間外分は実打刻ベースで延長料金が自動計算される(Phase6・別処理)。
--   新テーブル不要: 既存の申請フロー(承認/却下/通知/監査/RLS)をそのまま利用。
--   details キー: '希望登園時刻'/'希望降園時刻'(HH:MM)+'理由'。承認画面(admin_web)は
--   details を汎用描画するため表示側の追加実装は型ラベルのみ。

-- (1) request_type に 'schedule_change' を追加(201と同型の差し替え)
alter table parent_requests drop constraint if exists parent_requests_request_type_check;
alter table parent_requests add constraint parent_requests_request_type_check
  check (request_type in ('absence', 'tardiness', 'early_leave', 'pickup_person_change',
                          'other', 'medication', 'schedule_change'));

-- (2) approve_parent_request を拡張(202の本体を踏襲し schedule_change ブロックを追加)
create or replace function approve_parent_request(p_request_id uuid, p_decision_reason text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request parent_requests%rowtype;
  v_enroll_start date;
  v_enroll_end date;
  v_day date;
  v_end date;
  v_kind text;
  v_is_absent boolean;
  v_reason text;
  -- 201: 服薬承認時の午睡自動追加用
  v_nap_office uuid;
  v_nap_class uuid;
  v_nap_required boolean;
  -- 202: お迎え変更承認時のお迎え者マスタ登録用
  v_pickup_name text;
  -- 402: 利用時間の一時変更の反映用
  v_sc_start text;
  v_sc_end text;
begin
  select * into v_request from parent_requests where id = p_request_id for update;
  if v_request.id is null then
    raise exception 'request not found';
  end if;
  if not staff_manages_guardian_data(v_request.child_id) then
    raise exception 'not authorized';
  end if;
  if v_request.status <> 'pending' then
    raise exception 'request is % and cannot be approved', v_request.status;
  end if;

  update parent_requests
  set status = 'approved', approved_by = my_employee_id(), approved_at = now(), decision_reason = p_decision_reason
  where id = p_request_id;

  -- 欠席の承認は、対象期間の各日を欠席としてデイリーボードへ自動反映。
  -- (感染症は106でabsenceのdetailsに統合済み=absenceで一括。遅刻/早退/お迎え変更/その他は対象外)。
  -- absence_kind=NULL(旧アプリ等)は反映をスキップ(既存の手動欠席を上書き破壊しない)。
  if v_request.request_type = 'absence' then
    v_kind := v_request.absence_kind;
    if v_kind is not null then
      v_is_absent := coalesce(v_kind in ('sick_absence', 'personal_absence'), false);  -- 185と同一の同期規則
      v_reason := case v_kind
        when 'sick_absence' then '保護者申請（病欠）'
        when 'personal_absence' then '保護者申請（都合欠）'
        else '保護者申請による欠席' end;

      -- 在籍期間(children マスタ)でクリップ: 在籍外の日には行を作らない。
      select enrollment_date, withdrawal_date into v_enroll_start, v_enroll_end
      from children where id = v_request.child_id;

      v_day := greatest(v_request.target_date, v_enroll_start);
      v_end := coalesce(v_request.end_date, v_request.target_date);
      if v_enroll_end is not null then
        v_end := least(v_end, v_enroll_end);
      end if;

      while v_day <= v_end loop
        insert into child_daily_attendance (child_id, business_date, is_absent, attendance_kind, absence_reason, changed_by, changed_at)
        values (v_request.child_id, v_day, v_is_absent, v_kind, v_reason, my_employee_id(), now())
        on conflict (child_id, business_date) do update set
          is_absent       = excluded.is_absent,
          attendance_kind = excluded.attendance_kind,
          absence_reason  = excluded.absence_reason,
          changed_by      = excluded.changed_by,
          changed_at      = excluded.changed_at;
        perform refresh_daily_child_status(v_request.child_id, v_day);
        v_day := v_day + 1;
      end loop;
    end if;
  end if;

  -- 201: 服薬連絡の承認。3歳以上(対象日の在籍クラスの nap_check_required=false)の園児を
  -- 対象日の午睡チェックへ自動追加(既存の任意追加機構=nap_sessions行。冪等)。
  -- kinds NULL/空(旧アプリ等)は反映スキップ(承認自体は成立)。在籍クラスが解決できない日も
  -- スキップ(承認をブロックしない)。ボードの服薬表示は読み取りRPC(fetch_board_medication_for_office)
  -- が parent_requests から直接引くため、承認時に立てるデータは無い。
  if v_request.request_type = 'medication'
     and v_request.medication_kinds is not null
     and array_length(v_request.medication_kinds, 1) > 0 then
    select c.office_id, cce.class_id, cc.nap_check_required
      into v_nap_office, v_nap_class, v_nap_required
    from children c
    join child_class_enrollments cce on cce.child_id = c.id
      and cce.effective_start_date <= v_request.target_date
      and (cce.effective_end_date is null or cce.effective_end_date >= v_request.target_date)
    join childcare_classes cc on cc.id = cce.class_id
    where c.id = v_request.child_id
    order by cce.effective_start_date desc
    limit 1;

    if v_nap_class is not null and v_nap_required = false then
      insert into nap_sessions (child_id, office_id, class_id, session_date, is_required, added_by)
      values (v_request.child_id, v_nap_office, v_nap_class, v_request.target_date, false, my_employee_id())
      on conflict (child_id, session_date) do nothing;
    end if;
  end if;

  -- 202: お迎えの方の変更の承認。お迎え者マスタ(園児単位)へ upsert。
  -- 同一人物判定は unique(child_id, name)。id_verified(実物確認済み)は維持しリセットしない。
  -- 続柄・電話・身分証パスは新しい値があるときだけ更新(NULLで既存値を消さない)。
  -- 氏名が空(旧アプリ等)は登録スキップ(承認自体は成立)。
  if v_request.request_type = 'pickup_person_change' then
    v_pickup_name := nullif(trim(coalesce(v_request.details->>'お迎えの方の氏名', '')), '');
    if v_pickup_name is not null then
      insert into pickup_persons (child_id, name, relationship, phone, id_document_path, created_by_guardian_id)
      values (
        v_request.child_id,
        v_pickup_name,
        nullif(trim(coalesce(v_request.details->>'続柄', '')), ''),
        nullif(trim(coalesce(v_request.details->>'電話番号', '')), ''),
        v_request.id_document_path,
        v_request.guardian_id
      )
      on conflict (child_id, name) do update set
        relationship     = coalesce(excluded.relationship, pickup_persons.relationship),
        phone            = coalesce(excluded.phone, pickup_persons.phone),
        id_document_path = coalesce(excluded.id_document_path, pickup_persons.id_document_path);
    end if;
  end if;

  -- 402: 利用時間の一時変更の承認。対象日(単日)の予定登降園時刻を child_daily_attendance の
  -- 日別override へ upsert(186ボードが override 優先で表示)。scheduled_* のみ更新し、
  -- is_absent/attendance_kind(欠席側)は触らない。時刻が HH:MM 形式でない・終了≦開始・
  -- 在籍外の日(旧アプリ/不正値)は反映スキップ(承認自体は成立)。
  if v_request.request_type = 'schedule_change' then
    v_sc_start := v_request.details->>'希望登園時刻';
    v_sc_end   := v_request.details->>'希望降園時刻';
    -- 時分として厳密に検証(00:00〜23:59)。'25:99' 等の不正値が緩い正規表現を通過して
    -- ::time cast で例外→承認全体がabortするのを防ぐ(Fableレビュー M1)。
    if v_sc_start ~ '^([01]?\d|2[0-3]):[0-5]\d$' and v_sc_end ~ '^([01]?\d|2[0-3]):[0-5]\d$'
       and v_sc_end::time > v_sc_start::time then
      select enrollment_date, withdrawal_date into v_enroll_start, v_enroll_end
      from children where id = v_request.child_id;
      if v_request.target_date >= v_enroll_start
         and (v_enroll_end is null or v_request.target_date <= v_enroll_end) then
        insert into child_daily_attendance
          (child_id, business_date, scheduled_start_at, scheduled_end_at, changed_by, changed_at)
        values
          (v_request.child_id, v_request.target_date, v_sc_start::time, v_sc_end::time, my_employee_id(), now())
        on conflict (child_id, business_date) do update set
          scheduled_start_at = excluded.scheduled_start_at,
          scheduled_end_at   = excluded.scheduled_end_at,
          changed_by         = excluded.changed_by,
          changed_at         = excluded.changed_at;
      end if;
    end if;
  end if;
end;
$$;
grant execute on function approve_parent_request(uuid, text) to anon, authenticated, service_role;
