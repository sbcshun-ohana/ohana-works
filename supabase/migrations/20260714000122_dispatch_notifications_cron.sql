-- P0: イベント駆動プッシュ通知の自動化 — dispatch-pending-notifications Edge Functionの定期実行。
--
-- pg_cronからEdge FunctionをHTTPで呼ぶにはpg_net拡張が必要(本プロジェクトでは今回が初導入。
-- 既存の月次バッチ(20260714000018)はDB内plpgsql関数呼び出しのみでpg_netは不要だった)。
--
-- service_role keyはSupabase Vaultに保管し、このマイグレーションファイル自体には値を含めない
-- (gitで管理されるファイルに秘匿情報を書かないため)。Vaultへの実際の値投入は本番DBに対して
-- 直接(マイグレーション外で)一度だけ以下を実行して行う:
--   select vault.create_secret('<service_role key>', 'dispatch_notifications_service_key');
-- 未設定の間はcron_dispatch_pending_notifications()が警告を出して何もせず終了する(安全側)。

create extension if not exists pg_net;

create or replace function cron_dispatch_pending_notifications()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_service_key text;
begin
  select decrypted_secret into v_service_key
  from vault.decrypted_secrets
  where name = 'dispatch_notifications_service_key';

  if v_service_key is null then
    raise warning 'dispatch_notifications_service_key is not set in vault; skipping dispatch';
    return;
  end if;

  perform net.http_post(
    url := 'https://wdsziqxvmhwbdyfeiame.supabase.co/functions/v1/dispatch-pending-notifications',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_service_key,
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
end;
$$;

-- 毎分実行。notifications(outbox)は業務RPC側で即座にpendingとして積まれるため、
-- 職員が体感する通知の遅延を抑えるには短い間隔が望ましい。
select cron.schedule(
  'dispatch_pending_notifications',
  '* * * * *',
  $$select cron_dispatch_pending_notifications();$$
);
