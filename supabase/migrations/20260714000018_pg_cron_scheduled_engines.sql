-- Supabase Scheduled Function(pg_cron)による有給自動付与・月次勤怠集計の自動実行。
--
-- 【タイムゾーンの扱い】
-- DBセッションのタイムゾーンはUTC固定(Supabase標準)。pg_cronのスケジュール式は
-- UTCで評価される。JSTはUTC+9で夏時間が無い固定オフセットのため、
-- cron.timezone GUC(Supabaseの管理環境での永続性が不確実)には依存せず、
-- 「UTC 17:00/18:00 = JST 翌日02:00/03:00」への変換を直接スケジュール式に
-- 組み込む方式を採る。
--
-- 【月末日(28〜31日で変動)の扱い】
-- 標準cron構文には「月末日」を表す特殊記法が無いため、UTC 28〜31日の毎日
-- 同時刻に起動し、ラッパー関数内で「当日(UTC)が月末日か」を判定して
-- 月末日以外は何もしない(冪等な自己ガード)方式にする。これにより28〜31日
-- どの日が月末になる月でも正確に1回だけ実行される。
--
-- UTC day (last day of month) 17:00 = JST (day+1, i.e. 翌月1日) 02:00
-- UTC day (last day of month) 18:00 = JST (day+1, i.e. 翌月1日) 03:00

create extension if not exists pg_cron;

-- 有給自動付与: 対象日はJST基準の実行当日(=UTC月末日の翌日=翌月1日)。
create or replace function cron_run_paid_leave_auto_grant()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target_date date;
begin
  if extract(day from (current_date + 1)) <> 1 then
    return; -- UTC基準で当日が月末日でなければ何もしない
  end if;
  v_target_date := current_date + 1; -- JST基準の当日(翌月1日)
  perform run_paid_leave_auto_grant(v_target_date);
end;
$$;

-- 月次勤怠集計: 対象月はJST基準の前月(=UTC月末日が属する月そのもの)。
create or replace function cron_run_attendance_summary()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target_month date;
begin
  if extract(day from (current_date + 1)) <> 1 then
    return;
  end if;
  v_target_month := date_trunc('month', current_date)::date; -- JST基準の前月
  perform run_attendance_summary(v_target_month);
end;
$$;

-- 無人実行(auth.uid()が無いコンテキスト)を許可する既存の認可方針
-- (run_paid_leave_auto_grant/run_attendance_summary、20260714000006/20260714000007)を
-- そのまま利用する。pg_cronジョブはSupabase Auth JWTコンテキストを持たないため
-- auth.uid() is null となり、無人実行として通過する。

select cron.schedule(
  'monthly_paid_leave_auto_grant', -- 毎月末日 UTC17:00(=JST 翌月1日02:00)
  '0 17 28-31 * *',
  $$select cron_run_paid_leave_auto_grant();$$
);

select cron.schedule(
  'monthly_attendance_summary', -- 毎月末日 UTC18:00(=JST 翌月1日03:00)
  '0 18 28-31 * *',
  $$select cron_run_attendance_summary();$$
);
