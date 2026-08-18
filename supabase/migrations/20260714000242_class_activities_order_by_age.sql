-- 242: クラス活動一覧のクラス並び順を年齢順(0歳→5歳)に統一。
-- fetch_childcare_classes(162)と同じ規則 order by age_group, class_name に合わせる
-- (従来は class_name の五十音順=かぜ/そら/つき/にじ/はな/ほし で年齢順と食い違っていた)。
-- 返却列は変更なし(ORDER BYのみ変更のため drop 不要)。
create or replace function fetch_class_activities_for_office(p_office_id uuid, p_business_date date)
returns table (
  activity_id uuid,
  class_id uuid,
  class_name text,
  assignee_employee_id uuid,
  assignee_name text,
  status text,
  today_theme text,
  activity_content text,
  class_overview text,
  class_announcement text,
  other_notes text,
  submitted_at timestamptz,
  rejected_reason text
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
    cda.id, cc.id, cc.class_name,
    cda.assignee_employee_id, e.name,
    cda.status, cda.today_theme, cda.activity_content, cda.class_overview,
    cda.class_announcement, cda.other_notes, cda.submitted_at, cda.rejected_reason
  from childcare_classes cc
  left join class_daily_activities cda on cda.class_id = cc.id and cda.business_date = p_business_date
  left join employees e on e.id = cda.assignee_employee_id
  where cc.office_id = p_office_id and cc.is_active
  order by cc.age_group, cc.class_name;
end;
$$;
