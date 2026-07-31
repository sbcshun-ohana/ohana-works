-- 149 の staff_pins 監査トリガのバグ修正(拒否側E2Eで発覚)。
-- log_event_change() は new.id/old.id を参照するが staff_pins の主キーは employee_id で
-- id 列が無いため、INSERT/UPDATE/DELETE で「record "new" has no field "id"」で失敗する。
-- さらに event_logs.after_data に pin_hash が入るのは機微上望ましくない。
-- よって staff_pins からは log_event_change トリガを外す。
-- PINログイン試行は pin_login_attempts に(pin_hash を含めず)記録済みで監査は担保される。
drop trigger if exists trg_audit_staff_pins on staff_pins;
