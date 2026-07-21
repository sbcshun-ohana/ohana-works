-- 保護者アプリ Phase A: クラス写真のStorageに保護者向けSELECTポリシーを追加
--
-- 103のコメント通り「保護者(guardian)からの署名付きURL発行は、保護者アプリ実装時に
-- 別途対応する」ための対応。class_daily_photosテーブル側にはguardian向けSELECTポリシー
-- (class_daily_photos_select_guardian、公開済みかつ自分の園児のクラスのみ)が既にあるが、
-- storage.objects側は職員限定(my_employee_id() is not null)のままだったため、
-- 保護者はstorage_pathを取得できても画像そのもの(署名付きURL発行・ダウンロード)には
-- アクセスできない状態だった。
--
-- class_daily_photos_select_guardianと同じ条件(status='published'かつ
-- 対象クラスに在籍する自分の園児がいる)を、object名(storage_path)照合で再現する。

create policy class_photos_storage_read_guardian on storage.objects
  for select using (
    bucket_id = 'class-photos'
    and exists (
      select 1
      from class_daily_photos cdp
      join child_class_enrollments cce on cce.class_id = cdp.class_id
      where cdp.storage_path = storage.objects.name
        and cdp.status = 'published'
        and cce.effective_start_date <= cdp.business_date
        and (cce.effective_end_date is null or cce.effective_end_date >= cdp.business_date)
        and guardian_has_child_access(cce.child_id)
    )
  );
