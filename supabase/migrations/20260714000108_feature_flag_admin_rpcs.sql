-- 開発計画(改訂版 2026-07-17) Phase 0: feature_flags管理UI(admin_web /feature-flags)向けRPC。
-- 既存の招待発行・承認系RPCと同じ慣習(admin_webからのテーブル直接upsertではなくRPC経由)に揃える。
-- 書き込みは is_system_admin() のみ許可(feature_flag_*_overrides のRLS write policyと同じ条件)。

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
  if not is_system_admin() then
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
  if not is_system_admin() then
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
