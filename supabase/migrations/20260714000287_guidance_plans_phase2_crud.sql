-- 287: 指導計画 Phase 2-a = 計画インスタンス(guidance_plans)+個人案+作成/編集/テンプレ公開RPC。
-- 状態遷移(申請→確認→承認)・通知は 288。作成画面(UI)は後続。保護者非公開(RLS定義者のみ)。
-- 権限(v1): 作成・編集=施設の保育業務職員(has_childcare_office_access)、テンプレ公開=管理者以上。

-- ============================================================
-- (1) 計画インスタンス
-- ============================================================
create table guidance_plans (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id) on delete cascade,
  class_id uuid references childcare_classes(id),        -- overall/safety は null(施設単位)
  plan_type text not null check (plan_type in ('overall','annual','monthly','weekly','daily','safety')),
  age_variant text,
  template_id uuid not null references guidance_plan_templates(id),
  fiscal_year int not null,
  month int check (month between 1 and 12),              -- monthly
  week_start_date date,                                  -- weekly(月曜)
  content jsonb not null default '{}'::jsonb,            -- 欄ID→テキスト
  evaluation jsonb not null default '{}'::jsonb,         -- 評価・反省(承認後も担任が編集可)
  status text not null default 'draft' check (status in ('draft','submitted','chief_checked','approved')),
  submitted_at timestamptz, submitted_by uuid references employees(id),
  chief_checked_at timestamptz, chief_checked_by uuid references employees(id),
  approved_at timestamptz, approved_by uuid references employees(id),
  rejected_reason text,
  source_shared_plan_id uuid references guidance_plans(id),  -- 全体的な計画の共通版配布元(Phase3)
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- 同一(施設×クラス×種別×年度×月×週)で1件。
create unique index uq_guidance_plans on guidance_plans(
  office_id, coalesce(class_id, '00000000-0000-0000-0000-000000000000'::uuid),
  plan_type, fiscal_year, coalesce(month, 0), coalesce(week_start_date, 'epoch'::date));
create index idx_guidance_plans_office on guidance_plans(office_id, plan_type, fiscal_year);
create trigger trg_guidance_plans_updated_at before update on guidance_plans
  for each row execute function set_updated_at();
alter table guidance_plans enable row level security;
comment on table guidance_plans is '指導計画/保育安全計画の作成インスタンス(287)。保護者非公開。評価反省は承認後も編集可(evaluation列)。';

-- (2) 個人案(月案付随・園児別)
create table guidance_plan_individual_entries (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references guidance_plans(id) on delete cascade,
  child_id uuid not null references children(id) on delete cascade,
  content jsonb not null default '{}'::jsonb,   -- 子どもの姿/ねらい/配慮・環境構成/評価反省
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (plan_id, child_id)
);
create trigger trg_guidance_indiv_updated_at before update on guidance_plan_individual_entries
  for each row execute function set_updated_at();
alter table guidance_plan_individual_entries enable row level security;

