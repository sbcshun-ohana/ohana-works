-- Phase 2 §2.2: 在籍登園状況のサマリー集計RPCを新設。あわせて
-- fetch_daily_board_for_office に class_id を追加し、クラス絞り込みを
-- name基準からid基準へ是正する(同office内で学年跨ぎ同名クラスの衝突回避)。
--
-- サマリー定義(設計§2.2・確定):
--   在籍     = その日有効な在籍(child_class_enrollments)・退園済み除外
--   登園予定 = 在籍のうち欠席連絡(child_daily_attendance.is_absent)なし
--   出席     = その日一度でも登園(daily_child_status.status in present/picked_up)
--   欠席     = 欠席連絡あり(is_absent)
--   登園中   = いま園内(status = present)
-- p_class_id が NULL なら施設全体、指定時はそのクラス単位。

-- 1) サマリー集計RPC(新設)
create or replace function fetch_daily_board_summary_for_office(
  p_office_id uuid,
  p_business_date date,
  p_class_id uuid default null
)
returns table (
  enrolled int,
  expected int,
  attended int,
  absent int,
  present_now int
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
  with base as (
    select
      c.id as child_id,
      coalesce(cda.is_absent, false) as is_absent,
      dcs.status as status
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
    count(*) filter (where status = 'present')::int
  from base;
end;
$$;

-- 2) fetch_daily_board_for_office に class_id を追加(列追加のため drop→再作成)
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
  pickup_time_to time
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
    fdr.pickup_time_to
  from children c
  join child_class_enrollments cce on cce.child_id = c.id
    and cce.effective_start_date <= p_business_date
    and (cce.effective_end_date is null or cce.effective_end_date >= p_business_date)
  join childcare_classes cc on cc.id = cce.class_id
  left join daily_child_status dcs on dcs.child_id = c.id and dcs.business_date = p_business_date
  left join child_attendance_events cae on cae.id = dcs.last_event_id
  left join family_daily_reports fdr on fdr.child_id = c.id and fdr.business_date = p_business_date
  where c.office_id = p_office_id and c.enrollment_status <> '退園済み'
  order by cc.age_group, cc.class_name, c.display_name;
end;
$$;
