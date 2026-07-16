-- 保育業務 Phase1: 通知テンプレート・アラート条件の追加
-- 既存のnotifications/notification_templates/alert_rules(20260710160005で定義済み)を再利用し、
-- 新規テーブルは作らない。状態遷移(申請/承認/差し戻し)の通知は各RPC内でnotificationsへ
-- 直接insertし、本ファイルではその表示用テンプレートと締切アラートの条件を投入する。
--
-- 締切前/超過アラート(alert_rules)は条件マスタの投入のみ行い、実際の評価・発火(スケジューラ)は
-- 本フェーズでは実装しない(既存プロジェクトにもアラート評価エンジンの実装は無いため)。

insert into notification_templates (template_key, title_template, body_template, channels) values
  ('childcare_class_activity_submitted', 'クラス活動の申請', 'クラス活動が申請されました。', array['in_app']),
  ('childcare_class_activity_approved', 'クラス活動が承認されました', 'クラス活動が承認されました。', array['in_app']),
  ('childcare_class_activity_rejected', 'クラス活動が差し戻されました', '理由: {{reason}}', array['in_app']),
  ('childcare_contact_submitted', '連絡帳の申請', '連絡帳が申請されました。', array['in_app']),
  ('childcare_contact_approved', '連絡帳が承認されました', '連絡帳が承認されました。', array['in_app']),
  ('childcare_contact_rejected', '連絡帳が差し戻されました', '理由: {{reason}}', array['in_app']);

insert into alert_rules (alert_key, name, description, severity, target_role_codes, condition_config) values
  (
    'childcare_class_activity_deadline_soon', 'クラス活動入力締切前',
    'クラス活動の入力・申請締切時刻(childcare_office_settings.class_activity_deadline_time)が近い',
    'normal', array['staff'],
    jsonb_build_object('feature', 'class_daily_activities', 'deadline_field', 'class_activity_deadline_time')
  ),
  (
    'childcare_class_activity_deadline_over', 'クラス活動入力締切超過',
    'クラス活動が締切時刻までに申請されていない',
    'high', array['director', 'chief', 'office_manager'],
    jsonb_build_object('feature', 'class_daily_activities', 'deadline_field', 'class_activity_deadline_time')
  ),
  (
    'childcare_contact_deadline_soon', '連絡帳承認締切前',
    '連絡帳の承認締切時刻(childcare_office_settings.contact_approval_deadline_time)が近い',
    'normal', array['director', 'chief', 'office_manager'],
    jsonb_build_object('feature', 'child_daily_contacts', 'deadline_field', 'contact_approval_deadline_time')
  ),
  (
    'childcare_contact_deadline_over', '連絡帳承認締切超過',
    '連絡帳が承認締切時刻までに処理されていない',
    'high', array['director', 'chief', 'office_manager'],
    jsonb_build_object('feature', 'child_daily_contacts', 'deadline_field', 'contact_approval_deadline_time')
  );
