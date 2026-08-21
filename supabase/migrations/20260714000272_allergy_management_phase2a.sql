-- 272: アレルギー管理 Phase2-a = 給食会議 + 保護者同意 + 同意文言テンプレ + 台帳の非提供食材アレルギー。
-- 給食管理設計書§7。除去食の「提供開始」に給食会議+保護者同意を課すための基盤。
-- ・提供開始ゲート(232 fetch_daily_elimination の改修)= 後続 273(Phase2-b)。
-- ・除去食の保護者限定公開(menu_days allergy_removed の RLS)= 後続 274(Phase2-c)。
-- 権限: 会議作成/テンプレ管理=主任以上(manages_childcare)、同意=保護者。フラグ=meal_management_enabled。

-- ============================================================
-- (1) 同意文言テンプレ(版管理・公開済みの最新版を同意時にスナップショット)
--     office_id=null は全社共通。施設別があればそちらを優先。
-- ============================================================
create table meal_consent_templates (
  id uuid primary key default gen_random_uuid(),
  office_id uuid references offices(id) on delete cascade,
  version int not null,
  body text not null,
  is_published boolean not null default false,
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- 施設スコープ(null=全社)ごとに version 一意。
create unique index idx_meal_consent_tmpl_ver
  on meal_consent_templates(coalesce(office_id, '00000000-0000-0000-0000-000000000000'::uuid), version);
create trigger trg_meal_consent_tmpl_updated_at before update on meal_consent_templates
  for each row execute function set_updated_at();
alter table meal_consent_templates enable row level security;
comment on table meal_consent_templates is 'アレルギー除去食の保護者同意文言テンプレ(272・§7)。管理者以上が版管理。公開済み最新版を同意時にスナップショット。';

-- ============================================================
-- (2) 給食会議(栄養士名=委託先テキスト・記録者=当社園長/管理者)
-- ============================================================
create table meal_conferences (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  office_id uuid not null references offices(id) on delete cascade,
  diagnosis_id uuid references child_allergy_diagnoses(id),  -- 対象診断書(除去指示の根拠)
  held_on date,                        -- 開催日
  nutritionist_name text,              -- 委託先栄養士名(テキスト)
  recorder_employee_id uuid references employees(id),  -- 記録者=当社職員
  elimination_plan text,               -- 除去・代替の提供方針
  status text not null default 'held' check (status in ('planned', 'held', 'consented', 'cancelled')),
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_meal_conferences_child on meal_conferences(child_id, created_at desc);
create index idx_meal_conferences_office on meal_conferences(office_id, status);
create trigger trg_meal_conferences_updated_at before update on meal_conferences
  for each row execute function set_updated_at();
alter table meal_conferences enable row level security;
comment on table meal_conferences is '給食会議(272・§7)。除去食提供の前提。保護者同意(meal_conference_consents)とセットで提供開始条件。';

-- ============================================================
-- (3) 保護者同意(不変=insertのみ・updated_atなし・削除しない)
--     該当外の保護者には一切表示しない(RPCで対象児の保護者のみ)。
-- ============================================================
create table meal_conference_consents (
  id uuid primary key default gen_random_uuid(),
  conference_id uuid not null references meal_conferences(id) on delete cascade,
  child_id uuid not null references children(id) on delete cascade,
  office_id uuid not null references offices(id) on delete cascade,
  guardian_id uuid references guardians(id),
  consent_template_id uuid references meal_consent_templates(id),
  consent_text_snapshot text not null,  -- 同意時点の文言を固定(後からテンプレ改版されても不変)
  agreed_guardian_name text not null,
  agreed_at timestamptz not null default now()
);
create index idx_meal_conf_consents_conf on meal_conference_consents(conference_id);
create index idx_meal_conf_consents_child on meal_conference_consents(child_id, agreed_at desc);
alter table meal_conference_consents enable row level security;
comment on table meal_conference_consents is 'アレルギー除去食の保護者同意(272・§7・不変記録)。日時・氏名・文言版を固定。対象児の保護者のみ閲覧。';

-- ============================================================
-- (4) 台帳: 園で提供しない食材のアレルギー(ナッツ等)。情報表示のみ・食数非連動。
-- ============================================================
create table child_allergen_alerts (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  office_id uuid not null references offices(id) on delete cascade,
  allergen text not null,
  severity text check (severity in ('mild', 'severe', 'anaphylaxis')),
  note text,
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_child_allergen_alerts_child on child_allergen_alerts(child_id);
create trigger trg_child_allergen_alerts_updated_at before update on child_allergen_alerts
  for each row execute function set_updated_at();
alter table child_allergen_alerts enable row level security;
comment on table child_allergen_alerts is '園で提供しない食材のアレルギー(272・§7.1)。緊急時把握のための台帳表示のみ。食数・除去食判定には連動しない。';

-- ============================================================
-- RPC: 同意文言テンプレ
-- ============================================================
-- 下書き保存=新バージョン(max+1)を作成。公開はしない。
create or replace function save_meal_consent_template(p_office_id uuid, p_body text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_ver int; v_id uuid;
begin
  if not is_childcare_admin(p_office_id) then raise exception 'not authorized'; end if;
  if coalesce(trim(p_body), '') = '' then raise exception 'body required'; end if;
  select coalesce(max(version), 0) + 1 into v_ver from meal_consent_templates
    where coalesce(office_id, '00000000-0000-0000-0000-000000000000'::uuid)
        = coalesce(p_office_id, '00000000-0000-0000-0000-000000000000'::uuid);
  insert into meal_consent_templates (office_id, version, body, created_by)
  values (p_office_id, v_ver, p_body, my_employee_id())
  returning id into v_id;
  return v_id;
end $$;
grant execute on function save_meal_consent_template(uuid, text) to authenticated, service_role;

-- 公開(同スコープの他版は非公開化=常に1版のみ公開)。
create or replace function publish_meal_consent_template(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from meal_consent_templates where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not is_childcare_admin(v_office) then raise exception 'not authorized'; end if;
  update meal_consent_templates set is_published = false
    where coalesce(office_id, '00000000-0000-0000-0000-000000000000'::uuid)
        = coalesce(v_office, '00000000-0000-0000-0000-000000000000'::uuid) and id <> p_id;
  update meal_consent_templates set is_published = true where id = p_id;
end $$;
grant execute on function publish_meal_consent_template(uuid) to authenticated, service_role;

create or replace function fetch_meal_consent_templates(p_office_id uuid)
returns table (id uuid, version int, body text, is_published boolean, created_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  if not is_childcare_admin(p_office_id) then raise exception 'not authorized'; end if;
  return query
    select t.id, t.version, t.body, t.is_published, t.created_at
    from meal_consent_templates t
    where t.office_id = p_office_id or t.office_id is null
    order by t.office_id nulls last, t.version desc;
end $$;
grant execute on function fetch_meal_consent_templates(uuid) to authenticated, service_role;

-- 有効な同意文言(施設別公開版を優先・なければ全社共通公開版)。内部用。
create or replace function active_meal_consent_template(p_office_id uuid)
returns meal_consent_templates language sql stable security definer set search_path = public as $$
  select * from meal_consent_templates
  where is_published and (office_id = p_office_id or office_id is null)
  order by office_id nulls last, version desc
  limit 1;
$$;

-- ============================================================
-- RPC: 給食会議
-- ============================================================
create or replace function create_meal_conference(
  p_child_id uuid, p_diagnosis_id uuid, p_held_on date, p_nutritionist_name text, p_elimination_plan text
)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_id uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  insert into meal_conferences (child_id, office_id, diagnosis_id, held_on, nutritionist_name,
                                recorder_employee_id, elimination_plan, created_by)
  values (p_child_id, v_office, p_diagnosis_id, p_held_on, p_nutritionist_name,
          my_employee_id(), p_elimination_plan, my_employee_id())
  returning id into v_id;
  return v_id;
end $$;
grant execute on function create_meal_conference(uuid, uuid, date, text, text) to authenticated, service_role;

create or replace function cancel_meal_conference(p_id uuid, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from meal_conferences where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  update meal_conferences set status = 'cancelled',
    elimination_plan = coalesce(elimination_plan, '') ||
      case when coalesce(trim(p_note), '') <> '' then E'\n[取消] ' || p_note else '' end
  where id = p_id;
end $$;
grant execute on function cancel_meal_conference(uuid, text) to authenticated, service_role;

-- 児ごとの会議一覧(同意状況付き)。全職員閲覧可。
create or replace function fetch_meal_conferences_for_child(p_child_id uuid)
returns table (id uuid, diagnosis_id uuid, held_on date, nutritionist_name text, recorder_name text,
               elimination_plan text, status text, created_at timestamptz,
               consent_at timestamptz, consent_guardian_name text)
language plpgsql security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  return query
    select mc.id, mc.diagnosis_id, mc.held_on, mc.nutritionist_name, e.display_name,
           mc.elimination_plan, mc.status, mc.created_at,
           cs.agreed_at, cs.agreed_guardian_name
    from meal_conferences mc
    left join employees e on e.id = mc.recorder_employee_id
    left join lateral (
      select agreed_at, agreed_guardian_name from meal_conference_consents
      where conference_id = mc.id order by agreed_at desc limit 1
    ) cs on true
    where mc.child_id = p_child_id
    order by mc.created_at desc;
end $$;
grant execute on function fetch_meal_conferences_for_child(uuid) to authenticated, service_role;

-- 施設の会議一覧(未同意=同意待ちのみ絞り込み可)。主任以上。
create or replace function fetch_meal_conferences_for_office(p_office_id uuid, p_only_unconsented boolean default false)
returns table (id uuid, child_id uuid, child_name text, held_on date, nutritionist_name text,
               status text, created_at timestamptz, consent_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  return query
    select mc.id, mc.child_id, c.display_name, mc.held_on, mc.nutritionist_name,
           mc.status, mc.created_at,
           (select max(agreed_at) from meal_conference_consents where conference_id = mc.id)
    from meal_conferences mc join children c on c.id = mc.child_id
    where mc.office_id = p_office_id and mc.status <> 'cancelled'
      and (not p_only_unconsented or mc.status = 'held')
    order by mc.created_at desc;
end $$;
grant execute on function fetch_meal_conferences_for_office(uuid, boolean) to authenticated, service_role;

-- ============================================================
-- RPC: 保護者同意(不変・対面で保護者アプリから押下)
-- ============================================================
-- 対象児の保護者が、公開中の同意文言に同意。文言をスナップショットし会議を consented に。
create or replace function submit_meal_conference_consent(p_conference_id uuid, p_agreed_guardian_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_child uuid; v_office uuid; v_tmpl meal_consent_templates; v_id uuid;
begin
  select child_id, office_id into v_child, v_office from meal_conferences where id = p_conference_id;
  if v_child is null then raise exception 'conference not found'; end if;
  if not guardian_has_child_access(v_child) then raise exception 'not authorized'; end if;
  if coalesce(trim(p_agreed_guardian_name), '') = '' then raise exception 'name required'; end if;
  v_tmpl := active_meal_consent_template(v_office);
  if v_tmpl.id is null then raise exception 'no consent template published'; end if;
  insert into meal_conference_consents (conference_id, child_id, office_id, guardian_id,
    consent_template_id, consent_text_snapshot, agreed_guardian_name)
  values (p_conference_id, v_child, v_office, my_guardian_id(), v_tmpl.id, v_tmpl.body, trim(p_agreed_guardian_name))
  returning id into v_id;
  update meal_conferences set status = 'consented' where id = p_conference_id and status = 'held';
  -- 主任以上へ通知(除去食提供開始の判断へ)
  insert into notifications (notification_type, title, body, channels, target_employee_id, payload, status)
  select 'meal_consent', '【給食】除去食の保護者同意',
    (select display_name from children where id = v_child) || 'さん: 給食会議の除去食提供に保護者同意が得られました。',
    array['push'], emp, jsonb_build_object('conference_id', p_conference_id::text, 'child_id', v_child::text), 'pending'
  from childcare_office_manager_employee_ids(v_office) emp;
  return v_id;
end $$;
grant execute on function submit_meal_conference_consent(uuid, text) to authenticated, service_role;

-- 保護者: 自分の子の同意待ち会議(status=held・未同意)+ 提示する同意文言。対象児の保護者のみ。
create or replace function fetch_pending_meal_consents_for_child(p_child_id uuid)
returns table (conference_id uuid, held_on date, nutritionist_name text, elimination_plan text,
               consent_template_id uuid, consent_body text)
language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_tmpl meal_consent_templates;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not guardian_has_child_access(p_child_id) then raise exception 'not authorized'; end if;
  v_tmpl := active_meal_consent_template(v_office);
  return query
    select mc.id, mc.held_on, mc.nutritionist_name, mc.elimination_plan,
           v_tmpl.id, v_tmpl.body
    from meal_conferences mc
    where mc.child_id = p_child_id and mc.status = 'held'
      and not exists (select 1 from meal_conference_consents cs where cs.conference_id = mc.id)
    order by mc.created_at desc;
end $$;
grant execute on function fetch_pending_meal_consents_for_child(uuid) to authenticated, service_role;

-- 職員向け: 児の「有効な除去食同意」の有無(提供開始ゲート 273 で使用する前段)。
create or replace function fetch_child_meal_consent_status(p_child_id uuid)
returns table (has_consent boolean, latest_consent_at timestamptz, latest_conference_status text)
language plpgsql security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  return query
    select exists(select 1 from meal_conference_consents where child_id = p_child_id),
           (select max(agreed_at) from meal_conference_consents where child_id = p_child_id),
           (select status from meal_conferences where child_id = p_child_id
              and status <> 'cancelled' order by created_at desc limit 1);
end $$;
grant execute on function fetch_child_meal_consent_status(uuid) to authenticated, service_role;

-- ============================================================
-- RPC: 台帳の非提供食材アレルギー
-- ============================================================
create or replace function set_child_allergen_alert(p_child_id uuid, p_allergen text, p_severity text, p_note text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_id uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  if coalesce(trim(p_allergen), '') = '' then raise exception 'allergen required'; end if;
  insert into child_allergen_alerts (child_id, office_id, allergen, severity, note, created_by)
  values (p_child_id, v_office, trim(p_allergen), nullif(p_severity, ''), p_note, my_employee_id())
  returning id into v_id;
  return v_id;
end $$;
grant execute on function set_child_allergen_alert(uuid, text, text, text) to authenticated, service_role;

create or replace function delete_child_allergen_alert(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from child_allergen_alerts where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  delete from child_allergen_alerts where id = p_id;
end $$;
grant execute on function delete_child_allergen_alert(uuid) to authenticated, service_role;

create or replace function fetch_child_allergen_alerts(p_child_id uuid)
returns table (id uuid, allergen text, severity text, note text, created_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  return query
    select a.id, a.allergen, a.severity, a.note, a.created_at
    from child_allergen_alerts a where a.child_id = p_child_id
    order by a.created_at;
end $$;
grant execute on function fetch_child_allergen_alerts(uuid) to authenticated, service_role;
