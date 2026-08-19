-- 259: 給食管理 Phase 2。厨房ページの変更アラートの「確認」操作(俊指定§5.2)。
-- 未確認の変更(meal_count_changes.acknowledged_at is null)を、現在の職員が確認済みにする。
-- 厨房端末で「更新があります」→タップで変更前→後を確認→この確認で通常表示に戻す。
create or replace function acknowledge_meal_changes(p_office_id uuid, p_business_date date)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  update meal_count_changes
    set acknowledged_by = my_employee_id(), acknowledged_at = now()
  where office_id = p_office_id and business_date = p_business_date and acknowledged_at is null;
end;
$$;
grant execute on function acknowledge_meal_changes(uuid, date) to authenticated, service_role;
