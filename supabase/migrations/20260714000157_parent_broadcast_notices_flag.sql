-- お知らせ(保護者向け一斉配信)Phase D: parent_app 表示の機能フラグ。
-- default OFF。staging は大和のみ seed_staging.ts でON、本番はリリースまでOFF。
-- 既存 'guardian_notices' フラグ(連絡帳の個別お知らせ用)とは別物・キーを分離する。
insert into feature_flags (feature_key, name, description, default_enabled) values
  ('parent_broadcast_notices', '保護者向けお知らせ(一斉配信)',
   'parent_app で保護者向け一斉配信お知らせの一覧/詳細を表示', false)
on conflict (feature_key) do nothing;
