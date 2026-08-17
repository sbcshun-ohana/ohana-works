-- 219: 機能フラグ管理を統括園長へ開放(俊指示 2026-08-17)。
-- 書き込みRPC 2本のゲートを is_system_admin() → is_executive_director_or_admin()(205新設=system_admin+executive_director)へ変更。
-- 読み取りは既に authenticated 全員可(055のselectポリシー)のため変更なし。
-- テーブル直書きのRLS write ポリシー(system_adminのみ)は据え置き=書き込み経路はRPCに一本化されたまま。
-- ※適用前照合: pg_get_functiondef で 108 版と一致することを確認済みの前提。冪等: create or replace のみ。

create or replace function set_guardian_feature_office_override(
  p_feature_key text,
  p_office_id uuid,
  p_enabled boolean,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_executive_director_or_admin() then
    raise exception 'not authorized';
  end if;

  insert into feature_flag_office_overrides (feature_key, office_id, enabled, note, updated_by, updated_at)
  values (p_feature_key, p_office_id, p_enabled, p_note, my_employee_id(), now())
  on conflict (feature_key, office_id) do update
    set enabled = excluded.enabled,
        note = excluded.note,
        updated_by = excluded.updated_by,
        updated_at = now();
end;
$$;

create or replace function set_guardian_feature_class_override(
  p_feature_key text,
  p_class_id uuid,
  p_enabled boolean,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_executive_director_or_admin() then
    raise exception 'not authorized';
  end if;

  insert into feature_flag_class_overrides (feature_key, class_id, enabled, note, updated_by, updated_at)
  values (p_feature_key, p_class_id, p_enabled, p_note, my_employee_id(), now())
  on conflict (feature_key, class_id) do update
    set enabled = excluded.enabled,
        note = excluded.note,
        updated_by = excluded.updated_by,
        updated_at = now();
end;
$$;
