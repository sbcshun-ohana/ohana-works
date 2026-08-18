-- 241: 発達記録の機能フラグ(§12・段階導入。既定OFF・施設別ON)。
insert into feature_flags (feature_key, name, description, default_enabled) values
  ('development_records_enabled', '発達記録',
   '発達記録機能(達成申請・承認・マスター)の施設別有効化。既定OFF、試験施設からON。', false)
on conflict (feature_key) do nothing;

create or replace function is_development_records_enabled_for_office(p_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select is_feature_enabled_for_office('development_records_enabled', p_office_id);
$$;
grant execute on function is_development_records_enabled_for_office(uuid) to authenticated, service_role;

-- 動作確認用に大和オハナ保育園でONにする運用は feature_flag_office_overrides で行う
-- (管理者Webの「機能フラグ」ページ、または個別UPSERT)。本マイグレーションではdefault OFFのまま。
