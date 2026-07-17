-- 保護者アプリ Phase A 修正: 保護者ドメインの閲覧範囲に関する3つの不具合を修正
-- (ダミーデータ検証で発見。いずれも既存ポリシーは削除・変更せず、追加ポリシーの
-- 新設または対象ドメインの拡張のみ行う)。
--
-- 1. children(Phase0)に保護者向けSELECTポリシーが1つも無く、保護者が自分の子の
--    基本情報(呼び方・生年月日等)すら閲覧できなかった。
-- 2. guardian_child_linksのSELECTポリシーが「自分自身の紐付け行」のみを対象と
--    しており、同じ園児に紐づく他の保護者(共同親権者等)の紐付けが見えなかった。
--    共同で子を見ている保護者同士が互いを認識できるよう、対象園児への
--    アクセス権を持つ保護者なら誰でもその園児の紐付け一覧を見られるようにする。
-- 3. guardian_invitationsのSELECTポリシーが招待元(招待した保護者)のみを対象と
--    しており、招待を受諾した本人(accepted_by_guardian_id)が自分の招待記録を
--    閲覧できなかった。

create policy children_select_guardian on children
  for select using (guardian_has_child_access(id));

drop policy guardian_child_links_select on guardian_child_links;
create policy guardian_child_links_select on guardian_child_links
  for select using (
    guardian_has_child_access(child_id) or staff_has_guardian_data_access(child_id)
  );

drop policy guardian_invitations_select on guardian_invitations;
create policy guardian_invitations_select on guardian_invitations
  for select using (
    invited_by_guardian_id = my_guardian_id()
    or accepted_by_guardian_id = my_guardian_id()
    or staff_has_guardian_data_access(child_id)
  );
