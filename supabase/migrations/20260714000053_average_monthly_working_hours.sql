-- 16.4 割増賃金の基礎単価: 年平均月間所定労働時間の登録・取得RPC。
--
-- average_monthly_working_hoursテーブル(20260710160004で定義済み)は
-- これまで一度も値が登録されておらず、月給者の残業・深夜・休日労働の
-- 割増単価計算がすべて0円になってしまう状態だった(run_payroll側では
-- prescribed_hours_missingとして既に検知済み)。個別登録用RPCを追加する。

create or replace function set_average_monthly_working_hours(
  p_fiscal_year int,
  p_hours numeric,
  p_note text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not is_labor_manager_plus() then
    raise exception 'not authorized';
  end if;
  if p_fiscal_year is null then
    raise exception 'fiscal_year is required';
  end if;
  if p_hours is null or p_hours <= 0 then
    raise exception 'hours must be greater than 0';
  end if;

  insert into average_monthly_working_hours (fiscal_year, hours, note)
  values (p_fiscal_year, p_hours, p_note)
  on conflict (fiscal_year) do update set
    hours = excluded.hours,
    note = excluded.note
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function fetch_average_monthly_working_hours()
returns table (fiscal_year int, hours numeric, note text)
language sql
stable
security definer
set search_path = public
as $$
  select fiscal_year, hours, note from average_monthly_working_hours order by fiscal_year desc;
$$;

-- 2026年度分を登録する。
-- 算出根拠: 正社員の月ごとの年間休日日数(勤務表ベース、合計111日)。
--   年間労働日数 = 365日 - 111日 = 254日
--   年平均月間所定労働時間 = 254日 × 8時間(就業規則第8条の所定労働時間) ÷ 12ヶ月
--                       = 169.33時間(169時間20分)
insert into average_monthly_working_hours (fiscal_year, hours, note)
values (
  2026,
  169.33,
  '正社員月ごとの年間休日日数(勤務表ベース、合計111日)により算出。年間労働日数254日×所定労働時間8時間(就業規則第8条)÷12ヶ月=169.33時間。'
)
on conflict (fiscal_year) do update set
  hours = excluded.hours,
  note = excluded.note;
