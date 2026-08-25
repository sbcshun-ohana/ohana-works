-- 325: 登降園管理の欠席理由プルダウン(病欠/都合欠/出席)用の最小RPC(俊指示 2026-08-25)。
-- set_child_attendance_status(203)は scheduled_* 等も上書きするため、種別のみを安全に更新する専用関数にする。
-- p_kind: 'none'(出席) / 'sick_absence'(病欠) / 'personal_absence'(都合欠)。is_absent は種別から導出。主任以上。
create or replace function set_child_absence_kind(p_child_id uuid, p_business_date date, p_kind text)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_kind text;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  v_kind := coalesce(nullif(p_kind, ''), 'none');
  if v_kind not in ('none', 'sick_absence', 'personal_absence') then raise exception 'invalid kind'; end if;

  insert into child_daily_attendance (child_id, business_date, is_absent, attendance_kind, changed_by, changed_at)
    values (p_child_id, p_business_date, v_kind in ('sick_absence', 'personal_absence'), v_kind, my_employee_id(), now())
  on conflict (child_id, business_date) do update
    set is_absent = excluded.attendance_kind in ('sick_absence', 'personal_absence'),
        attendance_kind = excluded.attendance_kind,
        changed_by = my_employee_id(), changed_at = now();
  perform refresh_daily_child_status(p_child_id, p_business_date);
end $$;
grant execute on function set_child_absence_kind(uuid, date, text) to authenticated, service_role;
