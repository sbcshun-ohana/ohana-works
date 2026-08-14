-- 201: 服薬連絡(parent_requests新種類)+午睡チェック自動追加(設計指示書 2026-08-13/俊確定A・B・C 2026-08-14)。
--
-- 概要:
--  (1) parent_requests に medication_kinds text[] を追加(薬の種類・複数選択。値は日本語ラベル=俊確定B。
--      選択肢はフロント共通定数で管理)。様子・症状/備考は既存 details jsonb(日本語キー)に格納し、
--      admin_web承認画面の汎用key:value表示に自動で乗せる。
--  (2) request_type CHECK に 'medication' を追加(106と同型の差し替え)。
--  (3) approve_parent_request(現行=197)に服薬分岐を追加:
--      3歳以上(=対象日の在籍クラスの nap_check_required=false。俊確定A)の園児を対象日の
--      午睡チェックへ自動追加(既存の任意追加=nap_sessions行と同一機構。unique(child_id,session_date)
--      + on conflict do nothing で冪等=AC-06)。0〜2歳児クラスは既定対象のため追加不要。
--      medication_kinds が NULL/空(旧アプリのRLS直接insert等)は反映スキップ・承認自体は成立
--      (197のkind=NULL方針と同型)。却下・取消の巻き戻しはv1では行わない(設計書§3.3)。
--  (4) fetch_pending_parent_requests に medication_kinds を追加(承認画面で種類を確認)。
--      戻り値の型変更のため drop→create→grant再付与(197と同手順)。
--      ※適用前の pg_get_functiondef 照合(197)は drop より前に実施すること。
--  (5) ボード服薬表示の読み取りRPC fetch_board_medication_for_office を新設(198方式。
--      種類+解熱剤フラグ+様子・症状=俊確定C。186 fetch_daily_board_for_office は変更しない)。
--  (6) 機能フラグ medication_report_enabled(既定OFF)+判定RPC(145の共通ヘルパー利用)。
--
-- 冪等: 列追加=if not exists、CHECK=drop if exists→add、関数=create or replace
--       (fetch_pending のみ drop→create)、フラグ行=not exists ガード。

-- (1) 薬の種類(複数選択・日本語ラベル)
alter table parent_requests add column if not exists medication_kinds text[];

comment on column parent_requests.medication_kinds is
  '服薬連絡(201)の薬の種類(複数選択・日本語ラベル。選択肢はフロント共通定数で管理)。medication以外はNULL';

-- (2) request_type に medication を追加(106と同型の差し替え)
alter table parent_requests drop constraint if exists parent_requests_request_type_check;
alter table parent_requests add constraint parent_requests_request_type_check
  check (request_type in ('absence', 'tardiness', 'early_leave', 'pickup_person_change', 'other', 'medication'));

-- (3) 承認: 197の全文をベースに服薬分岐を追加(照合は適用前に実施)
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
end;
$$;

-- (4) 承認画面の一覧に medication_kinds を追加。戻り型変更のため drop→create→grant 再付与。
--     ※ pg_get_functiondef による 197 照合は、この drop より前に実施すること。
drop function if exists fetch_pending_parent_requests(uuid);

create function fetch_pending_parent_requests(p_office_id uuid)
returns table (
  request_id uuid,
  child_id uuid,
  child_display_name text,
  guardian_name text,
  request_type text,
  target_date date,
  end_date date,
  absence_kind text,
  medication_kinds text[],
  details jsonb,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not has_childcare_office_access(p_office_id) then
    raise exception 'not authorized';
  end if;

  return query
  select
    pr.id, c.id, c.display_name, g.name, pr.request_type,
    pr.target_date, pr.end_date, pr.absence_kind, pr.medication_kinds, pr.details, pr.created_at
  from parent_requests pr
  join children c on c.id = pr.child_id
  join guardians g on g.id = pr.guardian_id
  where c.office_id = p_office_id and pr.status = 'pending'
  order by pr.created_at;
end;
$$;

grant execute on function fetch_pending_parent_requests(uuid) to anon, authenticated, service_role;

-- (5) ボード服薬表示の読み取り(198方式・186は不変)。同一児の複数承認は種類をマージして1行。
--     解熱剤フラグ='解熱剤' を含むか(俊確定B=日本語ラベル)。様子・症状も返す(俊確定C)。
create or replace function fetch_board_medication_for_office(p_office_id uuid, p_business_date date)
returns table (
  child_id uuid,
  medication_kinds text[],
  has_antipyretic boolean,
  symptom text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not has_childcare_office_access(p_office_id) then
    raise exception 'not authorized';
  end if;

  return query
  select
    m.child_id,
    array_agg(distinct m.k),
    bool_or(m.k = '解熱剤'),
    string_agg(distinct m.symptom, ' / ') filter (where m.symptom is not null and m.symptom <> '')
  from (
    select pr.child_id, k.k, pr.details->>'お子さまの様子・症状' as symptom
    from parent_requests pr
    join children c on c.id = pr.child_id
    cross join lateral unnest(pr.medication_kinds) as k(k)
    where c.office_id = p_office_id
      and pr.request_type = 'medication'
      and pr.status = 'approved'
      and pr.target_date = p_business_date
      and pr.medication_kinds is not null
  ) m
  group by m.child_id;
end;
$$;

grant execute on function fetch_board_medication_for_office(uuid, date) to anon, authenticated, service_role;

-- (6) 機能フラグ(既定OFF・施設別ONはseed/フラグ画面から)。判定は145の共通ヘルパーを利用。
insert into feature_flags (feature_key, name, description, default_enabled)
select 'medication_report_enabled', '服薬連絡', '保護者からの服薬連絡(申請種類)とボード服薬表示・午睡自動追加', false
where not exists (select 1 from feature_flags where feature_key = 'medication_report_enabled');

create or replace function is_medication_report_enabled_for_office(p_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select is_feature_enabled_for_office('medication_report_enabled', p_office_id);
$$;

grant execute on function is_medication_report_enabled_for_office(uuid) to anon, authenticated, service_role;
