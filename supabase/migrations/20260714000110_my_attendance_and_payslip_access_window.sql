-- 開発計画(改訂版 2026-07-17) Phase 1 / A: 職員セルフビュー基盤。
-- A-2: 自分の勤怠(月間・施設別)を集計テーブルではなく生データ(daily_attendances)から
--      組み立てるRPC。施設帰属の推定ロジックはadmin側のfetch_attendance_by_officeと同じ
--      (当日最初のtime_punches.office_idを採用、無ければhome_office_id)。
-- A-3: 給与明細(payslips)の本人アクセスを退職後6ヶ月で打ち切る。テーブル行だけでなく
--      Storage側(実ファイル)のポリシーも同様に更新する(片方だけではPDF実体に無期限で
--      アクセスできてしまうため)。労務管理者側の閲覧権限は退職者分も含めて維持する。

create or replace function fetch_my_attendance(p_month_start date, p_month_end date)
returns table (
  work_date date,
  office_id uuid,
  office_name text,
  actual_clock_in_at timestamptz,
  approved_work_start_at timestamptz,
  actual_clock_out_at timestamptz,
  approved_work_end_at timestamptz,
  actual_break_start_at timestamptz,
  actual_break_end_at timestamptz,
  approved_break_minutes int,
  shift_type text,
  alert_codes text[]
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if my_employee_id() is null then
    raise exception 'not authorized';
  end if;

  return query
  select
    da.work_date,
    coalesce(rep.office_id, e.home_office_id),
    o.name,
    da.actual_clock_in_at,
    da.approved_work_start_at,
    da.actual_clock_out_at,
    da.approved_work_end_at,
    da.actual_break_start_at,
    da.actual_break_end_at,
    da.approved_break_minutes,
    da.shift_type::text,
    da.alert_codes
  from daily_attendances da
  join employees e on e.id = da.employee_id
  left join lateral (
    select tp.office_id
    from time_punches tp
    where tp.employee_id = da.employee_id
      and tp.punched_at >= (da.work_date::timestamp) at time zone 'Asia/Tokyo'
      and tp.punched_at < (da.work_date::timestamp + interval '1 day') at time zone 'Asia/Tokyo'
    order by tp.punched_at asc
    limit 1
  ) rep on true
  join offices o on o.id = coalesce(rep.office_id, e.home_office_id)
  where da.employee_id = my_employee_id()
    and da.work_date between p_month_start and p_month_end
  order by da.work_date;
end;
$$;

create or replace function is_within_payslip_access_window(p_employee_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select resignation_date from employees where id = p_employee_id) is null
    or (select resignation_date from employees where id = p_employee_id) + interval '6 months' >= current_date,
    false
  );
$$;

comment on function is_within_payslip_access_window(uuid) is
  '本人の給与明細アクセス可否(退職日から6ヶ月以内、または在職中ならtrue)。
   労務管理者側の閲覧権限(is_labor_manager_plus())には適用しない。';

drop policy payslips_select_self on payslips;
create policy payslips_select_self on payslips
  for select using (employee_id = my_employee_id() and is_within_payslip_access_window(my_employee_id()));

drop policy payslips_storage_select on storage.objects;
create policy payslips_storage_select on storage.objects
  for select using (
    bucket_id = 'payslips'
    and (
      is_labor_manager_plus()
      or (
        (storage.foldername(name))[1] = (my_employee_id())::text
        and is_within_payslip_access_window(my_employee_id())
      )
    )
  );
