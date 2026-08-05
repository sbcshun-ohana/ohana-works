-- 186: デイリーボードに登降園バー用の列を追加(fetch_daily_board_for_office を drop+recreate)
-- デイリーボード刷新 Phase B の第3弾。既存22列は不変のまま、以下8列を追加(read-only):
--   arrival_at/departure_at   … 実績の登園(最初のdrop_off)/降園(最後のpick_up)時刻
--   out_at/return_at          … 日中の中抜け(外出/戻り・185で許可した event_type)
--   scheduled_start/end_at    … 予定(日別override[184] を優先、無ければ週次標準[184])
--   attendance_kind/attendance_note … 出欠種別・出欠メモ(184/185)
-- 予定の曜日解決: extract(isodow) = 1:月..7:日 (child_weekly_schedule.weekday と一致)。
-- 列追加のため drop→再作成(172と同じ手順)。172/167/163 は明示grant無し(既定PUBLIC実行)だったが、
-- 本186では安全のため drop 後に grant execute を明示付与する(default権限がrevoke済み環境でも確実)。

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
  therapy_provider_name text,
  -- ▼186 追加(登降園バー用)
  arrival_at timestamptz,
  departure_at timestamptz,
  out_at timestamptz,
  return_at timestamptz,
  scheduled_start_at time,
  scheduled_end_at time,
  attendance_kind text,
  attendance_note text
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
    case when te.event_type = 'out' then te.provider_name end,
    -- ▼186 追加
    ev.arrival_at,
    ev.departure_at,
    ev.out_at,
    ev.return_at,
    coalesce(cda.scheduled_start_at, ws.scheduled_start_at),
    coalesce(cda.scheduled_end_at,   ws.scheduled_end_at),
    cda.attendance_kind,
    cda.attendance_note
  from children c
  join child_class_enrollments cce on cce.child_id = c.id
    and cce.effective_start_date <= p_business_date
    and (cce.effective_end_date is null or cce.effective_end_date >= p_business_date)
  join childcare_classes cc on cc.id = cce.class_id
  left join daily_child_status dcs on dcs.child_id = c.id and dcs.business_date = p_business_date
  left join child_attendance_events cae on cae.id = dcs.last_event_id
  left join family_daily_reports fdr on fdr.child_id = c.id and fdr.business_date = p_business_date
  left join child_daily_contacts cdc on cdc.child_id = c.id and cdc.business_date = p_business_date
  left join child_daily_attendance cda on cda.child_id = c.id and cda.business_date = p_business_date
  left join child_weekly_schedule ws on ws.child_id = c.id and ws.weekday = extract(isodow from p_business_date)::int
  left join lateral (
    select e.event_type, e.occurred_at, tp.name as provider_name
    from therapy_outing_events e
    join therapy_providers tp on tp.id = e.provider_id
    where e.child_id = c.id and (e.occurred_at at time zone 'Asia/Tokyo')::date = p_business_date
    order by e.occurred_at desc
    limit 1
  ) te on true
  left join lateral (
    select
      min(e2.occurred_at) filter (where e2.event_type in ('drop_off','proxy_drop_off')) as arrival_at,
      max(e2.occurred_at) filter (where e2.event_type in ('pick_up','proxy_pick_up'))   as departure_at,
      max(e2.occurred_at) filter (where e2.event_type = 'out')    as out_at,
      max(e2.occurred_at) filter (where e2.event_type = 'return') as return_at
    from child_attendance_events e2
    where e2.child_id = c.id
      and (e2.occurred_at at time zone 'Asia/Tokyo')::date = p_business_date
  ) ev on true
  where c.office_id = p_office_id and c.enrollment_status <> '退園済み'
  order by cc.age_group, cc.class_name, c.display_name;
end;
$$;

-- drop 後の実行権限を明示付与(認証セッションのみ。関数内で office access を判定)。
grant execute on function fetch_daily_board_for_office(uuid, date) to authenticated;
