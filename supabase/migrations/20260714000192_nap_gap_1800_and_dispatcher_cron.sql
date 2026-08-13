-- 192: (1) 午睡漏れ検出cronを 15:00 JST → 閉園前の日次まとめ 18:00 JST に付替
--      (2) dispatcher毎分cron(dispatch_pending_notifications)がDB側に未登録の環境向けに冪等登録
--
-- C4調査(2026-08-07)の確定: cron登録・15:00実行・nap_check_gap通知3件生成・EMP-02宛あり=検出側は正常。
--   未達の原因は配信側で、いずれもDB外の設定:
--     ・vault の dispatch_notifications_service_key / dispatch_notifications_function_url が未設定
--       → cron_dispatch_pending_notifications() が warning を出して skip → 全通知 pending 滞留。
--     ・Edge Function secret FCM_SERVICE_ACCOUNT_JSON が未設定 → FCM 送信不可。
--     ・STG-EMP-02 の push_device_tokens が未登録 → 送信先なし。
--   → これらは本migrationでは扱わない(DB外。リリース手順/別手順に明記)。
--
-- 本migrationはDB側の変更のみ:
--   (1) 検出関数 cron_detect_nap_check_gaps は時刻非依存(上限=min(起床,now))のため本体不変。
--       schedule だけ '0 6 * * *' → '0 9 * * *'(UTC=18:00 JST)へ付替。通知対象(manages_childcare)・
--       文言・二重ガード(office×date=1日1回)は不変。18時実行で15時以降の午睡も自然にカバー。
--   (2) 122/139 で登録済みの dispatcher 毎分cron が、当該環境に未登録の場合のみ冪等登録
--       (122/139 適用済み環境では no-op)。cron_dispatch_pending_notifications 関数は 139 のものを使用。
-- 依存: 184〜191 のいずれのオブジェクトにも依存しない。
--
-- 【ドル引用の入れ子衝突を回避】cron.schedule のコマンド文字列は単引用符で渡す。
--   do $$ ... $$ ブロック内で command を $$...$$ にすると、外側の $$ が内側の $$ で閉じてしまい
--   42601 syntax error になる(初版の失敗原因)。command に単引用符が含まれないため単引用符で問題ない。
-- 冪等: 頭から再実行して差し支えない(unschedule は存在時のみ、登録は未登録時のみ)。

-- (1) 午睡漏れ検出cronを 18:00 JST へ付替
do $$
begin
  if exists (select 1 from cron.job where jobname = 'detect_nap_check_gaps') then
    perform cron.unschedule('detect_nap_check_gaps');
  end if;
end $$;

select cron.schedule(
  'detect_nap_check_gaps',
  '0 9 * * *',   -- 18:00 JST(= 09:00 UTC)。閉園前の日次まとめ。
  'select cron_detect_nap_check_gaps();'
);

-- (2) dispatcher毎分cronがDB側に未登録なら登録(122/139適用済みなら no-op)
do $$
begin
  if not exists (select 1 from cron.job where jobname = 'dispatch_pending_notifications') then
    perform cron.schedule(
      'dispatch_pending_notifications',
      '* * * * *',
      'select cron_dispatch_pending_notifications();'
    );
  end if;
end $$;
