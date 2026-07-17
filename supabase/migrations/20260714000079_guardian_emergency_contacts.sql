-- 保護者アプリ Phase A: 緊急連絡先(変更9で確定した仕様)
--
-- 「園児ごと最低2件必須」はDB制約ではなくRPC側でチェックする(最終確定・申請確定等の
-- タイミングで件数を確認する運用。登録途中は1件でも保存できる必要があるため)。
--
-- 重複チェックは同一園児内の同一電話番号のみを対象とし、きょうだい間(family_group_idが
-- 同じ園児同士)の同一連絡先は正常な運用として許可する(警告しない)。
-- 同一園児内の重複は職員が例外承認できる(duplicate_approved_by/reason)。

create table guardian_emergency_contacts (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  name text not null,
  phone text not null,
  relationship text,
  sort_order int not null default 0,
  duplicate_approved_by uuid references employees(id),
  duplicate_approved_reason text,
  created_by_guardian_id uuid references guardians(id),
  created_by_employee_id uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_guardian_emergency_contacts_updated_at before update on guardian_emergency_contacts
  for each row execute function set_updated_at();
create index idx_guardian_emergency_contacts_child on guardian_emergency_contacts(child_id);

do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'guardian_emergency_contacts'
  );
end $$;
