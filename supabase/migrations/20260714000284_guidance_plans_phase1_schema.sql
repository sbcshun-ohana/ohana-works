-- 284: 指導計画・保育安全計画 Phase 1 = 基盤スキーマ(テンプレ版管理・承認フロー定義・前提列・フラグ)。
-- 設計指示書 指導計画_本案_v1_0_2026-08-19。テンプレの初期seed=285、計画CRUD(guidance_plans等)=Phase2(286+)。
-- 保育安全計画は plan_type='safety' として同枠組みに載せる(俊追加要望・こども家庭庁正式様式)。
-- 保護者からは一切見えない(RLSは有効化しポリシー無し=定義者RPC経由のみ)。フラグ既定OFF・施設別ON。

-- (1) 機能フラグ
insert into feature_flags (feature_key, name, description, default_enabled) values
  ('guidance_plans_enabled', '指導計画・保育安全計画',
   '指導計画(全体的な計画/年間/月案+個人案/週案/日案)+保育安全計画の施設別有効化。既定OFF。', false)
on conflict (feature_key) do nothing;

create or replace function is_guidance_plans_enabled_for_office(p_office_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select is_feature_enabled_for_office('guidance_plans_enabled', p_office_id);
$$;
grant execute on function is_guidance_plans_enabled_for_office(uuid) to authenticated, service_role;

-- (2) 施設区分(認可/企業主導型)。週案の出し分け等に使用。将来のBABY MAHALO(M)の大和統合を意識。
alter table offices add column if not exists office_category text
  check (office_category in ('authorized', 'corporate_led'));
update offices set office_category = 'authorized'   where office_code = 'O'  and office_category is null;
update offices set office_category = 'corporate_led' where office_code in ('M','S','H') and office_category is null;
comment on column offices.office_category is '施設区分。authorized=認可(大和)/corporate_led=企業主導型(MAHALO/Station/Halelea)。週案対象・承認フロー段数の判定に使用(指導計画284)';

-- (3) 加配フラグ(個人案の対象判定)。支援保育(140)とは別の独立フラグ(俊確定2026-08-24)。
alter table children add column if not exists individual_plan_target boolean not null default false;
comment on column children.individual_plan_target is '個人案対象(加配)。0-2歳クラスは既定対象、それ以外のクラスは本フラグで個別に対象化(指導計画§2-6・支援保育とは別管理)';

-- (4) テンプレート版管理(種別×年齢区分×版・宣言的な欄定義)。指針改訂で新版公開・過去計画は当時版で再現。
create table guidance_plan_templates (
  id uuid primary key default gen_random_uuid(),
  plan_type text not null check (plan_type in ('overall','annual','monthly','weekly','daily','safety')),
  age_variant text,                       -- 例 age0 / age1plus / age1to4 / age5 / null(区分なし)
  version int not null,
  title text not null,
  sections jsonb not null default '[]'::jsonb,  -- [{key,label,fields:[{key,label,required,subject,input,note}...]}...]
  is_published boolean not null default false,
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index uq_guidance_tmpl on guidance_plan_templates(plan_type, coalesce(age_variant, ''), version);
create trigger trg_guidance_tmpl_updated_at before update on guidance_plan_templates
  for each row execute function set_updated_at();
alter table guidance_plan_templates enable row level security;
comment on table guidance_plan_templates is '指導計画/保育安全計画のテンプレ(版管理・宣言的欄定義)。管理者以上が版管理。seed=285。';

-- (5) 承認フロー定義(施設区分×計画種別→段)。大和=2段(主任確認→園長)、企業3施設=1段(管理者)。
create table guidance_approval_flows (
  id uuid primary key default gen_random_uuid(),
  office_category text not null check (office_category in ('authorized', 'corporate_led')),
  plan_type text,                         -- null=全種別共通
  steps jsonb not null,                   -- [{"step":1,"role":"chief","action":"confirm"}, ...]
  created_at timestamptz not null default now()
);
create unique index uq_guidance_flow on guidance_approval_flows(office_category, coalesce(plan_type, ''));
alter table guidance_approval_flows enable row level security;
comment on table guidance_approval_flows is '指導計画の承認フロー定義。authorized=担当→主任確認→園長承認(2段)/corporate_led=担当→管理者承認(1段)。';

insert into guidance_approval_flows (office_category, plan_type, steps) values
  ('authorized',   null, '[{"step":1,"role":"chief","action":"confirm"},{"step":2,"role":"director","action":"approve"}]'::jsonb),
  ('corporate_led', null, '[{"step":1,"role":"admin","action":"approve"}]'::jsonb)
on conflict do nothing;

-- (6) 参照RPC(管理者以上)。テンプレ一覧・承認フロー取得。write/公開RPCは285(seed)で追加。
create or replace function fetch_guidance_plan_templates()
returns setof guidance_plan_templates language plpgsql stable security definer set search_path = public as $$
begin
  if not is_childcare_admin_any() then raise exception 'not authorized'; end if;
  return query select * from guidance_plan_templates
    order by plan_type, age_variant nulls first, version desc;
end $$;
grant execute on function fetch_guidance_plan_templates() to authenticated, service_role;

create or replace function fetch_guidance_approval_flow(p_office_category text, p_plan_type text)
returns jsonb language sql stable security definer set search_path = public as $$
  select steps from guidance_approval_flows
  where office_category = p_office_category and (plan_type = p_plan_type or plan_type is null)
  order by plan_type nulls last limit 1;
$$;
grant execute on function fetch_guidance_approval_flow(text, text) to authenticated, service_role;
