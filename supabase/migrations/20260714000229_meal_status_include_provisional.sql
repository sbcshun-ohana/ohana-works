-- 229: 給食状態一覧に入園予定児を含める(俊指摘 2026-08-18・staging適用済)。
-- 入園前に食材チェック・診断書を進める実運用のため、fetch_meal_status_for_office の対象を
-- 在籍中+入園予定に拡大し、在籍状況列を追加する(戻り型変更のため drop→create)。
drop function if exists fetch_meal_status_for_office(uuid);

create function fetch_meal_status_for_office(p_office_id uuid)
returns table (
  child_id uuid,
  child_name text,
  class_name text,
  enrollment_status text,
  meal_status text,
  candidate_stage text,
  current_stage text,
  approved_stage text,
  approved_serving_start date
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not is_childcare_admin(p_office_id) then
    raise exception 'not authorized';
  end if;
  return query
  select c.id, c.display_name, cc.class_name, c.enrollment_status,
    s.meal_status, s.candidate_stage, s.current_stage, s.approved_stage, s.approved_serving_start
  from children c
  left join child_class_enrollments cce on cce.child_id = c.id and cce.effective_end_date is null
  left join childcare_classes cc on cc.id = cce.class_id
  cross join lateral fetch_child_meal_status(c.id) s
  where c.office_id = p_office_id and c.enrollment_status in ('在籍中', '入園予定')
  order by (c.enrollment_status = '入園予定'), cc.class_name, c.display_name;
end;
$$;
