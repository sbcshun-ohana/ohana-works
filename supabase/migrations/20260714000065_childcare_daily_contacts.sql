-- 保育業務 Phase1: 園児個別メモ・連絡帳本体・職員編集/承認・コピー
-- §10(個別メモ・個別お知らせチェック)・§11(AI生成本文の保存)・
-- §12(職員編集/申請→管理者承認・差し戻し)・§13(承認済み文章のコピー)に対応する。

create table child_daily_contacts (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  business_date date not null,
  assignee_employee_id uuid references employees(id),
  guardian_message text,
  child_today_notes text,
  free_notes text,
  ai_generated_text text,
  current_text text,
  status text not null default 'draft' check (status in ('draft', 'submitted', 'approved', 'rejected')),
  submitted_at timestamptz,
  approved_by uuid references employees(id),
  approved_at timestamptz,
  rejected_reason text,
  admin_comment text,
  copied_by uuid references employees(id),
  copied_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (child_id, business_date)
);
create trigger trg_child_daily_contacts_updated_at before update on child_daily_contacts
  for each row execute function set_updated_at();
create index idx_child_daily_contacts_business_date on child_daily_contacts(business_date);

-- 個別お知らせの複数チェック
create table child_daily_contact_notice_checks (
  contact_id uuid not null references child_daily_contacts(id) on delete cascade,
  notice_master_id uuid not null references individual_notice_masters(id),
  checked_by uuid references employees(id),
  checked_at timestamptz not null default now(),
  primary key (contact_id, notice_master_id)
);

-- 備品利用の記録欄(請求への自動連携は今回実装しない)
create table child_daily_contact_supply_items (
  id uuid primary key default gen_random_uuid(),
  contact_id uuid not null references child_daily_contacts(id) on delete cascade,
  item_name text not null,
  quantity int not null default 1,
  recorded_by uuid references employees(id),
  created_at timestamptz not null default now()
);

-- 担当者不在時等に他職員が追加する補足メモ(担当者の入力を上書きしないため別レコードとして追加。
-- 追記専用でUPDATE/DELETEポリシーは設けない)
create table child_daily_contact_supplements (
  id uuid primary key default gen_random_uuid(),
  contact_id uuid not null references child_daily_contacts(id) on delete cascade,
  author_employee_id uuid references employees(id),
  content text not null,
  created_at timestamptz not null default now()
);

alter table child_daily_contacts enable row level security;
create policy child_daily_contacts_select_scoped on child_daily_contacts
  for select using (
    exists (
      select 1 from children c
      where c.id = child_daily_contacts.child_id and has_childcare_office_access(c.office_id)
    )
  );
create policy child_daily_contacts_insert_scoped on child_daily_contacts
  for insert with check (
    exists (
      select 1 from children c
      where c.id = child_daily_contacts.child_id and has_childcare_office_access(c.office_id)
    )
  );
-- 担当者本人は下書き・差し戻し中のみ編集可(状態遷移は下記RPC経由に限定)。
create policy child_daily_contacts_update_assignee_content on child_daily_contacts
  for update using (
    assignee_employee_id = my_employee_id() and status in ('draft', 'rejected')
  ) with check (
    assignee_employee_id = my_employee_id() and status in ('draft', 'rejected')
  );
create policy child_daily_contacts_update_managers on child_daily_contacts
  for update using (
    exists (
      select 1 from children c
      where c.id = child_daily_contacts.child_id and manages_childcare(c.office_id)
    )
  ) with check (
    exists (
      select 1 from children c
      where c.id = child_daily_contacts.child_id and manages_childcare(c.office_id)
    )
  );

alter table child_daily_contact_notice_checks enable row level security;
create policy child_daily_contact_notice_checks_select_scoped on child_daily_contact_notice_checks
  for select using (
    exists (
      select 1 from child_daily_contacts cdc join children c on c.id = cdc.child_id
      where cdc.id = child_daily_contact_notice_checks.contact_id and has_childcare_office_access(c.office_id)
    )
  );
