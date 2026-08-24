-- 310: 重要事項説明書のアプリ化 Phase A(PDF方式)。管理者がPDFを公開→保護者がアプリで閲覧→氏名入力で同意(不変記録)。
-- 同意は世帯単位(俊確定・一人=世帯全員同意)。将来Phase B=アプリ内構造化作成で置換予定。再実行可(冪等)。
create table if not exists important_matters_documents (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id),
  fiscal_year int not null,
  title text not null,
  storage_path text not null,             -- important-matters バケットのPDFパス
  version int not null default 1,
  is_published boolean not null default true,
  published_by uuid references employees(id),
  published_at timestamptz not null default now(),
  note text,
  created_at timestamptz not null default now()
);
create index if not exists idx_imd_office_year on important_matters_documents(office_id, fiscal_year desc, version desc);
alter table important_matters_documents enable row level security;

-- 同意は世帯単位(俊確定): 一人が同意すれば世帯全員(きょうだい・保護者全員)が同意したとみなす。
create table if not exists important_matters_consents (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references important_matters_documents(id) on delete cascade,
  household_id uuid not null references households(id) on delete cascade,
  office_id uuid not null references offices(id),
  guardian_id uuid references guardians(id),         -- 実際に同意操作をした保護者
  agreed_guardian_name text not null,
  doc_title_snapshot text not null,       -- 同意時点のタイトル/版を固定
  doc_version_snapshot int not null,
  agreed_at timestamptz not null default now(),
  unique (document_id, household_id)
);
create index if not exists idx_imc_doc on important_matters_consents(document_id);
create index if not exists idx_imc_household on important_matters_consents(household_id, agreed_at desc);
alter table important_matters_consents enable row level security;
-- アクセスは security definer RPC のみ(直接のRLSポリシーは置かない)。

-- ===== ストレージ(private) =====
insert into storage.buckets (id, name, public) values ('important-matters', 'important-matters', false)
on conflict (id) do nothing;
drop policy if exists im_storage_staff_rw on storage.objects;
create policy im_storage_staff_rw on storage.objects
  for all using (bucket_id = 'important-matters' and my_employee_id() is not null)
  with check (bucket_id = 'important-matters' and my_employee_id() is not null);
-- 保護者=公開済み文書のパスのみ署名URL取得可(自分の子の施設)。
drop policy if exists im_storage_guardian_read on storage.objects;
create policy im_storage_guardian_read on storage.objects
  for select using (
    bucket_id = 'important-matters'
    and exists (
      select 1 from important_matters_documents d join children ch on ch.office_id = d.office_id
      where d.storage_path = storage.objects.name and d.is_published and guardian_has_child_access(ch.id)
    )
  );

