-- 378: 登降園 — 監査履歴の取得(本案§Aの「監査」閲覧・草案§20)。
--   既存の trg_audit(log_event_change・160005)が child_daily_attendance / child_attendance_events /
--   child_outings の INSERT/UPDATE/DELETE を event_logs に記録済み。これを園児×日で人間可読に取り出す。
--   before_data/after_data(to_jsonb(row))から child_id・日付を絞り込む。権限=主任以上(manages_childcare)。
create or replace function fetch_child_attendance_audit(p_child_id uuid, p_business_date date)
returns table (
  occurred_at timestamptz,
  operator text,
  target_type text,     -- child_daily_attendance / child_attendance_events / child_outings
  action text,          -- INSERT / UPDATE / DELETE
  before_data jsonb,
  after_data jsonb
)
language plpgsql stable security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  return query
  select el.occurred_at,
         coalesce(e.name, 'システム') as operator,
         el.target_type, el.action, el.before_data, el.after_data
  from event_logs el
  left join employees e on e.id = el.operator_id
  where el.target_type in ('child_daily_attendance', 'child_attendance_events', 'child_outings')
    and coalesce(el.after_data ->> 'child_id', el.before_data ->> 'child_id') = p_child_id::text
    and (
      -- child_daily_attendance / child_outings は business_date を保持
      coalesce(el.after_data ->> 'business_date', el.before_data ->> 'business_date') = to_char(p_business_date, 'YYYY-MM-DD')
      -- child_attendance_events は occurred_at(JST日付)で突合
      or (el.target_type = 'child_attendance_events'
          and ((coalesce(el.after_data ->> 'occurred_at', el.before_data ->> 'occurred_at'))::timestamptz at time zone 'Asia/Tokyo')::date = p_business_date)
    )
  order by el.occurred_at, el.id;  -- 同時刻タイの安定化(同一txのdelete+insert等)
end $$;
grant execute on function fetch_child_attendance_audit(uuid, date) to authenticated, service_role;
