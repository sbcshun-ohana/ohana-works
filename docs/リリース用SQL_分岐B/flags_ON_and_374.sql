-- §6 フラグON(2026-08-28・俊承認済みマトリクス)+ 374再実行(給食ONとセット)
-- 全施設ON=職員系コア / 大和のみON=療育・感染症・保護者系 / OFF維持=family_checkin・infection_gate・outing_other・meal保護者系
insert into feature_flag_office_overrides (feature_key, office_id, enabled)
select k.key, o.id, true
from offices o
cross join (values
  ('childcare_operations'), ('childcare_home_enabled'), ('child_internal_notes_enabled'),
  ('class_messaging_enabled'), ('development_records_enabled'), ('incident_reports_enabled'),
  ('guidance_plans_enabled'), ('enrollment_form_enabled'), ('food_check_enabled'),
  ('meal_management_enabled')
) as k(key)
on conflict (feature_key, office_id) do update set enabled = true;

insert into feature_flag_office_overrides (feature_key, office_id, enabled)
select k.key, o.id, true
from offices o
cross join (values
  ('therapy_outing_enabled'), ('infection_control_enabled'),
  ('guardian_app'), ('attendance_qr'), ('family_daily_report'), ('communication_book'),
  ('guardian_notices'), ('guardian_requests'), ('parent_broadcast_notices'), ('class_photos'),
  ('medication_report_enabled'), ('pickup_id_document_enabled')
) as k(key)
where o.office_code = 'O'
on conflict (feature_key, office_id) do update set enabled = true;

-- ===== 374 再実行(給食ON施設の職員へ月〜金テンプレ付与) =====
-- 374: 職員給食 自己注文モデル go-live 初期テンプレ seed(俊指示 2026-08-27・既定A)。
--   稼働初日に「全職員テンプレ空=給食ゼロ」になるのを防ぐため、給食有効施設に所属する在職職員で
--   まだ曜日テンプレが無い曜日に「月〜金=食べる(will_eat=true)」を初期投入する。
--   ・gap-fill / 冪等: 既存テンプレ行(職員×曜日)は温存(on conflict do nothing)。各職員はアプリで調整可能。
--   ・土日(weekday 5/6)は投入しない(既定=食べない)。
--   ・対象: home_office_id が meal_management_enabled、在職(hire<=当日, 未退職)。
--   ※本番切替の直前に適用(migration列の一部として本番反映時に実行される)。
insert into staff_meal_weekly_templates (employee_id, weekday, will_eat, office_id)
select e.id, g.wd, true, null
from employees e
cross join (values (0), (1), (2), (3), (4)) g(wd)   -- 0=月 〜 4=金
where e.home_office_id is not null
  and e.resignation_date is null
  and e.hire_date <= (now() at time zone 'Asia/Tokyo')::date
  and is_feature_enabled_for_office('meal_management_enabled', e.home_office_id)
on conflict (employee_id, weekday) do nothing;

-- ===== 確認 =====
select feature_key, count(*) filter (where enabled) as on_offices
from feature_flag_office_overrides group by 1 order by 1;
