-- 保護者アプリ Phase A 修正: child_daily_contacts(Phase1)に保護者向けSELECTポリシーを追加
--
-- 不具合: 既存のchild_daily_contacts_select_scopedポリシーは職員側(has_childcare_office_access)
-- のみを許可しており、保護者ドメイン(guardian_has_child_access)向けのポリシーが
-- 一つも無かった。そのため保護者は承認済みの連絡帳すら閲覧できず、
-- communication_book_reads/confirmationsへのINSERT時のサブクエリ(child_daily_contactsを
-- 参照)もRLSに阻まれて失敗していた(ダミーデータ検証で発見)。
--
-- 既存ポリシーは変更せず、承認済み(status='approved')の行のみを対象とする
-- 追加の許可ポリシー(OR条件として加算される)を新設する。

create policy child_daily_contacts_select_guardian on child_daily_contacts
  for select using (
    status = 'approved' and guardian_has_child_access(child_id)
  );
