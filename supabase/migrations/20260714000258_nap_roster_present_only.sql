-- 258: 午睡チェックの名簿を「登園済みの園児のみ」に絞る(俊指摘 2026-08-19)。
-- 午睡画面の名簿は fetch_children_for_office / fetch_class_children(全在籍児)から作られており、
-- fetch_nap_board(251・セッション起点)を絞っても名簿は絞られなかった。名簿専用RPCを新設する。
-- 表示=daily_child_status.status IN ('present','picked_up') かつ 欠席でない。
create or replace function fetch_nap_roster(p_office_id uuid, p_class_id uuid, p_business_date date)
returns table (child_id uuid, display_name text, honorific_suffix text, class_id uuid, class_name text)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  return query
  select c.id, c.display_name, c.honorific_suffix_resolved, cc.id, cc.class_name
  from children c
  join child_class_enrollments cce on cce.child_id = c.id and cce.effective_end_date is null
  join childcare_classes cc on cc.id = cce.class_id
  join daily_child_status ds
    on ds.child_id = c.id and ds.business_date = p_business_date and ds.status in ('present', 'picked_up')
  where c.office_id = p_office_id
    and c.enrollment_status = '在籍中'
    and not exists (
      select 1 from child_daily_attendance a
      where a.child_id = c.id and a.business_date = p_business_date and a.is_absent
    )
    and (p_class_id is null or cc.id = p_class_id)
  order by cc.age_group, cc.class_name, c.display_name;
end;
$$;
grant execute on function fetch_nap_roster(uuid, uuid, date) to authenticated, service_role;
