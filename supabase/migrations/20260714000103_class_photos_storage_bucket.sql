-- 保護者アプリ Phase A: クラス写真格納用バケット(変更7)
--
-- クレジット透かし入り画像はクライアント側(Canvas)で生成してからアップロードするため、
-- 元画像自体がサーバーに送信・保存されることはない。
-- 実際のアクセス制御はclass_daily_photos側のRLSで行毎に絞られているため
-- (=見えないclass_daily_photos行のstorage_pathはクライアントがそもそも取得できない)、
-- ストレージ側は既存notice-attachmentsと同じ簡易方針(職員は全体読み取り可)とする。
-- 保護者(guardian)からの署名付きURL発行は、保護者アプリ実装時に別途対応する。

insert into storage.buckets (id, name, public)
values ('class-photos', 'class-photos', false)
on conflict (id) do nothing;

create policy class_photos_storage_read on storage.objects
  for select using (
    bucket_id = 'class-photos' and my_employee_id() is not null
  );

create policy class_photos_storage_insert on storage.objects
  for insert with check (
    bucket_id = 'class-photos' and my_employee_id() is not null
  );

create policy class_photos_storage_delete on storage.objects
  for delete using (
    bucket_id = 'class-photos' and my_employee_id() is not null
  );
