-- 254: 給食管理 Phase 1 ①(機能フラグ + 行区分マスタ + 大和seed)。設計指示書v1.0 §4.1/§12。
-- 行区分×食事区分の提供対象マトリクスをマスタで管理(ハードコード禁止)。単価は既存 burden_fee_masters を正とする。
-- 朝おやつ対象=0・1・2歳(はな/そら/かぜ)。3歳以上(つき/ほし/にじ)は昼食+午後おやつのみ(俊確定2026-08-19)。

-- 機能フラグ(既定OFF・施設別ON)
insert into feature_flags (feature_key, name, description, default_enabled) values
  ('meal_management_enabled', '給食管理',
   '給食管理(食数厨房ボード・職員食数・アレルギー・給食写真・献立)の施設別有効化。既定OFF、試験施設からON。', false)
on conflict (feature_key) do nothing;

create or replace function is_meal_management_enabled_for_office(p_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select is_feature_enabled_for_office('meal_management_enabled', p_office_id);
$$;
grant execute on function is_meal_management_enabled_for_office(uuid) to authenticated, service_role;

-- 行区分マスタ(施設別・提供対象マトリクス・表示順)
create table meal_row_definitions (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id),
  row_key text not null,                 -- 施設内で一意
  row_label text not null,               -- 表示名
  class_id uuid references childcare_classes(id),  -- 対象クラス(職員行/一時保育=null)
  meal_stage text check (meal_stage in ('late', 'complete', 'toddler')),  -- はな組の給食段階分割(null=分割しない)
  row_type text not null check (row_type in ('children', 'staff', 'temp_care')),
  am_snack boolean not null default false,  -- 提供対象マトリクス(朝おやつ)
  lunch boolean not null default false,     -- 昼食
  pm_snack boolean not null default false,  -- 午後おやつ
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (office_id, row_key)
);
create index idx_meal_row_definitions_office on meal_row_definitions(office_id, sort_order) where is_active;
create trigger trg_meal_row_definitions_updated_at
  before update on meal_row_definitions for each row execute function set_updated_at();
alter table meal_row_definitions enable row level security;
create policy meal_row_definitions_select on meal_row_definitions
  for select using (is_childcare_staff());
comment on table meal_row_definitions is
  '給食管理の行区分マスタ(254)。施設別の行×食事区分の提供対象。管理者以上が管理(RPCは後続)。';

-- 大和オハナ保育園の初期行区分(§4.1: はな=後期/完了期/幼児食3分割・そら〜にじ各1行・事務室=職員)。
-- 朝おやつ=はな(0歳)/そら(1歳)/かぜ(2歳)が対象。つき(3歳)以上は昼食+午後おやつのみ。職員行は昼食のみ。
with dai as (
  select id as office_id from offices where name = '大和オハナ保育園'
),
cls as (
  select cc.class_name, cc.id from childcare_classes cc
  join dai on cc.office_id = dai.office_id where cc.is_active
)
insert into meal_row_definitions
  (office_id, row_key, row_label, class_id, meal_stage, row_type, am_snack, lunch, pm_snack, sort_order)
select dai.office_id, v.row_key, v.row_label, cls.id, v.meal_stage, v.row_type, v.am, v.lunch, v.pm, v.sort
from dai
cross join (values
  ('hana_late',     'はな組(後期)',  'はな組', 'late',     'children', true,  true, true, 10),
  ('hana_complete', 'はな組(完了期)', 'はな組', 'complete', 'children', true,  true, true, 20),
  ('hana_toddler',  'はな組(幼児食)', 'はな組', 'toddler',  'children', true,  true, true, 30),
  ('sora',          'そら組',        'そら組', null,       'children', true,  true, true, 40),
  ('kaze',          'かぜ組',        'かぜ組', null,       'children', true,  true, true, 50),
  ('tsuki',         'つき組',        'つき組', null,       'children', false, true, true, 60),
  ('hoshi',         'ほし組',        'ほし組', null,       'children', false, true, true, 70),
  ('niji',          'にじ組',        'にじ組', null,       'children', false, true, true, 80),
  ('office_staff',  '事務室(職員)',  null,     null,       'staff',    false, true, false, 90)
) as v(row_key, row_label, class_name, meal_stage, row_type, am, lunch, pm, sort)
left join cls on cls.class_name = v.class_name
where not exists (
  select 1 from meal_row_definitions m where m.office_id = dai.office_id and m.row_key = v.row_key
);
