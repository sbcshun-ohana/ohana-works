-- 保育業務 Phase0: 監査履歴
-- 既存のevent_logsテーブル + log_event_change()トリガー(20260710160005で定義済み)を
-- そのまま再利用する。新規の履歴テーブルは作らない。

do $$
declare
  t text;
  audited_tables text[] := array[
    'feature_flags',
    'feature_flag_office_overrides',
    'feature_flag_employee_overrides',
    'childcare_classes',
    'children',
    'child_class_enrollments',
    'employee_class_access'
  ];
begin
  foreach t in array audited_tables loop
    execute format(
      'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
      t
    );
  end loop;
end $$;
