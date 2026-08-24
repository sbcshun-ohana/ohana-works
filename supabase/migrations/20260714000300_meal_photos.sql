-- 300: 給食写真(§8)。厨房iPadで撮影→承認待ち→管理者以上が承認で保護者「給食」セクションに公開。
-- 施設×日付の「本日の給食」(クラス単位ではなく園単位)。class_daily_photos(089)と同型。
-- 元画像はクライアントから meal-photos バケットへ直接アップロードし、行のstatusで公開制御する。

create table meal_photos (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id),
  business_date date not null,
  storage_path text not null,
  caption text,
  uploaded_by uuid not null references employees(id),
  approved_by uuid references employees(id),
  approved_at timestamptz,
  status text not null default 'pending' check (status in ('pending', 'published', 'rejected')),
  rejected_reason text,
  created_at timestamptz not null default now()
);
create index idx_meal_photos_office_date on meal_photos(office_id, business_date);

alter table meal_photos enable row level security;

-- 職員=自施設の全ステータス閲覧。
create policy meal_photos_select_staff on meal_photos
  for select using (has_childcare_office_access(office_id));
-- 保護者=公開済みかつ自分の子が在籍する施設の写真のみ。
create policy meal_photos_select_guardian on meal_photos
  for select using (
    status = 'published'
    and exists (
      select 1 from children ch
      where ch.office_id = meal_photos.office_id and guardian_has_child_access(ch.id)
    )
  );
-- 送信=自施設の職員(厨房アカウント含む)。
create policy meal_photos_insert_staff on meal_photos
  for insert with check (has_childcare_office_access(office_id));
-- 承認/差し戻し=管理者以上。
create policy meal_photos_update_admins on meal_photos
  for update using (is_childcare_admin(office_id)) with check (is_childcare_admin(office_id));
-- 削除=管理者以上、または自分がアップロードした未公開分。
create policy meal_photos_delete on meal_photos
  for delete using (
    is_childcare_admin(office_id)
    or (uploaded_by = my_employee_id() and status <> 'published')
  );

do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'meal_photos'
  );
end $$;

-- ===== ストレージ(private バケット・class-photos と同方針) =====
insert into storage.buckets (id, name, public)
values ('meal-photos', 'meal-photos', false)
on conflict (id) do nothing;

create policy meal_photos_storage_read_staff on storage.objects
  for select using (bucket_id = 'meal-photos' and my_employee_id() is not null);
create policy meal_photos_storage_insert_staff on storage.objects
  for insert with check (bucket_id = 'meal-photos' and my_employee_id() is not null);
create policy meal_photos_storage_delete_staff on storage.objects
  for delete using (bucket_id = 'meal-photos' and my_employee_id() is not null);
-- 保護者=公開済み写真のパスのみ署名URL取得可。
create policy meal_photos_storage_read_guardian on storage.objects
  for select using (
    bucket_id = 'meal-photos'
    and exists (
      select 1 from meal_photos mp join children ch on ch.office_id = mp.office_id
      where mp.storage_path = storage.objects.name
        and mp.status = 'published'
        and guardian_has_child_access(ch.id)
    )
  );

-- ===== RPC =====
-- 送信(承認待ちで登録)。画像は事前に meal-photos バケットへアップロード済み。
create or replace function submit_meal_photo(p_office_id uuid, p_business_date date, p_storage_path text, p_caption text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  if not is_meal_management_enabled_for_office(p_office_id) then raise exception 'meal management disabled'; end if;
  insert into meal_photos(office_id, business_date, storage_path, caption, uploaded_by, status)
    values (p_office_id, p_business_date, p_storage_path, nullif(trim(coalesce(p_caption, '')), ''), my_employee_id(), 'pending')
    returning id into v_id;
  return v_id;
end $$;

-- 承認=公開(管理者以上)。
create or replace function approve_meal_photo(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v meal_photos%rowtype;
begin
  select * into v from meal_photos where id = p_id for update;
  if v.id is null then raise exception 'photo not found'; end if;
  if not is_childcare_admin(v.office_id) then raise exception 'not authorized'; end if;
  if v.status = 'published' then return; end if;
  update meal_photos set status = 'published', approved_by = my_employee_id(), approved_at = now(), rejected_reason = null
    where id = p_id;
end $$;

-- 差し戻し(管理者以上・理由必須)。
create or replace function reject_meal_photo(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v meal_photos%rowtype;
begin
  if p_reason is null or trim(p_reason) = '' then raise exception 'reason is required'; end if;
  select * into v from meal_photos where id = p_id for update;
  if v.id is null then raise exception 'photo not found'; end if;
  if not is_childcare_admin(v.office_id) then raise exception 'not authorized'; end if;
  update meal_photos set status = 'rejected', rejected_reason = trim(p_reason), approved_by = null, approved_at = null
    where id = p_id;
end $$;

-- 削除(管理者以上、または自分の未公開分)。
create or replace function delete_meal_photo(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v meal_photos%rowtype;
begin
  select * into v from meal_photos where id = p_id;
  if v.id is null then raise exception 'photo not found'; end if;
  if not (is_childcare_admin(v.office_id) or (v.uploaded_by = my_employee_id() and v.status <> 'published')) then
    raise exception 'not authorized';
  end if;
  delete from meal_photos where id = p_id;
end $$;

-- 職員向け一覧(自施設・指定日・全ステータス)。
create or replace function fetch_meal_photos_for_office(p_office_id uuid, p_business_date date)
returns table (id uuid, storage_path text, caption text, status text, rejected_reason text,
               uploaded_by_name text, approved_by_name text, approved_at timestamptz, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  return query
    select mp.id, mp.storage_path, mp.caption, mp.status, mp.rejected_reason,
           ue.display_name, ae.display_name, mp.approved_at, mp.created_at
    from meal_photos mp
    left join employees ue on ue.id = mp.uploaded_by
    left join employees ae on ae.id = mp.approved_by
    where mp.office_id = p_office_id and mp.business_date = p_business_date
    order by mp.created_at;
end $$;

-- 保護者向け(公開済み・その子の施設・指定日)。
create or replace function fetch_published_meal_photos_for_guardian(p_child_id uuid, p_business_date date)
returns table (id uuid, storage_path text, caption text, approved_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare v_office uuid;
begin
  if not guardian_has_child_access(p_child_id) then raise exception 'not authorized'; end if;
  select office_id into v_office from children where id = p_child_id;
  return query
    select mp.id, mp.storage_path, mp.caption, mp.approved_at
    from meal_photos mp
    where mp.office_id = v_office and mp.business_date = p_business_date and mp.status = 'published'
    order by mp.approved_at;
end $$;

grant execute on function submit_meal_photo(uuid, date, text, text) to authenticated, service_role;
grant execute on function approve_meal_photo(uuid) to authenticated, service_role;
grant execute on function reject_meal_photo(uuid, text) to authenticated, service_role;
grant execute on function delete_meal_photo(uuid) to authenticated, service_role;
grant execute on function fetch_meal_photos_for_office(uuid, date) to authenticated, service_role;
grant execute on function fetch_published_meal_photos_for_guardian(uuid, date) to authenticated, service_role;
