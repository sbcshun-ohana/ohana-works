-- 365: 職員給食 自己注文モデル M1 — 曜日テンプレ(俊指示 2026-08-27・設計ロック)。
--   従来の「シフト由来の給食自動算出」を廃止し、本人の事前注文を給食数・請求の源泉にする再設計の第1段。
--   本migrationは曜日テンプレ(既定=これに従って毎週◯が入る)の器とCRUDのみ。
--   参加スナップショット(participation)への反映・提供なし・締め切り等は後続 M2〜M4。
--   weekday は shift_weekly_templates(113) と同一規約: 0=月曜 〜 6=日曜。1人1日1食(喫食施設=既定は主所属home_office_id)。

-- ============================================================
-- (1) 曜日テンプレ本体
-- ============================================================
create table staff_meal_weekly_templates (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  weekday int not null check (weekday between 0 and 6),  -- 0=月曜 〜 6=日曜
  will_eat boolean not null default false,               -- true=その曜日は毎週食べる
  office_id uuid references offices(id),                 -- 喫食施設。null=読み取り時に主所属home_office_idで解決(異動に追従)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (employee_id, weekday)                          -- 1人1曜日1行(= (employee_id, weekday) の複合uniqueindexも兼ねる)
);
alter table staff_meal_weekly_templates enable row level security;
-- 参照: 本人 + 保育職員(朝の発注画面/職員給食表で他職員の予定を集計表示するため。既存 staff_meal_entries と同方針)。
create policy smwt_select on staff_meal_weekly_templates
  for select using (employee_id = my_employee_id() or is_childcare_staff());

-- ============================================================
-- (2) 本人が曜日テンプレを設定(食べる/食べない・喫食施設は任意)
-- ============================================================
create or replace function set_staff_meal_weekly_template(p_weekday int, p_will_eat boolean, p_office_id uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_emp uuid;
begin
  v_emp := my_employee_id();
  if v_emp is null then raise exception 'not authorized'; end if;
  if p_weekday is null or p_weekday < 0 or p_weekday > 6 then raise exception 'weekday must be 0..6'; end if;
  if p_will_eat is null then raise exception 'will_eat is required'; end if;
  -- office_id は任意。null のまま保存し、読み取り(集計)時に主所属home_office_idへ解決する(異動追従)。
  insert into staff_meal_weekly_templates (employee_id, weekday, will_eat, office_id)
    values (v_emp, p_weekday, p_will_eat, p_office_id)
  on conflict (employee_id, weekday) do update
    set will_eat = excluded.will_eat, office_id = excluded.office_id, updated_at = now();
end $$;
grant execute on function set_staff_meal_weekly_template(int, boolean, uuid) to authenticated, service_role;

-- ============================================================
-- (3) 本人の曜日テンプレを取得(未設定曜日は返らない。UI側で 0..6 を埋める)
-- ============================================================
create or replace function fetch_staff_meal_weekly_template()
returns table (weekday int, will_eat boolean, office_id uuid)
language sql stable security definer set search_path = public as $$
  select weekday, will_eat, office_id
  from staff_meal_weekly_templates
  where employee_id = my_employee_id()
  order by weekday;
$$;
grant execute on function fetch_staff_meal_weekly_template() to authenticated, service_role;

-- ============================================================
-- (4) 既存職員の初期テンプレ移行(冪等)
--   シフト曜日テンプレ(shift_weekly_templates)のある曜日を初期値として、
--   その職員の喫食既定(employee_meal_settings.eats_default・既定true)に従って will_eat を設定。
--   施設はシフトテンプレの office_id を採用。既にテンプレ行があれば温存(do nothing)。
--   ※eats_default は本モデルで曜日テンプレへ一本化(以後は本テーブルが正)。
-- ============================================================
insert into staff_meal_weekly_templates (employee_id, weekday, will_eat, office_id)
select swt.employee_id, swt.weekday,
       coalesce(ems.eats_default, true) as will_eat,
       swt.office_id
from shift_weekly_templates swt
left join employee_meal_settings ems on ems.employee_id = swt.employee_id
on conflict (employee_id, weekday) do nothing;
