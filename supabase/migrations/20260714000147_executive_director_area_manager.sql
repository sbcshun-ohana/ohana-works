-- 統括園長(executive_director)・統括管理者(area_manager)の追加と多施設権限付与機構。
-- 設計: docs/権限・セッション管理_設計案_2026-07-30.md §1 / docs/統括管理者_調査報告_2026-07-30.md §7。
--
-- 方針(要点):
--  - 役職を2つ追加。executive_director=全施設で園長＋管理者を包含(職員業務系
--    is_labor_manager_plus/is_system_admin は拡張しない)。area_manager=付与テーブルで
--    対象施設を明示指定し「管理者(office_manager)相当」。
--  - 施設スコープ判定4関数(manages_office/manages_childcare/is_support_childcare_chief/
--    has_goal_sheet_edit_access)に「executive_director を全施設許可」＋「付与テーブルのOR句」を追加。
--    childcare_office_manager_employee_ids(通知宛先専用)は意図的に対象外(§3-5 の注記参照)。
--  - 支援保育・目標シートの最終承認関数(承認者テーブル駆動)に executive_director を追加し、
--    大和オハナの director 空席でも統括園長が全施設で承認者として通るようにする。
--  - 付与・剥奪は is_system_admin() のみ。監査は log_event_change トリガ(event_logs)。
--  - 大原利奈の director→executive_director 切替は本番固有データのため本マイグレーションに
--    直書きしない(本番リリース手順書の手動SQLで実施)。ステージングは seed_staging.ts で
--    テスト用アカウントに付与する。
--
-- 【レビュー反映 2026-07-31】
--  1) 付与できる権限は「管理者(office_manager)相当」のみ。**園長(director)相当の付与は提供しない**。
--     設計上、統括園長は executive_director という“役職”で全施設園長を表現しており、付与テーブルで
--     他施設の園長権限を配る用途は無い。誤って他施設の園長権限を配る事故を構造的に防ぐため、
--     granted_level カラム自体を設けない(全付与=office_manager 相当固定)。将来もし「特定施設だけ
--     園長権限を付与」する需要が生じたら、その時に別途レビューを経てスキーマ拡張する。
--  2) (grantee_employee_id, office_id) where revoked_at is null の部分ユニークインデックスで
--     有効付与の重複を防止。grant RPC は既存の有効付与があれば**その行を返す(冪等)**。
--  3) roles.sort_order は表示順専用(権限判定・比較演算には未使用=リポジトリ全体を grep で確認済み)。
--     10刻みへ振り直し、executive_director を director の上、area_manager を chief の上へ配置する。
--
-- volatility 自己チェック(§3.2b): 本マイグレーションで追加/差替する関数はいずれも
--  log_sensitive_access() を呼ばない。書き込みを行う grant/revoke は volatile(既定)、
--  判定・取得系は stable。stable が問題化するのは log_sensitive_access を呼ぶ関数のみで、
--  該当なし(適用後に pg_proc で機械確認して報告する)。

-- ============================================================
-- 1) 役職マスタ: 既存の sort_order を10刻みへ振り直し、2役職を適切な位置に追加
--    (sort_order は表示順専用。権限判定・比較には未使用。)
--    表示順(上位→下位): system_admin > labor_manager > 統括園長 > director >
--                        統括管理者 > chief > office_manager > viewer > staff
-- ============================================================
update roles set sort_order = 10 where code = 'system_admin';
update roles set sort_order = 20 where code = 'labor_manager';
update roles set sort_order = 40 where code = 'director';
update roles set sort_order = 60 where code = 'chief';
update roles set sort_order = 70 where code = 'office_manager';
update roles set sort_order = 80 where code = 'viewer';
update roles set sort_order = 90 where code = 'staff';

insert into roles (code, name, sort_order) values
  ('executive_director', '統括園長', 30),  -- director(40) の上
  ('area_manager', '統括管理者', 50)        -- chief(60) の上
on conflict (code) do nothing;

