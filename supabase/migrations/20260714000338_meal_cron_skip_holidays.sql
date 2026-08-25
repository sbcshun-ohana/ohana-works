-- 338: 食数自動算出(9:31 cron)を休園日にスキップする(給食管理 §4.2・俊指示 2026-08-25)。
--   従来 cron_compute_meal_counts は給食ON全施設を無条件に算出しており、休園日(全社休日・施設の
--   非稼働曜日=日曜/土日など)でも在籍児が計上され誤カウントになっていた。
--   スキップ条件: (1) holidays に当日がある(national_holiday/year_end_new_year/company_holiday)、
--                 または (2) その施設の当日曜日が稼働日でない(office_pickup_deadlines.is_operating_day)。
--   ※手動の compute_meal_counts は管理者判断のため対象外(スキップしない)。
create or replace function cron_compute_meal_counts()
returns void
language plpgsql security definer set search_path = public
as $$
declare o record; v_today date := (now() at time zone 'Asia/Tokyo')::date; v_dow int := extract(dow from (now() at time zone 'Asia/Tokyo'))::int;
begin
  -- 全社休日(祝日・年末年始・会社休業)は全施設スキップ。
  if exists (select 1 from holidays h where h.holiday_date = v_today) then
    return;
  end if;

  for o in
    select id as office_id from offices where is_feature_enabled_for_office('meal_management_enabled', id)
  loop
    -- 施設の当日曜日が稼働日として登録されていなければスキップ(明示的に稼働日のみ算出)。
    if not exists (
      select 1 from office_pickup_deadlines d
      where d.office_id = o.office_id and d.day_of_week = v_dow and d.is_operating_day = true
    ) then
      continue;
    end if;
    perform meal_compute_internal(o.office_id, v_today);
  end loop;
end;
$$;