create policy child_daily_contact_notice_checks_write_scoped on child_daily_contact_notice_checks
  for all using (
    exists (
      select 1 from child_daily_contacts cdc join children c on c.id = cdc.child_id
      where cdc.id = child_daily_contact_notice_checks.contact_id and has_childcare_office_access(c.office_id)
    )
  ) with check (
    exists (
      select 1 from child_daily_contacts cdc join children c on c.id = cdc.child_id
      where cdc.id = child_daily_contact_notice_checks.contact_id and has_childcare_office_access(c.office_id)
    )
  );

alter table child_daily_contact_supply_items enable row level security;
create policy child_daily_contact_supply_items_select_scoped on child_daily_contact_supply_items
  for select using (
    exists (
      select 1 from child_daily_contacts cdc join children c on c.id = cdc.child_id
      where cdc.id = child_daily_contact_supply_items.contact_id and has_childcare_office_access(c.office_id)
    )
  );
create policy child_daily_contact_supply_items_write_scoped on child_daily_contact_supply_items
  for all using (
    exists (
      select 1 from child_daily_contacts cdc join children c on c.id = cdc.child_id
      where cdc.id = child_daily_contact_supply_items.contact_id and has_childcare_office_access(c.office_id)
    )
  ) with check (
    exists (
      select 1 from child_daily_contacts cdc join children c on c.id = cdc.child_id
      where cdc.id = child_daily_contact_supply_items.contact_id and has_childcare_office_access(c.office_id)
    )
  );

alter table child_daily_contact_supplements enable row level security;
create policy child_daily_contact_supplements_select_scoped on child_daily_contact_supplements
  for select using (
    exists (
      select 1 from child_daily_contacts cdc join children c on c.id = cdc.child_id
      where cdc.id = child_daily_contact_supplements.contact_id and has_childcare_office_access(c.office_id)
    )
  );
create policy child_daily_contact_supplements_insert_scoped on child_daily_contact_supplements
  for insert with check (
    exists (
      select 1 from child_daily_contacts cdc join children c on c.id = cdc.child_id
      where cdc.id = child_daily_contact_supplements.contact_id and has_childcare_office_access(c.office_id)
    )
  );

do $$
declare
  t text;
  audited_tables text[] := array[
    'child_daily_contacts',
    'child_daily_contact_notice_checks',
    'child_daily_contact_supply_items',
    'child_daily_contact_supplements'
  ];
begin
  foreach t in array audited_tables loop
    execute format(
      'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
      t
    );
  end loop;
end $$;

-- 当日の連絡帳行が無ければ、現在の担当者割当から作成する。
create or replace function ensure_child_daily_contact(p_child_id uuid, p_business_date date)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_office_id uuid;
  v_assignee uuid;
  v_contact_id uuid;
begin
  select office_id into v_office_id from children where id = p_child_id;
  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  select assigned_employee_id into v_assignee
  from child_contact_assignments
  where child_id = p_child_id and effective_end_date is null
  limit 1;

  insert into child_daily_contacts (child_id, business_date, assignee_employee_id)
  values (p_child_id, p_business_date, v_assignee)
  on conflict (child_id, business_date) do nothing;

  select id into v_contact_id from child_daily_contacts
  where child_id = p_child_id and business_date = p_business_date;

  return v_contact_id;
end;
$$;

