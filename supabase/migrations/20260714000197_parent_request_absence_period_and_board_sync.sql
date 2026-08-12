-- 197: 保護者からの欠席連絡の「期間指定 + 欠席種別(病欠/都合欠)」対応 と、承認時のデイリーボード
--      自動反映(俊確定 + Fableレビュー2回反映 2026-08-12)。
--
-- 変更点:
--  (1) parent_requests に end_date(任意)と absence_kind(病欠/都合欠・absence申請のみ)を追加。
--      - end_date: null=単日(target_date)。end_date>=target_date かつ 期間上限31日。
--      - absence_kind: 'sick_absence'|'personal_absence'(=child_daily_attendance.attendance_kind と同じ値域)。
--        値域CHECKのみDBで担保。absence申請での必須入力はフォーム側で強制(既存行backfill不可のため
--        cross-column必須CHECKは張らない)。
--  (2) approve_parent_request を拡張: 欠席(request_type='absence')かつ absence_kind が非NULLのとき、対象期間
--      (在籍でクリップ)の各日を child_daily_attendance へ upsert。184/185の意味論に整合させ is_absent は
--      attendance_kind から同期(is_absent = kind in ('sick_absence','personal_absence'))し attendance_kind も設定。
--      → 163サマリー(is_absent基準の欠席カウント)・186ボード(is_absent+attendance_kind表示)の双方で反映。
--      - absence_kind=NULL(旧バージョンアプリのRLS直接insert等)の承認は、承認自体は成立させ、ボード反映は
--        197以前と同じく行わない(is_absent上書き破壊を避け、職員の手動対応に委ねる)。
--      - 遅刻/早退/お迎え変更/その他は is_absent を触らない(出席側)。
--  (3) fetch_pending_parent_requests に end_date / absence_kind を追加(承認画面で期間・種別を確認)。
--      戻り値の型変更は create or replace では 42P13(cannot change return type)になるため、
--      drop function → create → grant execute 再付与(094の現行実効grant=anon/authenticated/service_role)とする。
--      ※適用前の pg_get_functiondef 照合(094)は drop より前に実施すること。
--
-- 冪等: 列追加/制約は if not exists、approve は create or replace、fetch は drop if exists→create。

-- (1) 期間列・欠席種別列
alter table parent_requests add column if not exists end_date date;
alter table parent_requests add column if not exists absence_kind text;

do $$
begin
  if not exists (select 1 from pg_constraint
    where conrelid='parent_requests'::regclass and conname='parent_requests_end_date_range') then
    alter table parent_requests add constraint parent_requests_end_date_range
      check (end_date is null or (end_date >= target_date and end_date - target_date <= 31));
  end if;
  if not exists (select 1 from pg_constraint
    where conrelid='parent_requests'::regclass and conname='parent_requests_absence_kind_check') then
    alter table parent_requests add constraint parent_requests_absence_kind_check
      check (absence_kind is null or absence_kind in ('sick_absence','personal_absence'));
  end if;
end $$;

-- (2) 承認: 欠席(kind非NULL)は対象期間(在籍でクリップ)の各日をデイリーボードへ自動反映(184/185整合)。
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
      v_is_absent := coalesce(v_kind in ('sick_absence','personal_absence'), false);  -- 185と同一の同期規則
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
end;
$$;

-- (3) 承認画面の一覧に end_date / absence_kind を追加。戻り型変更のため drop→create→grant 再付与。
--     ※ pg_get_functiondef による 094 照合は、この drop より前に実施すること。
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
    pr.target_date, pr.end_date, pr.absence_kind, pr.details, pr.created_at
  from parent_requests pr
  join children c on c.id = pr.child_id
  join guardians g on g.id = pr.guardian_id
  where c.office_id = p_office_id and pr.status = 'pending'
  order by pr.created_at;
end;
$$;

-- 094の現行実効grant(20260713000001のdefault privileges=anon/authenticated/service_role)と同一を明示再付与。
grant execute on function fetch_pending_parent_requests(uuid) to anon, authenticated, service_role;
