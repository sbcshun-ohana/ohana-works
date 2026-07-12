-- publicスキーマの標準ロール(anon/authenticated/service_role)への権限付与
--
-- 現象: Edge Function内でservice_roleキーを使ったクエリが
-- "permission denied for table employees" で失敗。RLSによる行フィルタではなく、
-- Postgresのテーブル権限(GRANT)自体がanon/authenticated/service_roleに
-- 付与されていなかったことが原因。通常Supabaseプロジェクトでは新規テーブルに
-- 自動付与されるが、CLI経由の`db push`ではこの既定権限が適用されていなかった。
--
-- RLSは既に全テーブルで有効化・ポリシー設定済みのため、GRANTを広く付与しても
-- anon/authenticatedの実効アクセス範囲はRLSポリシーで制限される。
-- service_roleはSupabase標準でBYPASSRLS属性を持つため、GRANTのみで意図通り
-- 全行アクセス可能になる。

grant usage on schema public to anon, authenticated, service_role;

grant select, insert, update, delete on all tables in schema public to anon, authenticated, service_role;
grant usage, select on all sequences in schema public to anon, authenticated, service_role;
grant execute on all functions in schema public to anon, authenticated, service_role;

-- 今後作成されるテーブル・シーケンス・関数にも同様の権限を既定で付与する
alter default privileges in schema public
  grant select, insert, update, delete on tables to anon, authenticated, service_role;
alter default privileges in schema public
  grant usage, select on sequences to anon, authenticated, service_role;
alter default privileges in schema public
  grant execute on functions to anon, authenticated, service_role;
