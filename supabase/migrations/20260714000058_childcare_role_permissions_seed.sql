-- 保育業務 Phase0: role_permissions初期値
-- 既存ロール(system_admin/director・chief・office_manager/staff)に
-- 保育業務3階層(システム管理者/管理者/一般職員)をマッピングする。
-- labor_manager(給与専用ロール)・viewerには既定で権限を付与しない。
-- 本テーブルは現時点でRLSポリシーからは参照されない(将来、管理者Web/RPC側での
-- 細かい権限判定に用いる想定。20260710160006_rls.sqlの既存コメント方針を踏襲)。

insert into role_permissions (role_id, feature_key, can_view, can_create, can_edit, can_delete, can_approve, can_confirm, can_export)
select r.id, 'childcare_operations', true, true, true, true, true, true, true
from roles r where r.code = 'system_admin';

insert into role_permissions (role_id, feature_key, can_view, can_create, can_edit, can_delete, can_approve, can_confirm, can_export)
select r.id, 'childcare_operations', true, true, true, false, true, true, true
from roles r where r.code in ('director', 'chief', 'office_manager');

insert into role_permissions (role_id, feature_key, can_view, can_create, can_edit, can_delete, can_approve, can_confirm, can_export)
select r.id, 'childcare_operations', true, true, true, false, false, false, false
from roles r where r.code = 'staff';
