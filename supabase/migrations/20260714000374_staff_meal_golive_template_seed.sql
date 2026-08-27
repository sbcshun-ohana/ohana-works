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