-- ===== RPC(管理) =====
-- 公開(管理者以上)。同一施設×年度の版を+1して公開。
create or replace function save_important_matters_document(p_office_id uuid, p_fiscal_year int, p_title text, p_storage_path text, p_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_ver int; v_id uuid;
begin
  if not is_childcare_admin(p_office_id) then raise exception 'not authorized'; end if;
  select coalesce(max(version), 0) + 1 into v_ver from important_matters_documents where office_id = p_office_id and fiscal_year = p_fiscal_year;
  insert into important_matters_documents (office_id, fiscal_year, title, storage_path, version, is_published, published_by, note)
    values (p_office_id, p_fiscal_year, p_title, p_storage_path, v_ver, true, my_employee_id(), nullif(trim(coalesce(p_note,'')),''))
    returning id into v_id;
  return v_id;
end $$;
grant execute on function save_important_matters_document(uuid, int, text, text, text) to authenticated, service_role;

-- 一覧(主任以上)。
create or replace function fetch_important_matters_documents(p_office_id uuid)
returns table (id uuid, fiscal_year int, title text, storage_path text, version int, is_published boolean,
               published_at timestamptz, note text, consented_count bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  return query
    select d.id, d.fiscal_year, d.title, d.storage_path, d.version, d.is_published, d.published_at, d.note,
           (select count(*) from important_matters_consents c where c.document_id = d.id)
    from important_matters_documents d
    where d.office_id = p_office_id
    order by d.fiscal_year desc, d.version desc;
end $$;
grant execute on function fetch_important_matters_documents(uuid) to authenticated, service_role;

-- 同意状況(主任以上)。園の在籍児ごとに、その世帯が同意済みか(世帯単位)を返す。
create or replace function fetch_important_matters_consent_status(p_document_id uuid)
returns table (child_id uuid, child_name text, class_name text, consented boolean, agreed_guardian_name text, agreed_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from important_matters_documents where id = p_document_id;
  if v_office is null then raise exception 'not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  return query
    select ch.id, ch.display_name, cc.class_name,
           (imc.id is not null), imc.agreed_guardian_name, imc.agreed_at
    from children ch
    left join child_class_enrollments cce on cce.child_id = ch.id and cce.effective_end_date is null
    left join childcare_classes cc on cc.id = cce.class_id
    left join important_matters_consents imc on imc.document_id = p_document_id and imc.household_id = ch.household_id
    where ch.office_id = v_office and ch.enrollment_status = '在籍中'
    order by cc.class_name nulls last, ch.display_name;
end $$;
grant execute on function fetch_important_matters_consent_status(uuid) to authenticated, service_role;

-- ===== RPC(保護者) =====
-- 対象児の施設で公開中の最新重要事項説明書 + 自分(その子)の同意状況。
create or replace function fetch_active_important_matters(p_child_id uuid)
returns table (id uuid, title text, fiscal_year int, version int, storage_path text, published_at timestamptz,
               consented boolean, agreed_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare v_office uuid;
begin
  if not guardian_has_child_access(p_child_id) then raise exception 'not authorized'; end if;
  select ch.office_id into v_office from children ch where ch.id = p_child_id;
  return query
    select d.id, d.title, d.fiscal_year, d.version, d.storage_path, d.published_at,
           (c.id is not null), c.agreed_at
    from important_matters_documents d
    left join children ch2 on ch2.id = p_child_id
    left join important_matters_consents c on c.document_id = d.id and c.household_id = ch2.household_id
    where d.office_id = v_office and d.is_published
    order by d.fiscal_year desc, d.version desc
    limit 1;
end $$;
grant execute on function fetch_active_important_matters(uuid) to authenticated, service_role;

-- 同意(保護者・不変記録)。同意時点のタイトル/版をsnapshot。
create or replace function submit_important_matters_consent(p_document_id uuid, p_child_id uuid, p_agreed_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_title text; v_ver int; v_id uuid; v_household uuid;
begin
  if not guardian_has_child_access(p_child_id) then raise exception 'not authorized'; end if;
  if coalesce(trim(p_agreed_name), '') = '' then raise exception 'name required'; end if;
  select office_id, title, version into v_office, v_title, v_ver from important_matters_documents where id = p_document_id and is_published;
  if v_office is null then raise exception 'document not found'; end if;
  -- 世帯単位。子の世帯→無ければ同意者(保護者)の世帯を採用。
  select coalesce(ch.household_id, g.household_id) into v_household
    from children ch left join guardians g on g.id = my_guardian_id()
    where ch.id = p_child_id;
  if v_household is null then raise exception '世帯情報が未設定です(households未設定)'; end if;
  insert into important_matters_consents (document_id, household_id, office_id, guardian_id, agreed_guardian_name, doc_title_snapshot, doc_version_snapshot)
    values (p_document_id, v_household, v_office, my_guardian_id(), trim(p_agreed_name), v_title, v_ver)
  on conflict (document_id, household_id) do nothing
  returning id into v_id;
  return v_id;
end $$;
grant execute on function submit_important_matters_consent(uuid, uuid, text) to authenticated, service_role;
