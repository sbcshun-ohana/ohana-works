-- 療育外出 §4(前回指示書§2.2の改訂): デイリーボードに療育外出中バッジ、サマリー「登園中」から
-- 療育外出中を除外。外出中導出は is_child_on_therapy_outing(171)を共有。board RPC は列追加のため
-- drop→再作成(1回)。サマリーは create-or-replace。

-- 1) サマリー: 登園中 = present かつ 療育外出中でない。他項目は不変(出席は外出中を含む=変更なし)。
create or replace function fetch_daily_board_summary_for_office(
  p_office_id uuid,
  p_business_date date,
  p_class_id uuid default null
)
returns table (enrolled int, expected int, attended int, absent int, present_now int)
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
  with base as (
    select
      c.id as child_id,
      coalesce(cda.is_absent, false) as is_absent,
      dcs.status as status,
      is_child_on_therapy_outing(c.id, p_business_date) as on_outing
    from children c
    join child_class_enrollments cce on cce.child_id = c.id
      and cce.effective_start_date <= p_business_date
      and (cce.effective_end_date is null or cce.effective_end_date >= p_business_date)
    left join child_daily_attendance cda on cda.child_id = c.id and cda.business_date = p_business_date
    left join daily_child_status dcs on dcs.child_id = c.id and dcs.business_date = p_business_date
    where c.office_id = p_office_id
      and c.enrollment_status <> '退園済み'
      and (p_class_id is null or cce.class_id = p_class_id)
  )
  select
    count(*)::int,
    count(*) filter (where not is_absent)::int,
    count(*) filter (where status in ('present', 'picked_up'))::int,
    count(*) filter (where is_absent)::int,
    count(*) filter (where status = 'present' and not on_outing)::int
  from base;
end;
$$;

-- 2) board: 療育外出中バッジ用の3列を追加(列追加のため drop→再作成)
drop function if exists fetch_daily_board_for_office(uuid, date);

create function fetch_daily_board_for_office(p_office_id uuid, p_business_date date)
returns table (
  child_id uuid,
  display_name text,
  honorific_suffix text,
  class_id uuid,
  class_name text,
  status text,
  last_event_type text,
  last_event_at timestamptz,
  family_daily_report_status text,
  temperature numeric,
  has_pickup_change boolean,
  pickup_person_name text,
  pickup_person_relationship text,
  pickup_time_from time,
  pickup_time_to time,
  contact_id uuid,
  contact_status text,
  contact_scheduled_publish_at timestamptz,
  contact_published_at timestamptz,
  on_therapy_outing boolean,
  therapy_out_at timestamptz,
  therapy_provider_name text
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
    c.id, c.display_name, c.honorific_suffix_resolved, cc.id, cc.class_name,
    coalesce(dcs.status, 'not_arrived'),
    cae.event_type, cae.occurred_at,
    fdr.status,
    fdr.temperature,
    (fdr.pickup_person_name is not null),
    fdr.pickup_person_name,
    fdr.pickup_person_relationship,
    fdr.pickup_time_from,
    fdr.pickup_time_to,
    cdc.id, cdc.status, cdc.scheduled_publish_at, cdc.published_at,
    (te.event_type = 'out'),
    case when te.event_type = 'out' then te.occurred_at end,
    case when te.event_type = 'out' then te.provider_name end
  from children c
  join child_class_enrollments cce on cce.child_id = c.id
    and cce.effective_start_date <= p_business_date
    and (cce.effective_end_date is null or cce.effective_end_date >= p_business_date)
  join childcare_classes cc on cc.id = cce.class_id
  left join daily_child_status dcs on dcs.child_id = c.id and dcs.business_date = p_business_date
  left join child_attendance_events cae on cae.id = dcs.last_event_id
  left join family_daily_reports fdr on fdr.child_id = c.id and fdr.business_date = p_business_date
  left join child_daily_contacts cdc on cdc.child_id = c.id and cdc.business_date = p_business_date
  left join lateral (
    select e.event_type, e.occurred_at, tp.name as provider_name
    from therapy_outing_events e
    join therapy_providers tp on tp.id = e.provider_id
    where e.child_id = c.id and (e.occurred_at at time zone 'Asia/Tokyo')::date = p_business_date
    order by e.occurred_at desc
    limit 1
  ) te on true
  where c.office_id = p_office_id and c.enrollment_status <> '退園済み'
  order by cc.age_group, cc.class_name, c.display_name;
end;
$$;
