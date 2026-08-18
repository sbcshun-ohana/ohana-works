-- 238: 発達記録 Phase 1後半 = マスター管理(RLS + 項目編集RPC)。
-- 全社共通マスター(office_idなし)。閲覧=全職員(保護者は到達不可=my_employee_id基準)、
-- 編集=管理者以上(園長以上)。直接書込はRLSで拒否し、編集は版スナップショットを自動記録するRPC経由のみ。
-- 正本=docs/Ohana_Works_設計指示書_発達記録_Opus実装用_v1_0_2026-08-18.md。

-- 管理者以上(いずれかの施設で保持。全社共通マスター編集用の無引数版。
-- 既存 is_childcare_admin(office) は施設スコープのため、office非依存の全社マスターにはこちらを使う)
create or replace function is_childcare_admin_any()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from employee_roles er
    join roles r on r.id = er.role_id
    where er.employee_id = my_employee_id()
      and r.code in ('system_admin', 'executive_director', 'director', 'office_manager')
  );
$$;
grant execute on function is_childcare_admin_any() to authenticated, service_role;
comment on function is_childcare_admin_any() is
  '管理者以上(system_admin/executive_director/director/office_manager)をいずれかの施設で保持するか。全社共通マスターの編集判定用(238)。';

-- RLS: 閲覧=全職員(保護者は my_employee_id が null のため到達不可)
create policy dev_item_masters_select on development_item_masters
  for select using (my_employee_id() is not null);
create policy dev_master_versions_select on development_master_versions
  for select using (my_employee_id() is not null);
-- 版履歴は管理者以上のみ
create policy dev_item_master_versions_select on development_item_master_versions
  for select using (is_childcare_admin_any());
-- ※書込ポリシーは付与しない(RLS有効=直接INSERT/UPDATE/DELETEは全拒否)。編集は下記RPC経由のみ。

-- 項目編集(内容変更+版スナップショット)。管理者以上のみ。
-- age_band_code は項目の帰属を定義するため編集不可(パラメータに含めない)。
create or replace function update_development_item_master(
  p_item_id uuid,
  p_item_name text,
  p_observation_point text,
  p_domain_code text,
  p_display_order int,
  p_is_active boolean
) returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_new_version int;
begin
  if not is_childcare_admin_any() then
    raise exception 'not authorized';
  end if;
  if p_domain_code is not null
     and p_domain_code not in ('health','relations','environment','language','expression') then
    raise exception 'invalid domain_code: %', p_domain_code;
  end if;

  update development_item_masters m
    set item_name        = coalesce(p_item_name, m.item_name),
        observation_point = p_observation_point,  -- nullで明示的クリア可
        domain_code      = coalesce(p_domain_code, m.domain_code),
        display_order    = coalesce(p_display_order, m.display_order),
        is_active        = coalesce(p_is_active, m.is_active),
        current_version  = m.current_version + 1
    where m.id = p_item_id
    returning m.current_version into v_new_version;

  if v_new_version is null then
    raise exception 'item not found: %', p_item_id;
  end if;

  insert into development_item_master_versions
    (item_id, version, age_band_code, domain_code, item_name, observation_point, display_order, is_active, changed_by)
  select m.id, m.current_version, m.age_band_code, m.domain_code, m.item_name,
         m.observation_point, m.display_order, m.is_active, my_employee_id()
  from development_item_masters m where m.id = p_item_id;
end;
$$;
grant execute on function update_development_item_master(uuid, text, text, text, int, boolean)
  to authenticated, service_role;
comment on function update_development_item_master(uuid, text, text, text, int, boolean) is
  '発達項目マスターの内容編集(管理者以上・238)。current_versionを+1し、変更後の内容を版テーブルへスナップショット。';
