-- 251: 午睡チェック一覧を「登園している園児のみ」に絞る(俊指示 2026-08-19)。
-- 欠席連絡がある(absent)・登園していない(not_arrived)園児は表示しない。
-- 判定源 = daily_child_status.status。登園済み = 'present'(登園中) / 'picked_up'(降園済=当日登園していた)。
-- fetch_nap_board(191)を戻り列そのままで置換(daily_child_status を内部結合してフィルタ)。
create or replace function fetch_nap_board(p_office_id uuid, p_class_id uuid, p_session_date date)
returns table (session_id uuid, child_id uuid, display_name text, honorific_suffix text, class_id uuid, class_name text,
  is_required boolean, sleep_start_at timestamptz, wake_up_at timestamptz, intervals jsonb, checks jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  return query
  select s.id, c.id, c.display_name, c.honorific_suffix_resolved, cc.id, cc.class_name, s.is_required, s.sleep_start_at, s.wake_up_at,
    coalesce((select jsonb_agg(jsonb_build_object('id',iv.id,'seq',iv.seq,'sleep_start_at',iv.sleep_start_at,'wake_up_at',iv.wake_up_at) order by iv.seq)
              from nap_intervals iv where iv.session_id=s.id), '[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object('slot_at',nc.slot_at,'body_position',nc.body_position,'breathing',nc.breathing_checked,
              'complexion',nc.complexion_checked,'bedding',nc.bedding_checked,'source',nc.source,
              'checked_by_name',e.name) order by nc.slot_at)
              from nap_checks nc left join employees e on e.id=nc.checked_by where nc.session_id=s.id), '[]'::jsonb)
  from nap_sessions s
  join children c on c.id=s.child_id
  join childcare_classes cc on cc.id=s.class_id
  join daily_child_status ds
    on ds.child_id = s.child_id and ds.business_date = s.session_date and ds.status in ('present', 'picked_up')
  where s.office_id=p_office_id and s.session_date=p_session_date and (p_class_id is null or s.class_id=p_class_id)
  order by cc.age_group, cc.class_name, c.display_name;
end; $$;
grant execute on function fetch_nap_board(uuid, uuid, date) to authenticated, service_role;
