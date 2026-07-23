-- デイリーボード(fetch_daily_board_for_office)に家庭連絡帳の提出状況・お迎え変更連絡を追加する。
-- admin_web・Flutter(Ohana Kids)の両方がこのRPCを共有しているため、この1関数の変更で両画面に反映される。
-- お迎え変更連絡は職員が見落とさないようバッジ表示する想定(has_pickup_changeで判定)。
-- 戻り値の列を追加するため、create or replaceでは型変更不可(42P13)。dropしてから作り直す。

drop function if exists fetch_daily_board_for_office(uuid, date);

create function fetch_daily_board_for_office(p_office_id uuid, p_business_date date)
returns table (
  child_id uuid,
  display_name text,
  honorific_suffix text,
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
    c.id, c.display_name, c.honorific_suffix, cc.class_name,
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
  order by cc.class_name, c.display_name;
end;
$$;
