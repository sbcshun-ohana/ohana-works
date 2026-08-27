-- 377: 一時外出の理由「その他」の表示フラグ(本案§4「その他は運用開始時フラグで非表示・療育+健診のみ」)。
--   既定OFF=「その他」を出さない(療育+健診のみ)。施設別にONで「その他」も選べる。
--   既存フラグと同一パターン。UIはこのフラグで理由チップの表示を切替える。
insert into feature_flags (feature_key, name, description, default_enabled) values
  ('outing_reason_other_enabled', '一時外出「その他」理由',
   '一時外出の理由に「その他」を表示する。既定OFF=療育+健診のみ。', false)
on conflict (feature_key) do nothing;

create or replace function is_outing_reason_other_enabled_for_office(p_office_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select is_feature_enabled_for_office('outing_reason_other_enabled', p_office_id);
$$;
grant execute on function is_outing_reason_other_enabled_for_office(uuid) to authenticated, service_role;
