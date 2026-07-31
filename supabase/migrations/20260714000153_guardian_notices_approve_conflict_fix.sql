-- 152 の approve_guardian_notice バグ修正(拒否側E2Eで発覚)。
-- uq_gnr_unique は「制約」ではなく「ユニークインデックス」のため、on conflict on constraint では
-- 参照できず「constraint does not exist」になる。カラム指定の on conflict へ変更(挙動は同一)。
create or replace function approve_guardian_notice(p_notice_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare v_status text;
begin
  select status into v_status from guardian_notices where id = p_notice_id;
  if v_status is null then raise exception 'not found'; end if;
  if v_status not in ('draft', 'in_review') then raise exception 'invalid state'; end if;
  if not is_guardian_notice_approver(p_notice_id) then
    raise exception 'not authorized to approve';
  end if;

  insert into guardian_notice_recipients (notice_id, guardian_id, child_id)
  select p_notice_id, r.guardian_id, r.child_id
  from resolve_guardian_notice_recipients(p_notice_id) r
  on conflict (notice_id, guardian_id, child_id) do nothing;

  update guardian_notices
  set status = 'approved', approver_id = my_employee_id(), approved_at = now(), sent_at = now()
  where id = p_notice_id;
end;
$$;
