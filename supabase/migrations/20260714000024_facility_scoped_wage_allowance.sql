-- 施設別給与対応(1/3): wage_masters・employee_allowancesに施設(office_id)を持たせる。
--
-- 兼務職員(現時点で3名、いずれも月給。今後も増える見込み)は施設ごとに異なる
-- 基本給・手当・交通費が発生し、それらを合算したものが総支給額になる。これは
-- 特定職員向けの例外ではなく給与計算全体の恒久的な設計方針とする(3名専用の
-- 特別スキーマ・特別処理は一切設けない。単一施設の職員は「施設が1件だけの
-- ケース」として同じ構造の上で扱われる)。
--
-- commute_masters(交通費)は既にoffice_idを持つが、給与計算エンジンは
-- home_office_id一致の1件のみを参照していた(20260714000025で修正)。
--
-- 既存のwage_masters(52件、CSV取込由来・金額はすべて0)・employee_allowances
-- (0件)は施設情報を持たないため、employees.home_office_idからバックフィルする。
-- これにより単一施設職員(大多数)は従来通りの状態を維持する。兼務職員の
-- 追加施設分は本マイグレーションでは分割せず、20260714000026で追加するUI/RPC
-- 経由で管理者が個別登録する(バックフィルで金額の按分を推測しない)。

alter table wage_masters add column office_id uuid references offices(id);
update wage_masters w set office_id = e.home_office_id
from employees e where w.employee_id = e.id and w.office_id is null;
alter table wage_masters alter column office_id set not null;

drop index if exists idx_wage_masters_employee;
create index idx_wage_masters_employee_office on wage_masters(employee_id, office_id);

alter table employee_allowances add column office_id uuid references offices(id);
update employee_allowances ea set office_id = e.home_office_id
from employees e where ea.employee_id = e.id and ea.office_id is null;
alter table employee_allowances alter column office_id set not null;

drop index if exists idx_employee_allowances_employee;
create index idx_employee_allowances_employee_office on employee_allowances(employee_id, office_id);
