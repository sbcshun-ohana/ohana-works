-- 保護者アプリ Phase A 修正: 園連絡帳の「個別お知らせ・備品利用」に保護者向けSELECTポリシーを追加
--
-- 不具合: 指示書§5.3(変更4)は園連絡帳の公開項目に「本文・個別お知らせ・備品利用・
-- 午睡時間・排泄・食事・検温・入浴」を挙げているが、child_daily_contacts本体には
-- 097で保護者向けポリシーを追加した一方、個別お知らせ(child_daily_contact_notice_checks)・
-- 備品利用(child_daily_contact_supply_items)・そのラベル元であるindividual_notice_masters
-- には保護者向けポリシーが1つも無かった(職員側has_childcare_office_access限定)。
-- そのため承認済み連絡帳でもこの2項目だけ保護者から閲覧できない状態だった
-- (園連絡帳閲覧画面の実装着手前の調査で発見)。
--
-- 既存ポリシーは変更せず、承認済み(status='approved')の連絡帳に紐づく行のみを対象とする
-- 追加の許可ポリシー(OR条件として加算される)を新設する。

create policy child_daily_contact_notice_checks_select_guardian on child_daily_contact_notice_checks
  for select using (
    exists (
      select 1 from child_daily_contacts cdc
      where cdc.id = child_daily_contact_notice_checks.contact_id
        and cdc.status = 'approved'
        and guardian_has_child_access(cdc.child_id)
    )
  );

create policy child_daily_contact_supply_items_select_guardian on child_daily_contact_supply_items
  for select using (
    exists (
      select 1 from child_daily_contacts cdc
      where cdc.id = child_daily_contact_supply_items.contact_id
        and cdc.status = 'approved'
        and guardian_has_child_access(cdc.child_id)
    )
  );

create policy individual_notice_masters_select_guardian on individual_notice_masters
  for select using (
    exists (
      select 1 from children c
      where c.office_id = individual_notice_masters.office_id
        and guardian_has_child_access(c.id)
    )
  );
