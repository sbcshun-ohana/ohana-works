-- 382: 出欠編集シートの外出理由プリフィル用(381の後続)。
--   当日の最新 'out' イベントの outing_reason を返す。シート再保存時に既存理由を保全する
--   (プリフィルした理由をそのまま渡すことで、時刻未変更の保存で理由が消えるのを防ぐ)。
--   権限=一般職員含む保育アクセス(has_childcare_office_access)。表示用の理由1個のみ返す。
create or replace function fetch_child_out_reason(p_child_id uuid, p_business_date date)
returns text language plpgsql stable security definer set search_path = public as $$
declare v_office uuid; v_reason text;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  select outing_reason into v_reason
  from child_attendance_events
  where child_id = p_child_id and event_type = 'out'
    and (occurred_at at time zone 'Asia/Tokyo')::date = p_business_date
  order by occurred_at desc limit 1;
  return v_reason;
end $$;
grant execute on function fetch_child_out_reason(uuid, date) to authenticated, service_role;
