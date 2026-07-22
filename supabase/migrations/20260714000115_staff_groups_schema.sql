-- 開発計画(改訂版 2026-07-17) Phase 1 / E: お知らせ・個別連絡・グループ連絡。
-- 「グループ連絡」用のグループ定義・メンバー管理テーブルを新設し、notices.category に
-- 'グループ' を追加する。グループ宛お知らせは送信時点のメンバーを notice_recipients に
-- スナップショット展開する方式とするため(create_notice RPCで実装)、notices/notice_recipients
-- 側のRLSは変更しない。

alter type notice_category add value 'グループ';

create type staff_group_type as enum ('class_team', 'project_team', 'custom');

-- グループ本体。class_team は related_class_id で保育業務側のクラスを参照するが、
-- あくまで名称・種別の参考情報であり、メンバーの絞り込みは staff_group_members が唯一の正とする
-- (employee_class_access は保育業務のアクセス制限用の別概念であり、職員名簿としては使わない)。
create table staff_groups (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id),
  group_type staff_group_type not null,
  name text not null,
  related_class_id uuid references childcare_classes(id),
  is_active boolean not null default true,
  created_by uuid not null references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz
);
create trigger trg_staff_groups_updated_at before update on staff_groups
  for each row execute function set_updated_at();
create index idx_staff_groups_office on staff_groups(office_id);

-- メンバーは論理削除(removed_at)で履歴を残す。一度外れて再度加入した場合は
-- 同一行の removed_at を null に戻す(unique制約により行の重複作成を防ぐ)。
create table staff_group_members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references staff_groups(id) on delete cascade,
  employee_id uuid not null references employees(id),
  added_at timestamptz not null default now(),
  removed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (group_id, employee_id)
);
create index idx_staff_group_members_employee on staff_group_members(employee_id);

alter table notices add column target_group_id uuid references staff_groups(id);
create index idx_notices_target_group on notices(target_group_id);

comment on column notices.target_group_id is
  'グループ連絡時の対象グループ。実際の宛先は送信時点のstaff_group_membersをnotice_recipientsへ
   スナップショット展開したもの(create_notice RPC参照)であり、本列はあくまで参照・監査用。';
