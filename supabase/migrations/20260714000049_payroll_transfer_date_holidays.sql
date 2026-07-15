-- 19章/design_v1.0.md 555行目: 支払日(翌月25日、土日祝は前営業日)の自動調整。
--
-- holidaysテーブル(20260710160005で定義済み、これまで未投入)に、内閣府
-- 「国民の祝日」公式データ(https://www8.cao.go.jp/chosei/shukujitsu/syukujitsu.csv、
-- 2026-07時点で公表済みの2025〜2027年分)と、銀行休業日(12/31・1/2・1/3、
-- 銀行法施行令準拠)を投入する。2028年以降の祝日(春分の日・秋分の日は
-- 国立天文台による官報公示待ちのため未公表)は、公表され次第別途追加が必要。

insert into holidays (holiday_date, holiday_type, name) values
  ('2025-01-01', 'national_holiday', '元日'),
  ('2025-01-13', 'national_holiday', '成人の日'),
  ('2025-02-11', 'national_holiday', '建国記念の日'),
  ('2025-02-23', 'national_holiday', '天皇誕生日'),
  ('2025-02-24', 'national_holiday', '振替休日'),
  ('2025-03-20', 'national_holiday', '春分の日'),
  ('2025-04-29', 'national_holiday', '昭和の日'),
  ('2025-05-03', 'national_holiday', '憲法記念日'),
  ('2025-05-04', 'national_holiday', 'みどりの日'),
  ('2025-05-05', 'national_holiday', 'こどもの日'),
  ('2025-05-06', 'national_holiday', '振替休日'),
  ('2025-07-21', 'national_holiday', '海の日'),
  ('2025-08-11', 'national_holiday', '山の日'),
  ('2025-09-15', 'national_holiday', '敬老の日'),
  ('2025-09-23', 'national_holiday', '秋分の日'),
  ('2025-10-13', 'national_holiday', 'スポーツの日'),
  ('2025-11-03', 'national_holiday', '文化の日'),
  ('2025-11-23', 'national_holiday', '勤労感謝の日'),
  ('2025-11-24', 'national_holiday', '振替休日'),

  ('2026-01-01', 'national_holiday', '元日'),
  ('2026-01-12', 'national_holiday', '成人の日'),
  ('2026-02-11', 'national_holiday', '建国記念の日'),
  ('2026-02-23', 'national_holiday', '天皇誕生日'),
  ('2026-03-20', 'national_holiday', '春分の日'),
  ('2026-04-29', 'national_holiday', '昭和の日'),
  ('2026-05-03', 'national_holiday', '憲法記念日'),
  ('2026-05-04', 'national_holiday', 'みどりの日'),
  ('2026-05-05', 'national_holiday', 'こどもの日'),
  ('2026-05-06', 'national_holiday', '振替休日'),
  ('2026-07-20', 'national_holiday', '海の日'),
  ('2026-08-11', 'national_holiday', '山の日'),
  ('2026-09-21', 'national_holiday', '敬老の日'),
  ('2026-09-22', 'national_holiday', '振替休日'),
  ('2026-09-23', 'national_holiday', '秋分の日'),
  ('2026-10-12', 'national_holiday', 'スポーツの日'),
  ('2026-11-03', 'national_holiday', '文化の日'),
  ('2026-11-23', 'national_holiday', '勤労感謝の日'),

  ('2027-01-01', 'national_holiday', '元日'),
  ('2027-01-11', 'national_holiday', '成人の日'),
  ('2027-02-11', 'national_holiday', '建国記念の日'),
  ('2027-02-23', 'national_holiday', '天皇誕生日'),
  ('2027-03-21', 'national_holiday', '春分の日'),
  ('2027-03-22', 'national_holiday', '振替休日'),
  ('2027-04-29', 'national_holiday', '昭和の日'),
  ('2027-05-03', 'national_holiday', '憲法記念日'),
  ('2027-05-04', 'national_holiday', 'みどりの日'),
  ('2027-05-05', 'national_holiday', 'こどもの日'),
  ('2027-07-19', 'national_holiday', '海の日'),
  ('2027-08-11', 'national_holiday', '山の日'),
  ('2027-09-20', 'national_holiday', '敬老の日'),
  ('2027-09-23', 'national_holiday', '秋分の日'),
  ('2027-10-11', 'national_holiday', 'スポーツの日'),
  ('2027-11-03', 'national_holiday', '文化の日'),
  ('2027-11-23', 'national_holiday', '勤労感謝の日'),

  -- 銀行休業日(元日は国民の祝日として上で登録済みのため12/31・1/2・1/3のみ)
  ('2025-12-31', 'year_end_new_year', '銀行休業日(大晦日)'),
  ('2026-01-02', 'year_end_new_year', '銀行休業日'),
  ('2026-01-03', 'year_end_new_year', '銀行休業日'),
  ('2026-12-31', 'year_end_new_year', '銀行休業日(大晦日)'),
  ('2027-01-02', 'year_end_new_year', '銀行休業日'),
  ('2027-01-03', 'year_end_new_year', '銀行休業日'),
  ('2027-12-31', 'year_end_new_year', '銀行休業日(大晦日)'),
  ('2028-01-02', 'year_end_new_year', '銀行休業日'),
  ('2028-01-03', 'year_end_new_year', '銀行休業日')
on conflict (holiday_date) do nothing;

-- 銀行営業日か判定(土日・国民の祝日・年末年始を除く)。
-- company_holiday(会社独自の休業日)は銀行の営業可否とは無関係のため対象外とする。
create or replace function is_bank_business_day(p_date date)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select extract(dow from p_date) not in (0, 6)
    and not exists (
      select 1 from holidays
      where holiday_date = p_date and holiday_type in ('national_holiday', 'year_end_new_year')
    );
$$;

-- 銀行休業日の場合、前営業日まで繰り上げる。
create or replace function adjust_to_previous_business_day(p_date date)
returns date
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_date date := p_date;
  v_guard int := 0;
begin
  while not is_bank_business_day(v_date) loop
    v_date := v_date - 1;
    v_guard := v_guard + 1;
    if v_guard > 30 then
      raise exception 'adjust_to_previous_business_day: 30日以上遡っても営業日が見つかりません(holidaysデータ不足の可能性)';
    end if;
  end loop;
  return v_date;
end;
$$;

-- 対象月(給与計算単位のtarget_month)から支払日(翌月25日、土日祝は前営業日)を算出する。
create or replace function compute_payroll_transfer_date(p_target_month date)
returns date
language sql
stable
security definer
set search_path = public
as $$
  select adjust_to_previous_business_day(
    (date_trunc('month', p_target_month) + interval '1 month' + interval '24 days')::date
  );
$$;
