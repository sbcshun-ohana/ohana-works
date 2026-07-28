-- fetch_employees_tax_withholding_status() の列名衝突を修正する。
--
-- 不具合: 戻り値のOUTパラメータ名(employee_id, tax_column,
-- social_insurance_dependent_count, income_tax_dependent_count, submitted_flag,
-- effective_start_year_month)が、lateralサブクエリ内で無修飾のまま参照している
-- tax_withholding_statuses の実列名と全て衝突しており、呼び出すたびに
-- "column reference ... is ambiguous"で必ず失敗していた(bulk_promote_childrenと
-- 同一パターン。135番のchild_id修正と同じ原因)。
-- 本番の/employeesページで実機確認し、"column reference \"tax_column\" is ambiguous"
-- を実際に確認済み。/payrollのイベント直行日通勤費・特殊業務手当パネルも同じRPCを
-- 職員選択肢の取得に流用しており、エラーを握りつぶして職員選択肢が空になっていた。
--
-- 修正: lateralサブクエリのFROM句にエイリアス(t)を付け、選択列・WHERE句・ORDER BYの
-- 全参照をt.で明示的に修飾する。戻り値の列名・型・順序は変更しない(呼び出し元との
-- 互換性を保つ)。

create or replace function fetch_employees_tax_withholding_status()
returns table (
  employee_id uuid, employee_name text, office_name text, tax_column text,
  social_insurance_dependent_count integer, income_tax_dependent_count integer,
  submitted_flag boolean, effective_start_year_month date
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_labor_manager_plus() then
    raise exception 'not authorized';
  end if;

  perform log_sensitive_access(
    '源泉徴収区分・扶養人数一覧(fetch_employees_tax_withholding_status)',
    null,
    '源泉徴収区分・扶養人数一覧(全職員)'
  );

  return query
  select
    e.id, e.name, o.name,
    tws.tax_column, tws.social_insurance_dependent_count, tws.income_tax_dependent_count,
    tws.submitted_flag, tws.effective_start_year_month
  from employees e
  join offices o on o.id = e.home_office_id
  left join lateral (
    select t.tax_column, t.social_insurance_dependent_count, t.income_tax_dependent_count,
           t.submitted_flag, t.effective_start_year_month
    from tax_withholding_statuses t
    where t.employee_id = e.id and t.effective_start_year_month <= current_date
    order by t.effective_start_year_month desc
    limit 1
  ) tws on true
  where e.resignation_date is null
  order by e.name;
end;
$$;
