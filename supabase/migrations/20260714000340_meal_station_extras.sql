-- 340: Mahalo Station固有欄(給食管理 §4.2・俊指示 2026-08-25)。
--   「今日の牛乳○本」=手入力(meal_count_days.milk_bottles)。「明日のおやつ」=翌日の登園予定数(非欠席の在籍児)。
--   いずれもMahalo Station(office_code='S')のみ画面に出す(is_station フラグで出し分け)。
--   牛乳の算出根拠(§14-2)は手入力とする(俊確定・自動目安は将来)。

-- 今日の牛乳本数を保存(職員以上・その施設の保育アクセス)。
create or replace function set_milk_bottles(p_office uuid, p_date date, p_count int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office) then raise exception 'not authorized'; end if;
  insert into meal_count_days (office_id, business_date, milk_bottles)
  values (p_office, p_date, p_count)
  on conflict (office_id, business_date) do update set milk_bottles = excluded.milk_bottles, updated_at = now();
end $$;
grant execute on function set_milk_bottles(uuid, date, int) to authenticated, service_role;

-- Station固有欄の取得: is_station・牛乳本数・明日のおやつ(翌日の非欠席在籍児数)。
create or replace function fetch_meal_station_extras(p_office uuid, p_date date)
returns table (is_station boolean, milk_bottles int, next_day_snack int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_childcare_staff() then raise exception 'not authorized'; end if;
  return query
  select
    (select o.office_code = 'S' from offices o where o.id = p_office),
    (select d.milk_bottles from meal_count_days d where d.office_id = p_office and d.business_date = p_date),
    (select count(*)::int
       from children c
       join child_class_enrollments cce on cce.child_id = c.id and cce.effective_end_date is null
       where c.office_id = p_office and c.enrollment_status = '在籍中'
         and not exists (
           select 1 from child_daily_attendance a
           where a.child_id = c.id and a.business_date = p_date + 1 and a.is_absent
         ));
end $$;
grant execute on function fetch_meal_station_extras(uuid, date) to authenticated, service_role;
