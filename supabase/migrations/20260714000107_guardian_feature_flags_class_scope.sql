-- 開発計画(改訂版 2026-07-17) Phase 0: 機能フラグ基盤の拡張
-- 施設単位に加え「クラス単位」の段階公開に対応する(Ohana Family公開制御の前提)。
-- 既存の feature_flag_office_overrides / feature_flag_employee_overrides(職員ドメイン、
-- childcare_operations用)はそのまま維持し、保護者ドメイン専用の判定関数を新設する。

-- クラス単位のON/OFF override(施設単位overrideと同じ形)。
create table feature_flag_class_overrides (
  id uuid primary key default gen_random_uuid(),
  feature_key text not null references feature_flags(feature_key) on delete cascade,
  class_id uuid not null references childcare_classes(id) on delete cascade,
  enabled boolean not null,
  note text,
  updated_by uuid references employees(id),
  updated_at timestamptz not null default now(),
  unique (feature_key, class_id)
);

alter table feature_flag_class_overrides enable row level security;
create policy feature_flag_class_overrides_select_authenticated on feature_flag_class_overrides
  for select using (my_employee_id() is not null);
create policy feature_flag_class_overrides_write_system_admin on feature_flag_class_overrides
  for all using (is_system_admin()) with check (is_system_admin());

create trigger trg_audit_feature_flag_class_overrides
  after insert or update or delete on feature_flag_class_overrides
  for each row execute function log_event_change();

-- 保護者アプリ(Ohana Family)側で不足していたfeature_key。既存: guardian_app(マスタースイッチ)・
-- attendance_qr・family_daily_report・class_photos。
insert into feature_flags (feature_key, name, description, default_enabled) values
  ('guardian_notices', '保育園からのお知らせ', '園児ごとの個別お知らせを保護者アプリへ配信する機能', false),
  ('guardian_requests', '保護者からの申請・連絡', '欠席・遅刻・早退・お迎えの方の変更・その他連絡を保護者アプリから送信する機能', false),
  ('communication_book', '保育園からの連絡帳', '園連絡帳(本文)を保護者アプリへ配信する機能', false);

-- 保護者ドメイン専用の判定関数。優先順位: クラスoverride → 施設override → デフォルト → false。
-- guardian_app(マスタースイッチ)がOFFの施設では、他の全キーが強制的にfalseになる。
create or replace function is_guardian_feature_enabled(p_feature_key text, p_child_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_office_id uuid;
  v_class_id uuid;
begin
  select office_id into v_office_id from children where id = p_child_id;
  if v_office_id is null then
    return false;
  end if;

  if p_feature_key <> 'guardian_app' and not is_guardian_feature_enabled('guardian_app', p_child_id) then
    return false;
  end if;

  select cce.class_id into v_class_id
    from child_class_enrollments cce
    where cce.child_id = p_child_id and cce.effective_end_date is null
    limit 1;

  return coalesce(
    (select enabled from feature_flag_class_overrides where feature_key = p_feature_key and class_id = v_class_id),
    (select enabled from feature_flag_office_overrides where feature_key = p_feature_key and office_id = v_office_id),
    (select default_enabled from feature_flags where feature_key = p_feature_key),
    false
  );
end;
$$;

comment on function is_guardian_feature_enabled(text, uuid) is
  '保護者ドメイン専用のfeature_flag判定。職員側のis_childcare_enabled_for_office()とは独立(3ドメイン分離を維持)。';

-- parent_appから1回で全キーをまとめて取得するRPC。呼び出し元の保護者がp_child_idへの
-- アクセス権を持つことをguardian_has_child_access()で検証してから返す。
create or replace function fetch_guardian_feature_flags(p_child_id uuid)
returns table(feature_key text, enabled boolean)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not guardian_has_child_access(p_child_id) then
    raise exception 'not authorized';
  end if;

  return query
    select ff.feature_key, is_guardian_feature_enabled(ff.feature_key, p_child_id)
    from feature_flags ff
    where ff.feature_key in (
      'guardian_app', 'guardian_notices', 'guardian_requests',
      'family_daily_report', 'communication_book', 'class_photos', 'attendance_qr'
    );
end;
$$;
