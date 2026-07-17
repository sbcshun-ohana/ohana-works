-- 保護者アプリ Phase A: admin_web/職員向け一覧取得RPC群(デイリーボード・保護者管理・保護者申請)

create or replace function fetch_daily_board_for_office(p_office_id uuid, p_business_date date)
returns table (
  child_id uuid,
  display_name text,
  honorific_suffix text,
  class_name text,
  status text,
  last_event_type text,
  last_event_at timestamptz
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
    c.id, c.display_name, c.honorific_suffix, cc.class_name,
    coalesce(dcs.status, 'not_arrived'),
    cae.event_type, cae.occurred_at
  from children c
  join child_class_enrollments cce on cce.child_id = c.id
    and cce.effective_start_date <= p_business_date
    and (cce.effective_end_date is null or cce.effective_end_date >= p_business_date)
  join childcare_classes cc on cc.id = cce.class_id
  left join daily_child_status dcs on dcs.child_id = c.id and dcs.business_date = p_business_date
  left join child_attendance_events cae on cae.id = dcs.last_event_id
  where c.office_id = p_office_id and c.enrollment_status <> '退園済み'
  order by cc.class_name, c.display_name;
end;
$$;

create or replace function fetch_guardians_for_office(p_office_id uuid)
returns table (
  guardian_id uuid,
  name text,
  phone text,
  email text,
  status text,
  linked_children text
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
    g.id, g.name, g.phone, g.email, g.status,
    string_agg(c.display_name, '、' order by c.display_name)
  from guardians g
  join guardian_child_links gcl on gcl.guardian_id = g.id
  join children c on c.id = gcl.child_id
  where c.office_id = p_office_id
  group by g.id, g.name, g.phone, g.email, g.status
  order by g.name;
end;
$$;

create or replace function fetch_pending_parent_requests(p_office_id uuid)
returns table (
  request_id uuid,
  child_id uuid,
  child_display_name text,
  guardian_name text,
  request_type text,
  target_date date,
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
    pr.id, c.id, c.display_name, g.name, pr.request_type, pr.target_date, pr.details, pr.created_at
  from parent_requests pr
  join children c on c.id = pr.child_id
  join guardians g on g.id = pr.guardian_id
  where c.office_id = p_office_id and pr.status = 'pending'
  order by pr.created_at;
end;
$$;

create or replace function fetch_pending_guardian_invitations(p_office_id uuid)
returns table (
  invitation_id uuid,
  child_id uuid,
  child_display_name text,
  role text,
  expires_at timestamptz,
  status text
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
  select gi.id, c.id, c.display_name, gi.role, gi.expires_at, gi.status
  from guardian_invitations gi
  join children c on c.id = gi.child_id
  where c.office_id = p_office_id
  order by gi.created_at desc;
end;
$$;
