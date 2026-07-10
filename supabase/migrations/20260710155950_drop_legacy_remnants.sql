-- 29章: 既存Phase 1スキーマの残存オブジェクト破棄(追補)
--
-- 20260710155900で15テーブルをDROPした後、db push実行時に発覚した残存オブジェクト。
-- ユーザーへのヒアリングにない付随オブジェクト(旧notices等が使用していたenum型、
-- および何らかのRLS自動化トリガー関数)がテーブルDROP後も孤立して残っていたため、
-- 確認のうえ削除する。20260710155900は既にリモートへ適用済みのため、
-- 本ファイルを独立したマイグレーションとして追加する。
--
-- 対象: type notice_category / role_type / shift_change_status,
--       function rls_auto_enable

drop function if exists rls_auto_enable cascade;
drop type if exists notice_category cascade;
drop type if exists role_type cascade;
drop type if exists shift_change_status cascade;
