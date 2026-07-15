-- 職員マスタCSV取込(20260714000020)対象の労働者名簿には「パート」雇用形態の職員が
-- 多数含まれるが、employment_typesマスタには「正社員」しか登録されていなかった。
-- CSV取込のemployment_type検証(名称完全一致)を通すため追加する。

insert into employment_types (name, sort_order, is_active)
values ('パート', 1, true)
on conflict do nothing;
