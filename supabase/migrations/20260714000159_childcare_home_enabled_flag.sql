-- ホーム画面(設計指示書 2026-08-03)Phase 1: Ohana Kids ホーム画面の機能フラグ。
-- default OFF。OFF時は従来の保育業務メニューを維持(コード側も安全側に倒れる)。
-- staging は試験施設(BABY MAHALO / Mahalo Station)から override でON、本番はリリースまでOFF。
insert into feature_flags (feature_key, name, description, default_enabled) values
  ('childcare_home_enabled', 'Ohana Kids ホーム画面',
   'Ohana Kids(保育業務iPad)のホーム画面7区分。OFF時は従来メニュー', false)
on conflict (feature_key) do nothing;

-- 施設単位の有効判定(既存の汎用 is_feature_enabled_for_office を呼ぶ薄いラッパー。
-- is_child_internal_notes_enabled_for_office と同じ方式でロジック複製なし)。
create or replace function is_childcare_home_enabled_for_office(p_office_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select is_feature_enabled_for_office('childcare_home_enabled', p_office_id);
$$;
