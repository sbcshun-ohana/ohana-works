-- 235: apply_family_checkin の child_id 列名衝突修正(234のバグ・staging適用済 2026-08-18)。
-- OUT列 child_id と guardian_child_links.child_id が曖昧(42702)。OUT列名を out_child_id へ・内部参照を修飾。
create or replace function apply_family_checkin(
  p_session_id uuid, p_selections jsonb, p_business_date date
)
returns table (out_child_id uuid, result text, reason text)
language plpgsql security definer set search_path = public
as $$
declare
  v_session family_checkin_sessions%rowtype;
  v_sel jsonb;
  v_child uuid;
  v_action text;
  v_office uuid;
  v_status text;
  v_gate_blocked boolean;
  v_gate_reason text;
begin
  select * into v_session from family_checkin_sessions where id = p_session_id;
  if v_session.id is null then raise exception 'session not found'; end if;
  if v_session.consumed then raise exception 'session already used'; end if;
  if v_session.expires_at < now() then raise exception 'session expired'; end if;

  update family_checkin_sessions set consumed = true where id = p_session_id;

  for v_sel in select * from jsonb_array_elements(p_selections) loop
    v_child := (v_sel->>'child_id')::uuid;
    v_action := v_sel->>'action';

    select office_id into v_office from children where id = v_child and enrollment_status = '在籍中';
    if v_office is null or v_office <> v_session.office_id
       or not exists (select 1 from guardian_child_links gcl
                      where gcl.guardian_id = v_session.guardian_id and gcl.child_id = v_child) then
      out_child_id := v_child; result := 'skipped'; reason := '対象外の園児'; return next; continue;
    end if;

    if v_action = 'checkin' then
      v_gate_blocked := false; v_gate_reason := null;
      begin
        perform assert_infection_gate_for_checkin(v_child);
      exception when others then
        v_gate_blocked := true; v_gate_reason := sqlerrm;
      end;
      if v_gate_blocked then
        out_child_id := v_child; result := 'blocked'; reason := coalesce(v_gate_reason, '感染症ゲート'); return next; continue;
      end if;
      if coalesce((select is_family_daily_report_required(v_child, p_business_date)), false)
         and not coalesce((select has_family_daily_report_submitted(v_child, p_business_date)), false) then
        out_child_id := v_child; result := 'blocked'; reason := '家庭連絡帳が未提出です'; return next; continue;
      end if;
      perform cancel_child_absence_for_day(v_child, p_business_date);
      select coalesce(ds.status, 'not_arrived') into v_status from daily_child_status ds
        where ds.child_id = v_child and ds.business_date = p_business_date;
      if coalesce(v_status, 'not_arrived') = 'present' then
        out_child_id := v_child; result := 'skipped'; reason := '既に登園済み'; return next; continue;
      end if;
      insert into child_attendance_events (child_id, event_type, occurred_at, recorded_by_guardian_id)
      values (v_child, 'drop_off', now(), v_session.guardian_id);
      perform refresh_daily_child_status(v_child, p_business_date);
      out_child_id := v_child; result := 'checked_in'; reason := null; return next;

    elsif v_action = 'checkout' then
      select coalesce(ds.status, 'not_arrived') into v_status from daily_child_status ds
        where ds.child_id = v_child and ds.business_date = p_business_date;
      if coalesce(v_status, 'not_arrived') <> 'present' then
        out_child_id := v_child; result := 'skipped'; reason := '在園中ではありません'; return next; continue;
      end if;
      insert into child_attendance_events (child_id, event_type, occurred_at, recorded_by_guardian_id)
      values (v_child, 'pick_up', now(), v_session.guardian_id);
      perform refresh_daily_child_status(v_child, p_business_date);
      out_child_id := v_child; result := 'checked_out'; reason := null; return next;
    else
      out_child_id := v_child; result := 'skipped'; reason := '不明なアクション'; return next;
    end if;
  end loop;
end;
$$;

revoke execute on function apply_family_checkin(uuid, jsonb, date) from public;
grant execute on function apply_family_checkin(uuid, jsonb, date) to service_role;
