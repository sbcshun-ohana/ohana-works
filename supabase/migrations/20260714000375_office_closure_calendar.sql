-- 375: 登降園管理 — 施設別 休園日カレンダー(本案§1-#9 / §10-2 / §7-1)。
--   既存 holidays(049で2025-2027の国民の祝日+年末年始をseed済)は「全社共通の祝日」。
--   office_pickup_deadlines(081)は「施設×曜日の稼働可否」(日曜休園等)。
--   両者では「祝日以外の園独自の個別休園日」を表現できないため、本テーブルを新設する。
--   休園判定 = 非稼働曜日 or 国民の祝日/年末年始 or 園独自休園日。出席簿の開所日数/網掛け・行政報告の日祝欄に使用。

-- ============================================================
-- (1) 施設別 園独自休園日(祝日以外)
-- ============================================================
create table office_closure_days (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id) on delete cascade,
  closure_date date not null,
  note text,                                   -- 例: 開園記念日 / 夏季休園 等
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  unique (office_id, closure_date)
);
alter table office_closure_days enable row level security;
create policy ocd_select on office_closure_days for select using (is_childcare_staff());

-- ============================================================
-- (2) 施設×日が「休園」か(非稼働曜日 / 国民の祝日・年末年始 / 園独自休園日)
--   ※祝日は national_holiday/year_end_new_year のみ(company_holiday=給与用で保育の休園とは無関係。
--     338給食cronは全タイプでスキップするが、休園判定は保育の開所日基準のため national/year_end に限定)。
--   ※開所情報のみで機微性が低いため authenticated に開放(出席簿・行政報告集計から再利用する内部関数)。
-- ============================================================
create or replace function is_office_closed(p_office uuid, p_date date)
returns boolean language sql stable security definer set search_path = public as $$
  select
    not exists (
      select 1 from office_pickup_deadlines d
      where d.office_id = p_office and d.day_of_week = extract(dow from p_date)::int and d.is_operating_day = true
    )
    or exists (
      select 1 from holidays h where h.holiday_date = p_date and h.holiday_type in ('national_holiday', 'year_end_new_year')
    )
    or exists (
      select 1 from office_closure_days c where c.office_id = p_office and c.closure_date = p_date
    );
$$;
grant execute on function is_office_closed(uuid, date) to authenticated, service_role;

-- ============================================================
-- (3) 開所日数(その月に開所している日数)。出席簿の開所日数欄。
-- ============================================================
create or replace function count_office_open_days(p_office uuid, p_year int, p_month int)
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int
  from generate_series(
    make_date(p_year, p_month, 1),
    (make_date(p_year, p_month, 1) + interval '1 month - 1 day')::date,
    interval '1 day'
  ) gs
  where not is_office_closed(p_office, gs::date);
$$;
grant execute on function count_office_open_days(uuid, int, int) to authenticated, service_role;

-- ============================================================
-- (4) 月カレンダー(各日: 休園か・理由・ラベル)。休園日管理画面/出席簿の網掛け用。
--   reason: weekday_off(定休曜日) / holiday(祝日) / custom(園独自) / null(開所)
-- ============================================================
create or replace function fetch_office_closure_calendar(p_office uuid, p_year int, p_month int)
returns table (business_date date, closed boolean, reason text, label text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not manages_childcare(p_office) then raise exception 'not authorized'; end if;
  if p_month not between 1 and 12 then raise exception 'invalid month'; end if;
  return query
  with days as (
    select gs::date as d
    from generate_series(
      make_date(p_year, p_month, 1),
      (make_date(p_year, p_month, 1) + interval '1 month - 1 day')::date,
      interval '1 day'
    ) gs
  )
  select dy.d,
    (op.is_operating_day is not true or h.holiday_date is not null or c.closure_date is not null) as closed,
    case
      when op.is_operating_day is not true then 'weekday_off'
      when h.holiday_date is not null then 'holiday'
      when c.closure_date is not null then 'custom'
      else null
    end as reason,
    case
      when op.is_operating_day is not true then '定休日'
      when h.holiday_date is not null then h.name
      when c.closure_date is not null then coalesce(nullif(c.note, ''), '休園')
      else null
    end as label
  from days dy
  left join office_pickup_deadlines op on op.office_id = p_office and op.day_of_week = extract(dow from dy.d)::int
  left join holidays h on h.holiday_date = dy.d and h.holiday_type in ('national_holiday', 'year_end_new_year')
  left join office_closure_days c on c.office_id = p_office and c.closure_date = dy.d
  order by dy.d;
end $$;
grant execute on function fetch_office_closure_calendar(uuid, int, int) to authenticated, service_role;

-- ============================================================
-- (5) 園独自休園日の登録/削除(施設管理者以上)。祝日・定休曜日はマスター側で自動のため対象外。
-- ============================================================
create or replace function set_office_closure_day(p_office uuid, p_date date, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_childcare_admin(p_office) then raise exception 'not authorized'; end if;
  insert into office_closure_days (office_id, closure_date, note, created_by)
    values (p_office, p_date, p_note, my_employee_id())
  on conflict (office_id, closure_date) do update set note = excluded.note;
end $$;
grant execute on function set_office_closure_day(uuid, date, text) to authenticated, service_role;

create or replace function delete_office_closure_day(p_office uuid, p_date date)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_childcare_admin(p_office) then raise exception 'not authorized'; end if;
  delete from office_closure_days where office_id = p_office and closure_date = p_date;
end $$;
grant execute on function delete_office_closure_day(uuid, date) to authenticated, service_role;