-- 申請(担当者本人のみ)。
create or replace function submit_child_daily_contact(p_contact_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_contact child_daily_contacts%rowtype;
  v_office_id uuid;
begin
  select * into v_contact from child_daily_contacts where id = p_contact_id for update;
  if v_contact.id is null then
    raise exception 'contact not found';
  end if;
  if v_contact.assignee_employee_id is distinct from my_employee_id() then
    raise exception 'not authorized: only the assignee can submit';
  end if;
  if v_contact.status not in ('draft', 'rejected') then
    raise exception 'contact is % and cannot be submitted', v_contact.status;
  end if;

  update child_daily_contacts
  set status = 'submitted', submitted_at = now(), rejected_reason = null
  where id = p_contact_id;

  select office_id into v_office_id from children where id = v_contact.child_id;

  insert into notifications (notification_type, title, body, channels, target_employee_id, payload)
  select
    'childcare_contact_submitted', '連絡帳の申請', null, array['in_app'], emp_id,
    jsonb_build_object('contact_id', p_contact_id, 'child_id', v_contact.child_id)
  from childcare_office_manager_employee_ids(v_office_id) as emp_id;
end;
$$;

-- 承認(管理者のみ)。直接編集・AI修正結果はp_final_textで上書き保存し、管理者コメントは
-- 保護者向け本文とは別カラム(admin_comment)に保存する。
create or replace function approve_child_daily_contact(
  p_contact_id uuid,
  p_final_text text default null,
  p_admin_comment text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_contact child_daily_contacts%rowtype;
  v_office_id uuid;
begin
  select * into v_contact from child_daily_contacts where id = p_contact_id for update;
  if v_contact.id is null then
    raise exception 'contact not found';
  end if;
  select office_id into v_office_id from children where id = v_contact.child_id;
  if not manages_childcare(v_office_id) then
    raise exception 'not authorized';
  end if;
  if v_contact.status <> 'submitted' then
    raise exception 'contact is % and cannot be approved', v_contact.status;
  end if;

  update child_daily_contacts
  set
    status = 'approved',
    approved_by = my_employee_id(),
    approved_at = now(),
    current_text = coalesce(p_final_text, current_text),
    admin_comment = p_admin_comment
  where id = p_contact_id;

  if v_contact.assignee_employee_id is not null then
    insert into notifications (notification_type, title, body, channels, target_employee_id, payload)
    values (
      'childcare_contact_approved', '連絡帳が承認されました', p_admin_comment, array['in_app'],
      v_contact.assignee_employee_id, jsonb_build_object('contact_id', p_contact_id)
    );
  end if;
end;
$$;

-- 差し戻し(管理者のみ、理由必須)。
create or replace function reject_child_daily_contact(p_contact_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_contact child_daily_contacts%rowtype;
  v_office_id uuid;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason is required';
  end if;

  select * into v_contact from child_daily_contacts where id = p_contact_id for update;
  if v_contact.id is null then
    raise exception 'contact not found';
  end if;
  select office_id into v_office_id from children where id = v_contact.child_id;
  if not manages_childcare(v_office_id) then
    raise exception 'not authorized';
  end if;
  if v_contact.status <> 'submitted' then
    raise exception 'contact is % and cannot be rejected', v_contact.status;
  end if;

  update child_daily_contacts
  set status = 'rejected', rejected_reason = p_reason, approved_by = null, approved_at = null
  where id = p_contact_id;

  if v_contact.assignee_employee_id is not null then
    insert into notifications (notification_type, title, body, channels, target_employee_id, payload)
    values (
      'childcare_contact_rejected', '連絡帳が差し戻されました', p_reason, array['in_app'],
      v_contact.assignee_employee_id, jsonb_build_object('contact_id', p_contact_id)
    );
  end if;
end;
$$;

-- 承認済みの文章のみコピー可能(コドモン運用)。基本は申請者、不在時は他職員・管理者が対応可能。
-- コピー操作の履歴(誰がいつ)を記録する。
create or replace function mark_child_daily_contact_copied(p_contact_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_contact child_daily_contacts%rowtype;
  v_office_id uuid;
begin
  select * into v_contact from child_daily_contacts where id = p_contact_id for update;
  if v_contact.id is null then
    raise exception 'contact not found';
  end if;
  select office_id into v_office_id from children where id = v_contact.child_id;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;
  if v_contact.status <> 'approved' then
    raise exception 'contact is % and only approved contacts can be copied', v_contact.status;
  end if;

  update child_daily_contacts
  set copied_by = my_employee_id(), copied_at = now()
  where id = p_contact_id;
end;
$$;
