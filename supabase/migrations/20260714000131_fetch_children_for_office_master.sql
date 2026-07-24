-- 園児マスタ画面(/childcare/children)用のRPC。
-- 施設内の在籍園児の基本情報と、連絡帳提出必須の適用期間設定状況を返す。
-- クラスでの絞り込みは画面側(クライアント)で行う想定(施設あたりの件数が少ないため)。
create or replace function fetch_children_for_office_master(p_office_id uuid)
returns table (
  child_id uuid,
  display_name text,
  honorific_suffix text,
  gender text,
  birth_date date,
  enrollment_status text,
  class_id uuid,
  class_name text,
  class_family_daily_report_required boolean,
  family_daily_report_required_from date,
  family_daily_report_required_until date
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
    c.id, c.display_name, c.honorific_suffix_resolved, c.gender, c.birth_date, c.enrollment_status,
    cc.id, cc.class_name, cc.family_daily_report_required,
    c.family_daily_report_required_from, c.family_daily_report_required_until
  from children c
  left join child_class_enrollments cce on cce.child_id = c.id and cce.effective_end_date is null
  left join childcare_classes cc on cc.id = cce.class_id
  where c.office_id = p_office_id and c.enrollment_status <> '退園済み'
  order by cc.class_name, c.display_name;
end;
$$;