-- ============================================================
-- 2) 多施設権限付与テーブル(全付与=管理者相当。granted_level カラムは設けない)
-- ============================================================
create table multi_office_authority_grants (
  id uuid primary key default gen_random_uuid(),
  grantee_employee_id uuid not null references employees(id) on delete cascade,
  office_id uuid not null references offices(id),
  granted_by uuid not null references employees(id),
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_by uuid references employees(id),
  note text
);
-- 有効付与(未失効)の重複を防止。失効済みは履歴として複数残せる。
create unique index uq_moag_active
  on multi_office_authority_grants (grantee_employee_id, office_id)
  where revoked_at is null;
create index idx_moag_grantee on multi_office_authority_grants (grantee_employee_id) where revoked_at is null;
create index idx_moag_office on multi_office_authority_grants (office_id) where revoked_at is null;

-- RLS: 直接の書き込みは塞ぎ(付与/剥奪はSECURITY DEFINER RPC経由)、閲覧は system_admin と当人のみ。
alter table multi_office_authority_grants enable row level security;
create policy moag_select on multi_office_authority_grants
  for select using (is_system_admin() or grantee_employee_id = my_employee_id());

create trigger trg_audit_multi_office_authority_grants
  after insert or update or delete on multi_office_authority_grants
  for each row execute function log_event_change();

-- ============================================================
-- 3) 施設スコープ判定4関数の差替(executive_director 全施設 + 付与テーブルOR句)
--    既存の判定は完全に維持し、2条件を足すのみ。付与=管理者相当のみ。
--    ※ childcare_office_manager_employee_ids(通知宛先専用)は §3-5 の注記のとおり変更しない。
-- ============================================================

create or replace function manages_office(target_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select is_labor_manager_plus()
    or exists (
      select 1 from employee_roles er
      join roles r on r.id = er.role_id
      where er.employee_id = my_employee_id()
        and (
          r.code = 'executive_director'  -- 統括園長: 全施設
          or (
            r.code in ('director', 'chief', 'office_manager', 'system_admin', 'labor_manager')
            and (er.office_id is null or er.office_id = target_office_id)
          )
        )
    )
    or exists (
      select 1 from multi_office_authority_grants g
      where g.grantee_employee_id = my_employee_id()
        and g.office_id = target_office_id
        and g.revoked_at is null
    );
$$;

create or replace function manages_childcare(target_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
      select 1 from employee_roles er
      join roles r on r.id = er.role_id
      where er.employee_id = my_employee_id()
        and (
          r.code = 'system_admin'
          or r.code = 'executive_director'  -- 統括園長: 全施設
          or (
            r.code in ('director', 'chief', 'office_manager')
            and (er.office_id is null or er.office_id = target_office_id)
          )
        )
    )
    or exists (
      select 1 from multi_office_authority_grants g
      where g.grantee_employee_id = my_employee_id()
        and g.office_id = target_office_id
        and g.revoked_at is null
    );
$$;

create or replace function is_support_childcare_chief(target_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
      select 1 from employee_roles er
      join roles r on r.id = er.role_id
      where er.employee_id = my_employee_id()
        and (
          r.code = 'executive_director'  -- 統括園長: 全施設
          or (
            r.code in ('chief', 'office_manager', 'director', 'system_admin')
            and (er.office_id is null or er.office_id = target_office_id)
          )
        )
    )
    or exists (
      select 1 from multi_office_authority_grants g
      where g.grantee_employee_id = my_employee_id()
        and g.office_id = target_office_id
        and g.revoked_at is null
    );
$$;

create or replace function has_goal_sheet_edit_access(target_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
      select 1 from employee_roles er
      join roles r on r.id = er.role_id
      where er.employee_id = my_employee_id()
        and (
          r.code = 'executive_director'  -- 統括園長: 全施設
          or (
            r.code in ('chief', 'office_manager', 'director', 'system_admin')
            and (er.office_id is null or er.office_id = target_office_id)
          )
        )
    )
    or exists (
      select 1 from multi_office_authority_grants g
      where g.grantee_employee_id = my_employee_id()
        and g.office_id = target_office_id
        and g.revoked_at is null
    );
$$;

-- childcare_office_manager_employee_ids は**意図的に変更しない**(migration 62 のまま)。
-- この関数は「通知の宛先解決」専用(連絡帳申請通知・クラス活動申請通知の2箇所のみが呼ぶ)で、
-- 承認可否や画面表示には使われない。ここに executive_director や付与保持者を足すと、
-- 統括園長が全4施設の申請通知を毎回受信し、統括管理者も付与施設の申請通知を受信して
-- ノイズになる。統括園長/統括管理者の**承認権限は §3・§4 の判定関数で担保済み**のため、
-- 通知宛先(施設ローカルの管理者)に含める必要はない。よって本関数は現状維持とする。
-- (注: 既存挙動で system_admin は全施設の申請通知を受信する。これは本マイグレーション以前からの
--  仕様であり変更しない。system_admin も通知対象から外したい場合は別途判断・別マイグレーションとする。)

-- ============================================================
-- 4) 最終承認関数(承認者テーブル駆動)へ executive_director を追加。
--    大和の director 空席でも統括園長が全施設の最終承認者として通る(§7.4)。
--    area_manager(付与)はここには含めない=最終承認は指定承認者/統括園長/system_admin のみ。
-- ============================================================

