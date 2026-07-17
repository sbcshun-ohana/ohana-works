-- 保護者アプリ・後続保育機能 Phase A: 機能フラグの新規キー投入
-- 機能単位×施設単位×職員単位でON/OFFできるよう、既存のfeature_flags基盤(Phase0)を
-- そのまま使う(新しいテーブルは作らず、feature_keyを追加するだけ)。すべて既定OFF。
--
-- Phase Aで実際に使うキーのみ投入する(billing/nap_check/near_miss/weekly_plans等は
-- 該当フェーズ(B〜E)着手時にそのフェーズのマイグレーションで追加する)。

insert into feature_flags (feature_key, name, description, default_enabled) values
  ('guardian_app', '保護者アプリ', '保護者アカウント・招待・保護者アプリ全体の有効化フラグ', false),
  ('attendance_qr', '登降園QR', '保護者アプリの動的QRによる登降園記録機能', false),
  ('family_daily_report', '家庭連絡帳', '保護者から園への家庭連絡帳(体温・症状等)入力機能', false),
  ('class_photos', 'クラス写真', 'クラス写真の保護者アプリへの配信機能', false);
