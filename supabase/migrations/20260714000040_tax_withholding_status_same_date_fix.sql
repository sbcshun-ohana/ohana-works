-- set_employee_tax_withholding_status()のバグ修正。
--
-- 既存の「現在有効(終了日未設定)」行を閉じる条件が
-- effective_start_year_month < p_effective_start_year_month (厳密未満)に
-- なっており、同一開始年月での「訂正」(例: 扶養人数の入力誤りをその場で
-- 直す)を行うと、新旧2行が同時にeffective_end_year_month=nullのまま
-- 残ってしまう(施設別賃金の同日付クローズ漏れと同種のバグ、
-- 20260714000038で修正した問題と同じクラス)。
--
-- 開始年月が完全に一致する行は「同一期間の訂正」とみなし削除する
-- (end = start - 1ヶ月とすると終了日が開始日より前になり不正なため)。
-- 開始年月が新規行より前の行は、従来通り前月末で終了させる。

create or replace function set_employee_tax_withholding_status(
  p_employee_id uuid,
  p_tax_column text,
  p_social_insurance_dependent_count int,
  p_income_tax_dependent_count int,
  p_submitted_flag boolean,
  p_effective_start_year_month date
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_id uuid;
begin
  if not is_labor_manager_plus() then
    raise exception 'not authorized';
  end if;
  if p_tax_column not in ('甲欄', '乙欄') then
    raise exception 'invalid tax_column: % (must be 甲欄 or 乙欄)', p_tax_column;
  end if;
  if p_social_insurance_dependent_count is null or p_social_insurance_dependent_count < 0 then
    raise exception 'social_insurance_dependent_count must be 0 or greater';
  end if;
  if p_income_tax_dependent_count is null or p_income_tax_dependent_count < 0 then
    raise exception 'income_tax_dependent_count must be 0 or greater';
  end if;

  delete from tax_withholding_statuses
  where employee_id = p_employee_id
    and effective_end_year_month is null
    and effective_start_year_month = p_effective_start_year_month;

  update tax_withholding_statuses
  set effective_end_year_month = (p_effective_start_year_month - interval '1 month')::date
  where employee_id = p_employee_id
    and effective_end_year_month is null
    and effective_start_year_month < p_effective_start_year_month;

  insert into tax_withholding_statuses (
    employee_id, submitted_flag, tax_column,
    social_insurance_dependent_count, income_tax_dependent_count,
    effective_start_year_month, created_by
  ) values (
    p_employee_id, p_submitted_flag, p_tax_column,
    p_social_insurance_dependent_count, p_income_tax_dependent_count,
    p_effective_start_year_month, my_employee_id()
  )
  returning id into v_new_id;

  return v_new_id;
end;
$$;
