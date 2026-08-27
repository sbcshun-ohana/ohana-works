-- 376: 登降園管理の機能フラグ(本案§8 / §0「機能フラグ既定OFF・施設別ON」)。
--   既存フラグ(241/247/254)と同一パターン。feature_flags 登録 + is_<feature>_enabled_for_office ラッパ。
--   既定OFF。ただし登降園管理は既に稼働中(ナビ表示済)のため、既存の可視状態を維持するよう
--   現存する全施設に override=ON を付与(grandfather)。以後の新規施設は既定OFFで、機能フラグ画面から施設別にON。

insert into feature_flags (feature_key, name, description, default_enabled) values
  ('attendance_mgmt_enabled', '登降園管理',
   '登降園の実績管理・要確認・休園日カレンダー・出席簿(施設別)。既定OFF・施設別ON。', false)
on conflict (feature_key) do nothing;

-- 既存施設は継続表示(grandfather)。新規施設は default_enabled=false に従う。
insert into feature_flag_office_overrides (feature_key, office_id, enabled)
select 'attendance_mgmt_enabled', o.id, true from offices o
on conflict (feature_key, office_id) do nothing;

-- 施設で登降園管理が有効か(既存 is_*_enabled_for_office と同型のラッパ)。
create or replace function is_attendance_mgmt_enabled_for_office(p_office_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select is_feature_enabled_for_office('attendance_mgmt_enabled', p_office_id);
$$;
grant execute on function is_attendance_mgmt_enabled_for_office(uuid) to authenticated, service_role;