-- ============================================================
-- (3) 年齢→テンプレ変種の解決 + 公開テンプレ取得
-- ============================================================
create or replace function guidance_age_variant(p_plan_type text, p_class_id uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare v_age int;
begin
  if p_plan_type in ('overall','safety','daily') then return null; end if;
  select substring(cc.age_group from '(\d)歳')::int into v_age from childcare_classes cc where cc.id = p_class_id;
  if v_age is null then return null; end if;
  if p_plan_type in ('monthly','weekly') then
    return case when v_age = 0 then 'age0' else 'age1plus' end;
  elsif p_plan_type = 'annual' then
    return case when v_age = 0 then 'age0' when v_age = 5 then 'age5' else 'age1to4' end;
  end if;
  return null;
end $$;

-- 公開中の最新テンプレ(種別×変種)。未公開しか無い場合は下書きの最新を返す(運用前でも作成テストできるように)。
create or replace function guidance_template_for(p_plan_type text, p_age_variant text)
returns guidance_plan_templates language sql stable security definer set search_path = public as $$
  select * from guidance_plan_templates
  where plan_type = p_plan_type and coalesce(age_variant,'') = coalesce(p_age_variant,'')
  order by is_published desc, version desc
  limit 1;
$$;

-- テンプレ公開(管理者以上)。seed済み下書きを公開する運用。
create or replace function publish_guidance_plan_template(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r guidance_plan_templates%rowtype;
begin
  if not is_childcare_admin_any() then raise exception 'not authorized'; end if;
  select * into r from guidance_plan_templates where id = p_id;
  if not found then raise exception 'not found'; end if;
  -- 同種別×変種の他版は非公開化(公開は常に最新1版)。
  update guidance_plan_templates set is_published = false
   where plan_type = r.plan_type and coalesce(age_variant,'') = coalesce(r.age_variant,'') and id <> p_id;
  update guidance_plan_templates set is_published = true where id = p_id;
end $$;
grant execute on function publish_guidance_plan_template(uuid) to authenticated, service_role;

-- ============================================================
-- (4) 作成・取得・保存
-- ============================================================
-- 作成(無ければ下書き行を作成し返す・冪等)。テンプレ版を固定。
create or replace function ensure_guidance_plan(
  p_office_id uuid, p_class_id uuid, p_plan_type text, p_fiscal_year int, p_month int, p_week_start date
)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_variant text; v_tmpl guidance_plan_templates; v_id uuid;
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  if not is_guidance_plans_enabled_for_office(p_office_id) then raise exception 'feature disabled'; end if;
  v_variant := guidance_age_variant(p_plan_type, p_class_id);
  v_tmpl := guidance_template_for(p_plan_type, v_variant);
  if v_tmpl.id is null then raise exception 'no template for % %', p_plan_type, v_variant; end if;

  select id into v_id from guidance_plans
   where office_id = p_office_id and coalesce(class_id,'00000000-0000-0000-0000-000000000000'::uuid)
       = coalesce(p_class_id,'00000000-0000-0000-0000-000000000000'::uuid)
     and plan_type = p_plan_type and fiscal_year = p_fiscal_year
     and coalesce(month,0) = coalesce(p_month,0)
     and coalesce(week_start_date,'epoch'::date) = coalesce(p_week_start,'epoch'::date);
  if v_id is null then
    insert into guidance_plans (office_id, class_id, plan_type, age_variant, template_id, fiscal_year, month, week_start_date, created_by)
    values (p_office_id, p_class_id, p_plan_type, v_variant, v_tmpl.id, p_fiscal_year, p_month, p_week_start, my_employee_id())
    returning id into v_id;
  end if;
  return v_id;
end $$;
grant execute on function ensure_guidance_plan(uuid, uuid, text, int, int, date) to authenticated, service_role;

-- 取得(本体+テンプレ定義+個人案)をjsonbで返す。
create or replace function fetch_guidance_plan(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_office uuid; v jsonb;
begin
  select office_id into v_office from guidance_plans where id = p_id;
  if v_office is null then raise exception 'not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  select jsonb_build_object(
    'plan', to_jsonb(gp.*),
    'template', to_jsonb(t.*),
    'individual', coalesce((select jsonb_agg(jsonb_build_object(
        'child_id', e.child_id, 'child_name', c.display_name, 'content', e.content) order by c.display_name)
      from guidance_plan_individual_entries e join children c on c.id = e.child_id where e.plan_id = gp.id), '[]'::jsonb)
  ) into v
  from guidance_plans gp join guidance_plan_templates t on t.id = gp.template_id
  where gp.id = p_id;
  return v;
end $$;
grant execute on function fetch_guidance_plan(uuid) to authenticated, service_role;

-- 本文の保存(自動保存)。承認済みは編集不可(評価反省は別RPC)。
create or replace function save_guidance_plan_content(p_id uuid, p_content jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_status text;
begin
  select office_id, status into v_office, v_status from guidance_plans where id = p_id;
  if v_office is null then raise exception 'not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  if v_status = 'approved' then raise exception 'approved plan is locked (use 承認取消)'; end if;
  update guidance_plans set content = p_content where id = p_id;
end $$;
grant execute on function save_guidance_plan_content(uuid, jsonb) to authenticated, service_role;

-- 評価・反省の保存(下書き/差し戻し中に加え、承認後も担任が記入可・AC-05)。
create or replace function save_guidance_plan_evaluation(p_id uuid, p_evaluation jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from guidance_plans where id = p_id;
  if v_office is null then raise exception 'not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  update guidance_plans set evaluation = p_evaluation where id = p_id;
end $$;
grant execute on function save_guidance_plan_evaluation(uuid, jsonb) to authenticated, service_role;

-- 個人案の保存(園児別・upsert)。承認済みは本文ロック(評価反省欄はcontent内で運用・v1は編集許可)。
create or replace function upsert_guidance_plan_individual(p_plan_id uuid, p_child_id uuid, p_content jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_status text;
begin
  select office_id, status into v_office, v_status from guidance_plans where id = p_plan_id;
  if v_office is null then raise exception 'not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  insert into guidance_plan_individual_entries (plan_id, child_id, content, created_by)
  values (p_plan_id, p_child_id, p_content, my_employee_id())
  on conflict (plan_id, child_id) do update set content = excluded.content, updated_at = now();
end $$;
grant execute on function upsert_guidance_plan_individual(uuid, uuid, jsonb) to authenticated, service_role;

-- 施設の計画一覧(年度・種別で絞り込み・作成状況把握用の簡易版)。
create or replace function fetch_guidance_plans_for_office(p_office_id uuid, p_fiscal_year int, p_plan_type text)
returns table (id uuid, class_id uuid, class_name text, plan_type text, age_variant text,
               month int, week_start_date date, status text, updated_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  return query
    select gp.id, gp.class_id, cc.class_name, gp.plan_type, gp.age_variant,
           gp.month, gp.week_start_date, gp.status, gp.updated_at
    from guidance_plans gp left join childcare_classes cc on cc.id = gp.class_id
    where gp.office_id = p_office_id and gp.fiscal_year = p_fiscal_year
      and (p_plan_type is null or gp.plan_type = p_plan_type)
    order by gp.plan_type, cc.class_name nulls first, gp.month nulls first, gp.week_start_date nulls first;
end $$;
grant execute on function fetch_guidance_plans_for_office(uuid, int, text) to authenticated, service_role;
