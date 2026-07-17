-- 保護者アプリ Phase A: 保護者ドメイン専用RLSヘルパー関数 + 000075〜79のRLS一括適用
--
-- RLS3ドメイン分離の要件:
--   - 職員業務(給与・勤怠): is_labor_manager_plus()等。本ファイルは一切参照しない
--   - 保育業務・職員側(Phase0/1): manages_childcare()等。本ファイルは一切参照しない
--   - 保護者(新規): 本ファイルのis_guardian()/my_guardian_id()/guardian_has_child_access()等
-- 保護者ドメインの関数は職員系テーブルへの参照を一切行わない(children/guardian_*系のみ参照)。

create or replace function my_guardian_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from guardians where auth_user_id = auth.uid();
$$;

create or replace function is_guardian()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select my_guardian_id() is not null;
$$;

create or replace function guardian_has_child_access(target_child_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from guardian_child_links
    where guardian_id = my_guardian_id() and child_id = target_child_id
  );
$$;

create or replace function guardian_is_primary_for_child(target_child_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from guardian_child_links
    where guardian_id = my_guardian_id() and child_id = target_child_id and role = 'primary'
  );
$$;

-- 施設管理者(保育業務ドメイン)が、当該園児に紐づく保護者データへアクセスできるか。
-- has_childcare_office_access()/manages_childcare()(Phase0)をそのまま再利用する。
create or replace function staff_has_guardian_data_access(target_child_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from children c
    where c.id = target_child_id and has_childcare_office_access(c.office_id)
  );
$$;

create or replace function staff_manages_guardian_data(target_child_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from children c
    where c.id = target_child_id and manages_childcare(c.office_id)
  );
$$;

-- ============================================================
-- guardians: アカウント作成・停止等はRPC経由に限定(直接INSERT/UPDATEポリシーは設けない)
-- ============================================================
alter table guardians enable row level security;
create policy guardians_select_self_or_staff on guardians
  for select using (
    auth_user_id = auth.uid()
    or exists (
      select 1 from guardian_child_links gcl
      where gcl.guardian_id = guardians.id and staff_has_guardian_data_access(gcl.child_id)
    )
  );
create policy guardians_update_staff_only on guardians
  for update using (
    exists (
      select 1 from guardian_child_links gcl
      where gcl.guardian_id = guardians.id and staff_manages_guardian_data(gcl.child_id)
    )
  ) with check (
    exists (
      select 1 from guardian_child_links gcl
      where gcl.guardian_id = guardians.id and staff_manages_guardian_data(gcl.child_id)
    )
  );

-- ============================================================
-- guardian_child_links: 作成/変更はRPC経由(招待受諾等)。閲覧のみRLSで許可
-- ============================================================
alter table guardian_child_links enable row level security;
create policy guardian_child_links_select on guardian_child_links
  for select using (
    guardian_id = my_guardian_id() or staff_has_guardian_data_access(child_id)
  );

-- ============================================================
-- guardian_invitations: 招待元本人・当該施設職員のみ閲覧可。作成/受諾はRPC経由。
-- (招待コード入力時点では未ログインの可能性があるため、トークン照合はRPC内で
--  security definerとして行い、本ポリシーには依存しない)
-- ============================================================
alter table guardian_invitations enable row level security;
create policy guardian_invitations_select on guardian_invitations
  for select using (
    invited_by_guardian_id = my_guardian_id() or staff_has_guardian_data_access(child_id)
  );

-- ============================================================
-- guardian_permissions: 閲覧は当該園児に紐づく保護者・職員。変更は主たる保護者・管理者のみ
-- ============================================================
alter table guardian_permissions enable row level security;
create policy guardian_permissions_select on guardian_permissions
  for select using (
    guardian_has_child_access(child_id) or staff_has_guardian_data_access(child_id)
  );
create policy guardian_permissions_write on guardian_permissions
  for all using (
    guardian_is_primary_for_child(child_id) or staff_manages_guardian_data(child_id)
  ) with check (
    guardian_is_primary_for_child(child_id) or staff_manages_guardian_data(child_id)
  );

-- ============================================================
-- guardian_notification_settings: 本人のみ(施設職員も参照不要)
-- ============================================================
alter table guardian_notification_settings enable row level security;
create policy guardian_notification_settings_self on guardian_notification_settings
  for all using (guardian_id = my_guardian_id()) with check (guardian_id = my_guardian_id());

-- ============================================================
-- guardian_account_actions: 本人閲覧可(自分がなぜ停止されたか知る権利)。書込は職員のみ(RPC経由)
-- ============================================================
alter table guardian_account_actions enable row level security;
create policy guardian_account_actions_select on guardian_account_actions
  for select using (
    guardian_id = my_guardian_id()
    or exists (
      select 1 from guardian_child_links gcl
      where gcl.guardian_id = guardian_account_actions.guardian_id
        and staff_has_guardian_data_access(gcl.child_id)
    )
  );

-- ============================================================
-- guardian_emergency_contacts: 当該園児に紐づく保護者・職員が閲覧・編集可
-- (件数下限・重複例外承認等の業務ルールはRPC側でチェックする)
-- ============================================================
alter table guardian_emergency_contacts enable row level security;
create policy guardian_emergency_contacts_select on guardian_emergency_contacts
  for select using (
    guardian_has_child_access(child_id) or staff_has_guardian_data_access(child_id)
  );
create policy guardian_emergency_contacts_write on guardian_emergency_contacts
  for all using (
    guardian_has_child_access(child_id) or staff_manages_guardian_data(child_id)
  ) with check (
    guardian_has_child_access(child_id) or staff_manages_guardian_data(child_id)
  );

comment on function guardian_has_child_access(uuid) is
  '保護者ドメイン専用のアクセス判定。職員業務(is_labor_manager_plus等)・
   保育業務職員側(manages_childcare等)のいずれの関数も参照しない、独立した権限ドメイン。';
