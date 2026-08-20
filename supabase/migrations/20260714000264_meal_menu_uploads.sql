-- 264: 給食管理 Phase 6(前半)= 献立・食育レターのアップロード+版管理+公開+保護者配信(非AI退避構成)。
-- 設計書 給食管理v1.0(2026-08-19)§9。AI解析による日別構造化(menu_days)は後半(OpenRouter準備後)。
-- ここでは「月次で献立/食育レターのファイルをアップロード→版管理→公開→保護者アプリで閲覧」を実装する。
-- 献立の取込・確認・公開=主任以上(§10)。保護者は自分の子の施設の公開済みのみ閲覧。

-- ============================================================
-- (1) 保護者向け給食セクションの機能フラグ(§12・既定OFF・施設別ON)
-- ============================================================
insert into feature_flags (feature_key, name, description, default_enabled)
select 'meal_parent_section_enabled', '給食(保護者公開)',
  '保護者アプリの給食セクション(本日の給食写真・今日/今月の献立・食育レター)の施設別公開', false
where not exists (select 1 from feature_flags where feature_key = 'meal_parent_section_enabled');

create or replace function is_meal_parent_section_enabled_for_office(p_office_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select is_feature_enabled_for_office('meal_parent_section_enabled', p_office_id);
$$;
grant execute on function is_meal_parent_section_enabled_for_office(uuid) to anon, authenticated, service_role;

-- ============================================================
-- (2) 献立取込(月×施設×版)。ai_result は将来のAI解析用(退避構成では null)。
-- ============================================================
create table menu_imports (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id) on delete cascade,
  target_month date not null,          -- 月初日(YYYY-MM-01に正規化)
  format text not null check (format in ('excel', 'pdf', 'image')),
  source_path text not null,           -- meal-menus バケットのパス
  source_filename text,
  ai_result jsonb,                     -- AI解析結果(将来)。退避構成では null
  status text not null default 'draft' check (status in ('draft', 'published', 'superseded')),
  version int not null default 1,
  note text,
  uploaded_by uuid references employees(id),
  published_by uuid references employees(id),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_menu_imports_office_month on menu_imports(office_id, target_month, version desc);
create trigger trg_menu_imports_updated_at before update on menu_imports
  for each row execute function set_updated_at();
alter table menu_imports enable row level security;  -- 直接アクセス不可(全てRPC経由)

-- ============================================================
-- (3) 食育レター(月×施設・委託先PDF)
-- ============================================================
create table nutrition_letters (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id) on delete cascade,
  target_month date not null,
  source_path text not null,
  source_filename text,
  status text not null default 'draft' check (status in ('draft', 'published', 'superseded')),
  version int not null default 1,
  uploaded_by uuid references employees(id),
  published_by uuid references employees(id),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_nutrition_letters_office_month on nutrition_letters(office_id, target_month, version desc);
create trigger trg_nutrition_letters_updated_at before update on nutrition_letters
  for each row execute function set_updated_at();
alter table nutrition_letters enable row level security;

-- ============================================================
-- (4) Storage バケット(private)+ポリシー。パス規約: {office_id}/{target_month}/{version}/{filename}
-- ============================================================
insert into storage.buckets (id, name, public) values ('meal-menus', 'meal-menus', false)
on conflict (id) do nothing;

drop policy if exists meal_menus_staff_read on storage.objects;
drop policy if exists meal_menus_staff_write on storage.objects;
drop policy if exists meal_menus_staff_delete on storage.objects;
drop policy if exists meal_menus_guardian_read on storage.objects;

create policy meal_menus_staff_read on storage.objects for select
  using (bucket_id = 'meal-menus' and my_employee_id() is not null);
create policy meal_menus_staff_write on storage.objects for insert
  with check (bucket_id = 'meal-menus' and my_employee_id() is not null);
create policy meal_menus_staff_delete on storage.objects for delete
  using (bucket_id = 'meal-menus' and my_employee_id() is not null);
-- 保護者は「自分の子の施設」の「公開済み」献立/レターファイルのみ閲覧可
create policy meal_menus_guardian_read on storage.objects for select using (
  bucket_id = 'meal-menus'
  and ((storage.foldername(name))[1])::uuid in (
    select c.office_id from guardian_child_links gcl
    join children c on c.id = gcl.child_id
    where gcl.guardian_id = my_guardian_id()
  )
  and (
    exists (select 1 from menu_imports mi where mi.source_path = name and mi.status = 'published')
    or exists (select 1 from nutrition_letters nl where nl.source_path = name and nl.status = 'published')
  )
);

-- ============================================================
-- (5) RPC — 職員側(取込・公開・一覧)。取込/公開=主任以上(manages_childcare)。閲覧=施設職員。
-- ============================================================

-- 献立の新規アップロード(ファイルはクライアントがStorageへ先にput済み。行を作成=draft・版=最新+1)
create or replace function create_menu_import(
  p_office_id uuid, p_target_month date, p_format text, p_source_path text, p_source_filename text
)
returns menu_imports language plpgsql security definer set search_path = public as $$
declare v_row menu_imports; v_month date := date_trunc('month', p_target_month)::date; v_ver int;
begin
  if not is_meal_management_enabled_for_office(p_office_id) then raise exception 'feature disabled'; end if;
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  if p_format not in ('excel', 'pdf', 'image') then raise exception 'invalid format'; end if;
  select coalesce(max(version), 0) + 1 into v_ver from menu_imports where office_id = p_office_id and target_month = v_month;
  insert into menu_imports (office_id, target_month, format, source_path, source_filename, version, uploaded_by)
  values (p_office_id, v_month, p_format, p_source_path, p_source_filename, v_ver, my_employee_id())
  returning * into v_row;
  return v_row;
end $$;
grant execute on function create_menu_import(uuid, date, text, text, text) to authenticated, service_role;

-- 献立の公開(同一月の旧公開版を superseded にして本行を published に)
create or replace function publish_menu_import(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v menu_imports;
begin
  select * into v from menu_imports where id = p_id;
  if v.id is null then raise exception 'not found'; end if;
  if not manages_childcare(v.office_id) then raise exception 'not authorized'; end if;
  update menu_imports set status = 'superseded'
    where office_id = v.office_id and target_month = v.target_month and status = 'published' and id <> p_id;
  update menu_imports set status = 'published', published_by = my_employee_id(), published_at = now()
    where id = p_id;
end $$;
grant execute on function publish_menu_import(uuid) to authenticated, service_role;

-- 献立の削除(行のみ。Storage実体はクライアントが別途削除)
create or replace function delete_menu_import(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v menu_imports;
begin
  select * into v from menu_imports where id = p_id;
  if v.id is null then raise exception 'not found'; end if;
  if not manages_childcare(v.office_id) then raise exception 'not authorized'; end if;
  delete from menu_imports where id = p_id;
end $$;
grant execute on function delete_menu_import(uuid) to authenticated, service_role;

-- 職員向け一覧(施設×月の全版)。閲覧=施設アクセス。
create or replace function fetch_menu_imports(p_office_id uuid, p_target_month date)
returns table (
  id uuid, target_month date, format text, source_path text, source_filename text,
  status text, version int, note text, uploaded_by_name text, published_at timestamptz, created_at timestamptz
) language plpgsql security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  return query
    select mi.id, mi.target_month, mi.format, mi.source_path, mi.source_filename,
           mi.status, mi.version, mi.note, e.name, mi.published_at, mi.created_at
    from menu_imports mi
    left join employees e on e.id = mi.uploaded_by
    where mi.office_id = p_office_id and mi.target_month = date_trunc('month', p_target_month)::date
    order by mi.version desc;
end $$;
grant execute on function fetch_menu_imports(uuid, date) to authenticated, service_role;

-- 食育レター: アップロード/公開/削除/一覧(献立と同型)
create or replace function create_nutrition_letter(
  p_office_id uuid, p_target_month date, p_source_path text, p_source_filename text
)
returns nutrition_letters language plpgsql security definer set search_path = public as $$
declare v_row nutrition_letters; v_month date := date_trunc('month', p_target_month)::date; v_ver int;
begin
  if not is_meal_management_enabled_for_office(p_office_id) then raise exception 'feature disabled'; end if;
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  select coalesce(max(version), 0) + 1 into v_ver from nutrition_letters where office_id = p_office_id and target_month = v_month;
  insert into nutrition_letters (office_id, target_month, source_path, source_filename, version, uploaded_by)
  values (p_office_id, v_month, p_source_path, p_source_filename, v_ver, my_employee_id())
  returning * into v_row;
  return v_row;
end $$;
grant execute on function create_nutrition_letter(uuid, date, text, text) to authenticated, service_role;

create or replace function publish_nutrition_letter(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v nutrition_letters;
begin
  select * into v from nutrition_letters where id = p_id;
  if v.id is null then raise exception 'not found'; end if;
  if not manages_childcare(v.office_id) then raise exception 'not authorized'; end if;
  update nutrition_letters set status = 'superseded'
    where office_id = v.office_id and target_month = v.target_month and status = 'published' and id <> p_id;
  update nutrition_letters set status = 'published', published_by = my_employee_id(), published_at = now()
    where id = p_id;
end $$;
grant execute on function publish_nutrition_letter(uuid) to authenticated, service_role;

create or replace function delete_nutrition_letter(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v nutrition_letters;
begin
  select * into v from nutrition_letters where id = p_id;
  if v.id is null then raise exception 'not found'; end if;
  if not manages_childcare(v.office_id) then raise exception 'not authorized'; end if;
  delete from nutrition_letters where id = p_id;
end $$;
grant execute on function delete_nutrition_letter(uuid) to authenticated, service_role;

create or replace function fetch_nutrition_letters(p_office_id uuid, p_target_month date)
returns table (
  id uuid, target_month date, source_path text, source_filename text,
  status text, version int, uploaded_by_name text, published_at timestamptz, created_at timestamptz
) language plpgsql security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  return query
    select nl.id, nl.target_month, nl.source_path, nl.source_filename,
           nl.status, nl.version, e.name, nl.published_at, nl.created_at
    from nutrition_letters nl
    left join employees e on e.id = nl.uploaded_by
    where nl.office_id = p_office_id and nl.target_month = date_trunc('month', p_target_month)::date
    order by nl.version desc;
end $$;
grant execute on function fetch_nutrition_letters(uuid, date) to authenticated, service_role;

-- ============================================================
-- (6) RPC — 保護者側(公開済みのみ)。給食セクションが有効な施設のみ。
-- ============================================================
create or replace function fetch_published_meal_menu(p_office_id uuid, p_target_month date)
returns table (kind text, source_path text, source_filename text, format text, published_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  -- 保護者は自分の子の施設のみ(guardian_has_office_access相当を子リンクで判定)
  if not exists (
    select 1 from guardian_child_links gcl join children c on c.id = gcl.child_id
    where gcl.guardian_id = my_guardian_id() and c.office_id = p_office_id
  ) then raise exception 'not authorized'; end if;
  if not is_meal_parent_section_enabled_for_office(p_office_id) then return; end if;
  return query
    select 'menu'::text, mi.source_path, mi.source_filename, mi.format, mi.published_at
    from menu_imports mi
    where mi.office_id = p_office_id and mi.target_month = date_trunc('month', p_target_month)::date and mi.status = 'published'
    union all
    select 'letter'::text, nl.source_path, nl.source_filename, 'pdf'::text, nl.published_at
    from nutrition_letters nl
    where nl.office_id = p_office_id and nl.target_month = date_trunc('month', p_target_month)::date and nl.status = 'published';
end $$;
grant execute on function fetch_published_meal_menu(uuid, date) to authenticated, service_role;
