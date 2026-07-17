-- 保護者アプリ Phase A 修正: child_class_enrollments(Phase0)に保護者向けSELECTポリシーを追加
--
-- 不具合: class_daily_photos_select_guardianポリシーはchild_class_enrollmentsを
-- サブクエリで参照するが、child_class_enrollments自体のRLSが職員側
-- (has_childcare_office_access)のみで保護者向けポリシーが無かったため、
-- サブクエリが保護者コンテキストでは常に0件になり、公開済みのクラス写真が
-- 保護者から一切見えなくなっていた(ダミーデータ検証で発見)。
-- 既存ポリシーは変更せず、追加ポリシーのみ新設する。

create policy child_class_enrollments_select_guardian on child_class_enrollments
  for select using (guardian_has_child_access(child_id));
