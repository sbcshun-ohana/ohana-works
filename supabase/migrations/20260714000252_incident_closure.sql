-- 252: ヒヤリハット・事故報告 Phase B ①(クロージング追跡)。設計指示書v2 §3。
-- 事故報告書2種は作成時 open(246の save で設定済)。条件充足で主任以上がクローズ、管理者以上が解除。
-- クローズ条件: 保護者連絡1行以上 / 最終連絡の反応=理解 or その他+記述 / 経過1行以上 /
--   病院搬送は受診記録の医師指示あり。

-- 施設別の未クローズ通知しきい値(発生から何日で初回通知するか。§7②俊回答=1日)+ 日次通知の重複防止。
alter table childcare_office_settings
  add column if not exists incident_unclosed_notify_days int not null default 1;
alter table childcare_office_settings
  add column if not exists incident_unclosed_notified_on date;

-- 内部: クローズ未充足の条件名を返す(空=クローズ可能)。authzなし=RPCから使う。
create or replace function incident_closure_missing(p_id uuid)
returns text[]
language plpgsql stable security definer set search_path = public
as $$
declare
  v_type text;
  v_missing text[] := '{}';
  v_last incident_report_guardian_contacts%rowtype;
begin
  select report_type into v_type from incident_reports where id = p_id;
  if v_type is null then return array['not found']; end if;

  select * into v_last from incident_report_guardian_contacts
  where incident_report_id = p_id order by contacted_at desc limit 1;
  if not found then
    v_missing := array_append(v_missing, '保護者連絡');
  elsif not (v_last.reaction_kind = 'understood'
             or (v_last.reaction_kind = 'other' and coalesce(v_last.reaction_text, '') <> '')) then
    v_missing := array_append(v_missing, '保護者の反応(ご理解 or その他+記述)');
  end if;

  if not exists (select 1 from incident_report_progress_logs where incident_report_id = p_id) then
    v_missing := array_append(v_missing, '経過と観察記録');
  end if;

  if v_type = 'hospital' then
    if not exists (
      select 1 from incident_report_medical_visits
      where incident_report_id = p_id and doctor_instruction is not null
    ) then
      v_missing := array_append(v_missing, '受診記録(医師の指示)');
    end if;
  end if;

  return v_missing;
end;
$$;

-- 保護者対応クローズ(主任以上・申請中以降・条件充足のみ)
create or replace function close_incident_report(p_id uuid, p_note text)
returns void
language plpgsql security definer set search_path = public
as $$
declare r incident_reports%rowtype; v_missing text[];
begin
  select * into r from incident_reports where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not manages_childcare(r.office_id) then raise exception 'not authorized'; end if;
  if r.report_type not in ('minor', 'hospital') then raise exception 'クローズ対象外の種別です'; end if;
  if r.status = 'draft' then raise exception 'クローズは申請中以降の状態でのみ可能です'; end if;

  v_missing := incident_closure_missing(p_id);
  if array_length(v_missing, 1) is not null then
    raise exception 'クローズ条件が未充足です: %', array_to_string(v_missing, '、');
  end if;

  update incident_reports set
    closure_status = 'closed', closed_by = my_employee_id(), closed_at = now(), closure_note = p_note
  where id = p_id;
end;
$$;
grant execute on function close_incident_report(uuid, text) to authenticated, service_role;

-- クローズ解除(管理者以上・理由必須・監査)
create or replace function reopen_incident_closure(p_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public
as $$
declare r incident_reports%rowtype;
begin
  select * into r from incident_reports where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not is_childcare_admin(r.office_id) then raise exception 'not authorized'; end if;
  if coalesce(p_reason, '') = '' then raise exception '解除理由が必要です'; end if;
  if r.closure_status <> 'closed' then raise exception 'invalid state'; end if;

  update incident_reports set
    closure_status = 'open',
    closure_reopened_by = my_employee_id(),
    closure_reopened_at = now(),
    closure_note = coalesce(closure_note || ' / ', '') || '再オープン理由: ' || p_reason
  where id = p_id;
end;
$$;
grant execute on function reopen_incident_closure(uuid, text) to authenticated, service_role;

-- クローズ状態+充足判定(詳細画面のボタン制御用)
create or replace function fetch_incident_closure(p_id uuid)
returns table (
  closure_status text, is_ready boolean, missing text[],
  closed_by_name text, closed_at timestamptz,
  reopened_by_name text, reopened_at timestamptz, closure_note text
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not is_childcare_staff() then raise exception 'not authorized'; end if;
  return query
  select r.closure_status,
         (array_length(incident_closure_missing(r.id), 1) is null),
         incident_closure_missing(r.id),
         e1.name, r.closed_at, e2.name, r.closure_reopened_at, r.closure_note
  from incident_reports r
  left join employees e1 on e1.id = r.closed_by
  left join employees e2 on e2.id = r.closure_reopened_by
  where r.id = p_id;
end;
$$;
grant execute on function fetch_incident_closure(uuid) to authenticated, service_role;

-- 未クローズ一覧(施設単位・経過日数順・不足条件付き)
create or replace function fetch_open_incident_reports(p_office_id uuid)
returns table (
  id uuid, report_type text, status text, occurred_on date, days_elapsed int,
  place_label text, child_names text, created_by_name text, missing text[]
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not is_childcare_staff() then raise exception 'not authorized'; end if;
  return query
  select r.id, r.report_type, r.status, r.occurred_on, (current_date - r.occurred_on)::int,
         coalesce(lo.label, r.place_other),
         (select string_agg(coalesce(c.child_name_snapshot, ''), '、' order by c.created_at)
          from incident_report_children c where c.incident_report_id = r.id),
         e.name,
         incident_closure_missing(r.id)
  from incident_reports r
  left join incident_lookup_options lo on lo.id = r.place_option_id
  left join employees e on e.id = r.created_by
  where r.office_id = p_office_id
    and r.closure_status = 'open'
    and r.report_type in ('minor', 'hospital')
  order by r.occurred_on asc, r.created_at asc;
end;
$$;
grant execute on function fetch_open_incident_reports(uuid) to authenticated, service_role;

-- 未クローズ件数(バッジ用)
create or replace function count_open_incident_reports(p_office_id uuid)
returns int
language sql stable security definer set search_path = public
as $$
  select case when is_childcare_staff() then (
    select count(*)::int from incident_reports r
    where r.office_id = p_office_id and r.closure_status = 'open' and r.report_type in ('minor', 'hospital')
  ) else 0 end;
$$;
grant execute on function count_open_incident_reports(uuid) to authenticated, service_role;
