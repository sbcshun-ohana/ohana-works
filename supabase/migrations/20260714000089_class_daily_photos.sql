-- 保護者アプリ Phase A: クラス写真(変更7)
-- 透かし入り画像のみを保存(元画像は保持しない)。掲載不可園児の確認は初期は手動
-- チェックリスト(status='checked'を経てからpublished、checked_byを必須とする運用は
-- RPC側で担保)。配信は署名付き短期URL(Supabase Storage signed URL)をAPI側で発行する。

create table class_daily_photos (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references childcare_classes(id),
  business_date date not null,
  storage_path text not null,
  thumbnail_path text,
  uploaded_by uuid not null references employees(id),
  checked_by uuid references employees(id),
  checked_at timestamptz,
  status text not null default 'draft' check (status in ('draft', 'checked', 'published')),
  published_at timestamptz,
  created_at timestamptz not null default now()
);
create index idx_class_daily_photos_class_date on class_daily_photos(class_id, business_date);

alter table class_daily_photos enable row level security;

create policy class_daily_photos_select_staff on class_daily_photos
  for select using (
    exists (select 1 from childcare_classes cc where cc.id = class_daily_photos.class_id and has_childcare_office_access(cc.office_id))
  );
create policy class_daily_photos_select_guardian on class_daily_photos
  for select using (
    status = 'published'
    and exists (
      select 1 from child_class_enrollments cce
      where cce.class_id = class_daily_photos.class_id
        and cce.effective_start_date <= class_daily_photos.business_date
        and (cce.effective_end_date is null or cce.effective_end_date >= class_daily_photos.business_date)
        and guardian_has_child_access(cce.child_id)
    )
  );
create policy class_daily_photos_insert_staff on class_daily_photos
  for insert with check (
    exists (select 1 from childcare_classes cc where cc.id = class_daily_photos.class_id and has_childcare_office_access(cc.office_id))
  );
create policy class_daily_photos_update_managers on class_daily_photos
  for update using (
    exists (select 1 from childcare_classes cc where cc.id = class_daily_photos.class_id and manages_childcare(cc.office_id))
  ) with check (
    exists (select 1 from childcare_classes cc where cc.id = class_daily_photos.class_id and manages_childcare(cc.office_id))
  );
create policy class_daily_photos_delete_managers on class_daily_photos
  for delete using (
    exists (select 1 from childcare_classes cc where cc.id = class_daily_photos.class_id and manages_childcare(cc.office_id))
  );

do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'class_daily_photos'
  );
end $$;
