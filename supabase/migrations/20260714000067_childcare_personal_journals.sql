-- 保育業務 Phase1: 個人日誌の同時生成・追記
-- 連絡帳と同じ入力から職員向けの個人日誌を同時生成(保護者向けと文章を分ける)。
-- 保護者へは自動公開しない。承認要否・閲覧範囲は施設ごとの設定(childcare_office_settings)で変更可能。
--
-- visibility_scopeは二段構えで実装する:
--   Tier1(本ファイルのRLS): 同施設職員+管理者を上限とする固定の安全網。
--     設定に関わらずこれ以上広い公開は将来も許可しない。
--   Tier2(fetch_personal_journal RPC): childcare_office_settings.personal_journal_visibility_scope
--     に応じた実際の絞り込み(admin_only設定時は一般職員向け結果から除外)。
--   アプリ側の読み取りは本RPC経由を前提とする。直接SELECTした場合でもTier1が上限のため、
--   最悪でも同施設内に留まる。

create table child_personal_journals (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  business_date date not null,
  content_fact text,
  content_support text,
  content_reaction text,
  content_progress text,
  content_consideration text,
  content_handover text,
  ai_generated_text text,
  current_text text,
  status text not null default 'draft' check (status in ('draft', 'submitted', 'approved')),
  created_by uuid references employees(id),
  approved_by uuid references employees(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (child_id, business_date)
);
create trigger trg_child_personal_journals_updated_at before update on child_personal_journals
  for each row execute function set_updated_at();

-- AI生成後の自由追記(追記者・時刻を記録)
create table personal_journal_addenda (
  id uuid primary key default gen_random_uuid(),
  journal_id uuid not null references child_personal_journals(id) on delete cascade,
  author_employee_id uuid references employees(id),
  content text not null,
  created_at timestamptz not null default now()
);

alter table child_personal_journals enable row level security;
create policy child_personal_journals_select_office_ceiling on child_personal_journals
  for select using (
    exists (
      select 1 from children c
      where c.id = child_personal_journals.child_id and has_childcare_office_access(c.office_id)
    )
  );
create policy child_personal_journals_insert_scoped on child_personal_journals
  for insert with check (
    exists (
      select 1 from children c
      where c.id = child_personal_journals.child_id and has_childcare_office_access(c.office_id)
    )
  );
create policy child_personal_journals_update_scoped on child_personal_journals
  for update using (
    exists (
      select 1 from children c
      where c.id = child_personal_journals.child_id and has_childcare_office_access(c.office_id)
    )
  ) with check (
    exists (
      select 1 from children c
      where c.id = child_personal_journals.child_id and has_childcare_office_access(c.office_id)
    )
  );

alter table personal_journal_addenda enable row level security;
create policy personal_journal_addenda_select_scoped on personal_journal_addenda
  for select using (
    exists (
      select 1 from child_personal_journals j
      join children c on c.id = j.child_id
      where j.id = personal_journal_addenda.journal_id and has_childcare_office_access(c.office_id)
    )
  );
create policy personal_journal_addenda_insert_scoped on personal_journal_addenda
  for insert with check (
    exists (
      select 1 from child_personal_journals j
      join children c on c.id = j.child_id
      where j.id = personal_journal_addenda.journal_id and has_childcare_office_access(c.office_id)
    )
  );

do $$
declare
  t text;
  audited_tables text[] := array['child_personal_journals', 'personal_journal_addenda'];
begin
  foreach t in array audited_tables loop
    execute format(
      'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
      t
    );
  end loop;
end $$;

-- Tier2: 施設設定に応じた絞り込みを行った上で1件取得する。
create or replace function fetch_personal_journal(p_journal_id uuid)
returns child_personal_journals
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_journal child_personal_journals%rowtype;
  v_office_id uuid;
  v_scope text;
begin
  select * into v_journal from child_personal_journals where id = p_journal_id;
  if v_journal.id is null then
    raise exception 'journal not found';
  end if;

  select office_id into v_office_id from children where id = v_journal.child_id;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  select personal_journal_visibility_scope into v_scope
  from childcare_office_settings where office_id = v_office_id;

  if coalesce(v_scope, 'same_office_staff_and_admin') = 'admin_only' and not manages_childcare(v_office_id) then
    raise exception 'not authorized: personal journal is restricted to managers at this office';
  end if;

  return v_journal;
end;
$$;

-- 施設設定のpersonal_journal_requires_approvalに従い、承認不要ならそのまま確定、
-- 承認要ならsubmitted状態にして管理者の承認待ちにする。
create or replace function finalize_personal_journal(p_journal_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_journal child_personal_journals%rowtype;
  v_office_id uuid;
  v_requires_approval boolean;
begin
  select * into v_journal from child_personal_journals where id = p_journal_id for update;
  if v_journal.id is null then
    raise exception 'journal not found';
  end if;
  select office_id into v_office_id from children where id = v_journal.child_id;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  select personal_journal_requires_approval into v_requires_approval
  from childcare_office_settings where office_id = v_office_id;

  if coalesce(v_requires_approval, false) then
    update child_personal_journals set status = 'submitted' where id = p_journal_id;
  else
    update child_personal_journals set status = 'approved', approved_at = now() where id = p_journal_id;
  end if;
end;
$$;

create or replace function approve_personal_journal(p_journal_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_journal child_personal_journals%rowtype;
  v_office_id uuid;
begin
  select * into v_journal from child_personal_journals where id = p_journal_id for update;
  if v_journal.id is null then
    raise exception 'journal not found';
  end if;
  select office_id into v_office_id from children where id = v_journal.child_id;
  if not manages_childcare(v_office_id) then
    raise exception 'not authorized';
  end if;
  if v_journal.status <> 'submitted' then
    raise exception 'journal is % and cannot be approved', v_journal.status;
  end if;

  update child_personal_journals
  set status = 'approved', approved_by = my_employee_id(), approved_at = now()
  where id = p_journal_id;
end;
$$;
