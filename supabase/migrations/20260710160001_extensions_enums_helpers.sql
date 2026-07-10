-- Ohana Works v1.0 スキーマ移行
-- 設計書 docs/design_v1.0.md 29章に基づき、既存Phase 1テーブル(本番データなし)は
-- 別途 DROP のうえ本マイグレーション群で再構築する想定。
--
-- 本ファイル: 拡張機能 / 共通ENUM型 / 共通トリガー関数

create extension if not exists "pgcrypto";

-- updated_at を自動更新する共通トリガー関数
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- 設計書13.5 シフト区分(コード化) ※「休日労働」等の曖昧な区分は使用しない
create type shift_type_code as enum (
  'normal_work',
  'holiday_substitute_saturday_work',
  'distributed_holiday_substitute_work',
  'statutory_holiday_work',
  'non_statutory_holiday_work',
  'event_work',
  'paid_leave',
  'absence',
  'company_holiday',
  'national_holiday',
  'year_end_new_year_holiday',
  'requires_admin_review'
);

create type shift_status as enum ('draft', 'confirmed');

-- 設計書6.2 労働時間制度
create type work_time_system_type as enum ('通常', '1ヶ月単位変形労働時間制');

create type salary_type as enum ('月給', '時給');

-- 設計書9.4 打刻種別
create type punch_type as enum ('clock_in', 'break_start', 'break_end', 'clock_out');
create type punch_source as enum ('qr', 'proxy');
create type qr_token_status as enum ('issued', 'used', 'expired');
create type device_status as enum ('enabled', 'disabled');

-- 設計書15章 申請種別
create type request_type as enum ('paid_leave', 'absence', 'tardiness_early_leave', 'info_change');
create type request_status as enum ('pending', 'approved', 'rejected', 'cancelled');
create type leave_usage_unit as enum ('day', 'half_day', 'hour');

-- 設計書17章 給与確定フロー
create type payroll_run_status as enum ('draft', 'confirmed', 'transferred');

-- 設計書22章 アラート状態(未処理/対応中/対応済み/対象外)
create type alert_status as enum ('未処理', '対応中', '対応済み', '対象外');

-- 設計書23章 災害モード回答
create type disaster_response_type as enum ('無事です', '出勤可能', '出勤不可', '連絡が必要', '被災しています');

-- 設計書4.3 施設稼働状態
create type office_status as enum ('稼働中', '廃止済み');

-- 設計書20.2 ファイル取込ステータス
create type file_import_status as enum ('processing', 'awaiting_review', 'applied', 'error');
