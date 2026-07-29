-- Phase 0.5(ステージング環境構築)で発覚した不具合の修正。
-- 122番(cron_dispatch_pending_notifications)がEdge FunctionのURLを
-- 本番プロジェクトのものとして直書きしており、他環境(ステージング等)へ
-- 同じマイグレーションを適用すると誤って本番URLを呼び出す構成になっていた。
-- URLもservice_role keyと同様にVaultへ移し、環境ごとに正しい値を設定する。
-- (122番のファイル自体は当時の実行記録として書き換えない。本マイグレーションで
-- 関数を差し替える)

create or replace function cron_dispatch_pending_notifications()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_service_key text;
  v_function_url text;
begin
  select decrypted_secret into v_service_key
  from vault.decrypted_secrets
  where name = 'dispatch_notifications_service_key';

  select decrypted_secret into v_function_url
  from vault.decrypted_secrets
  where name = 'dispatch_notifications_function_url';

  if v_service_key is null or v_function_url is null then
    raise warning 'dispatch_notifications_service_key/function_url is not set in vault; skipping dispatch';
    return;
  end if;

  perform net.http_post(
    url := v_function_url,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_service_key,
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
end;
$$;
