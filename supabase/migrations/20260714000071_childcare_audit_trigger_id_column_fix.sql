-- 保育業務 Phase0/Phase1 修正: idカラムを持たないテーブルへの監査トリガー誤適用を解消
--
-- 不具合: 共通のlog_event_change()トリガー関数はnew.id/old.idを参照するため、
-- 主キーがidという名前のuuid列ではないテーブルに適用すると、書込み時に
-- 「record "new" has no field "id"」で例外になる(ダミーデータ検証で発見)。
-- 既存コードでもnotice_recipients(複合主キー)は元々audited_tablesに含めておらず、
-- 同じ理由による意図的な除外だったと考えられる。
--
-- 該当テーブルと主キー:
--   feature_flags               主キー = feature_key (text)
--   childcare_office_settings    主キー = office_id (uuid)
--   child_daily_contact_notice_checks 主キー = (contact_id, notice_master_id) の複合キー
--
-- これらはlog_event_change()による自動監査対象から外す(それ以外のテーブルの監査は維持)。

drop trigger if exists trg_audit_feature_flags on feature_flags;
drop trigger if exists trg_audit_childcare_office_settings on childcare_office_settings;
drop trigger if exists trg_audit_child_daily_contact_notice_checks on child_daily_contact_notice_checks;