create or replace function is_support_childcare_office_approver(target_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
      select 1 from support_childcare_office_approvers a
      where a.office_id = target_office_id and a.approver_employee_id = my_employee_id()
    )
    or exists (
      select 1 from employee_roles er
      join roles r on r.id = er.role_id
      where er.employee_id = my_employee_id()
        and r.code in ('system_admin', 'executive_director')  -- 統括園長: 全施設の承認者
    );
$$;

create or replace function is_goal_sheet_office_approver(target_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
      select 1 from employee_goal_sheet_office_approvers a
      where a.office_id = target_office_id and a.approver_employee_id = my_employee_id()
    )
    or exists (
      select 1 from employee_roles er
      join roles r on r.id = er.role_id
      where er.employee_id = my_employee_id()
        and r.code in ('system_admin', 'executive_director')  -- 統括園長: 全施設の承認者
    );
$$;

-- ============================================================
-- 5) 付与・剥奪・取得RPC(付与/剥奪は is_system_admin() のみ)
--    grant は冪等: 既存の有効付与があればその行を返し、二重付与しない。
-- ============================================================
create or replace function grant_multi_office_authority(
  p_grantee_employee_id uuid, p_office_id uuid
)
returns multi_office_authority_grants
language plpgsql security definer set search_path = public
as $$
declare
  v_row multi_office_authority_grants;
begin
  if not is_system_admin() then
    raise exception 'not authorized to grant multi-office authority';
  end if;

  -- 既存の有効付与があれば冪等に返す(UNIQUE index が最終防波堤)
  select * into v_row from multi_office_authority_grants
  where grantee_employee_id = p_grantee_employee_id
    and office_id = p_office_id
    and revoked_at is null;
  if found then
    return v_row;
  end if;

  insert into multi_office_authority_grants (grantee_employee_id, office_id, granted_by)
  values (p_grantee_employee_id, p_office_id, my_employee_id())
  returning * into v_row;

  return v_row;
end;
$$;

create or replace function revoke_multi_office_authority(p_grant_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not is_system_admin() then
    raise exception 'not authorized to revoke multi-office authority';
  end if;

  update multi_office_authority_grants
  set revoked_at = now(), revoked_by = my_employee_id()
  where id = p_grant_id and revoked_at is null;
end;
$$;

-- admin_web の付与管理画面用: 有効な付与一覧。
-- system_admin は全件、それ以外は自分が付与された分のみ(付与された本人が自分の状況を確認できる)。
create or replace function fetch_multi_office_authority_grants()
returns setof multi_office_authority_grants
language sql stable security definer set search_path = public
as $$
  select g.*
  from multi_office_authority_grants g
  where (is_system_admin() or g.grantee_employee_id = my_employee_id())
    and g.revoked_at is null
  order by g.granted_at desc;
$$;
