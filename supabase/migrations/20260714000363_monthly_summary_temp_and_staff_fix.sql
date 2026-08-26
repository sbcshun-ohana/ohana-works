-- 363: 月次集計の是正(俊指示 2026-08-27)。
--   (A) 職員合計(am/lunch/pm_staff)を「職員(事務室)行のみ」に修正。360で大和の児童行に
--       盛り付け配分の staff_count が入るようになり、全行合算だと職員食が二重計上されていた(#1と同根)。
--   (B) 一時保育(row_type='temp_care', meal_stage=null)の食数が late/complete/toddler の内訳から漏れ、
--       月次表・Excelに出ていなかった。区分ごとに *_temp 列を追加して可視化(#2)。
--       これで各区分 child = late + complete + toddler + temp が成立する。
--   戻り値追加のため drop→再作成。既存列名は不変(UIは追加列のみ拾う)。
drop function if exists fetch_meal_monthly_summary(uuid, int, int);
create function fetch_meal_monthly_summary(p_office_id uuid, p_year int, p_month int)
returns table (
  business_date date,
  am_child int, am_staff int, am_late int, am_complete int, am_toddler int, am_temp int,
  lunch_child int, lunch_staff int, lunch_late int, lunch_complete int, lunch_toddler int, lunch_temp int,
  pm_child int, pm_staff int, pm_late int, pm_complete int, pm_toddler int, pm_temp int,
  leftover_grams int
)
language plpgsql stable security definer set search_path = public as $$
declare v_start date; v_end date;
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  v_start := make_date(p_year, p_month, 1);
  v_end := (v_start + interval '1 month - 1 day')::date;
  return query
    with days as (
      select distinct mr.business_date from meal_count_rows mr
        where mr.office_id = p_office_id and mr.business_date between v_start and v_end
      union
      select cd.business_date from meal_count_days cd
        where cd.office_id = p_office_id and cd.business_date between v_start and v_end and cd.leftover_grams is not null
    )
    select d.business_date,
      -- 午前おやつ
      coalesce(sum(mr.child_count) filter (where mr.meal_slot = 'am_snack'), 0)::int,
      coalesce(sum(mr.staff_count) filter (where mr.meal_slot = 'am_snack' and rd.row_type = 'staff'), 0)::int,
      coalesce(sum(mr.child_count) filter (where mr.meal_slot = 'am_snack' and rd.meal_stage = 'late'), 0)::int,
      coalesce(sum(mr.child_count) filter (where mr.meal_slot = 'am_snack' and rd.meal_stage = 'complete'), 0)::int,
      coalesce(sum(mr.child_count) filter (where mr.meal_slot = 'am_snack' and rd.row_type = 'children' and (rd.meal_stage = 'toddler' or rd.meal_stage is null)), 0)::int,
      coalesce(sum(mr.child_count) filter (where mr.meal_slot = 'am_snack' and rd.row_type = 'temp_care'), 0)::int,
      -- 昼食
      coalesce(sum(mr.child_count) filter (where mr.meal_slot = 'lunch'), 0)::int,
      coalesce(sum(mr.staff_count) filter (where mr.meal_slot = 'lunch' and rd.row_type = 'staff'), 0)::int,
      coalesce(sum(mr.child_count) filter (where mr.meal_slot = 'lunch' and rd.meal_stage = 'late'), 0)::int,
      coalesce(sum(mr.child_count) filter (where mr.meal_slot = 'lunch' and rd.meal_stage = 'complete'), 0)::int,
      coalesce(sum(mr.child_count) filter (where mr.meal_slot = 'lunch' and rd.row_type = 'children' and (rd.meal_stage = 'toddler' or rd.meal_stage is null)), 0)::int,
      coalesce(sum(mr.child_count) filter (where mr.meal_slot = 'lunch' and rd.row_type = 'temp_care'), 0)::int,
      -- 午後おやつ
      coalesce(sum(mr.child_count) filter (where mr.meal_slot = 'pm_snack'), 0)::int,
      coalesce(sum(mr.staff_count) filter (where mr.meal_slot = 'pm_snack' and rd.row_type = 'staff'), 0)::int,
      coalesce(sum(mr.child_count) filter (where mr.meal_slot = 'pm_snack' and rd.meal_stage = 'late'), 0)::int,
      coalesce(sum(mr.child_count) filter (where mr.meal_slot = 'pm_snack' and rd.meal_stage = 'complete'), 0)::int,
      coalesce(sum(mr.child_count) filter (where mr.meal_slot = 'pm_snack' and rd.row_type = 'children' and (rd.meal_stage = 'toddler' or rd.meal_stage is null)), 0)::int,
      coalesce(sum(mr.child_count) filter (where mr.meal_slot = 'pm_snack' and rd.row_type = 'temp_care'), 0)::int,
      cd.leftover_grams
    from days d
    left join meal_count_rows mr on mr.office_id = p_office_id and mr.business_date = d.business_date
    left join meal_row_definitions rd on rd.office_id = mr.office_id and rd.row_key = mr.row_key
    left join meal_count_days cd on cd.office_id = p_office_id and cd.business_date = d.business_date
    group by d.business_date, cd.leftover_grams
    order by d.business_date;
end $$;
grant execute on function fetch_meal_monthly_summary(uuid, int, int) to authenticated, service_role;
