-- 29章: 既存Phase 1スキーマの破棄
--
-- 対象プロジェクト(wdsziqxvmhwbdyfeiame)には以下15テーブルが存在するが、
-- ユーザー確認の結果、本番データは投入されていないため、v1.0スキーマで
-- 全面的に再構築する。CASCADEにより従属する制約・インデックス・トリガーも
-- 併せて削除する。
--
-- 対象: offices, employees, employee_contacts, emergency_contacts,
--       employee_office_assignments, employee_role_histories, roles,
--       employee_permissions, notices, notice_attachments, notice_recipients,
--       shift_imports, shifts, shift_change_requests, shift_change_approvals
--
-- 注記: notices/notice_attachments/notice_recipients は本マイグレーション群でも
-- 同名テーブルとして8章仕様に基づき再構築する(お知らせ機能自体は廃止しない)。

drop table if exists notice_recipients cascade;
drop table if exists notice_attachments cascade;
drop table if exists notices cascade;
drop table if exists shift_change_approvals cascade;
drop table if exists shift_change_requests cascade;
drop table if exists shifts cascade;
drop table if exists shift_imports cascade;
drop table if exists employee_permissions cascade;
drop table if exists employee_role_histories cascade;
drop table if exists roles cascade;
drop table if exists employee_office_assignments cascade;
drop table if exists emergency_contacts cascade;
drop table if exists employee_contacts cascade;
drop table if exists employees cascade;
drop table if exists offices cascade;
