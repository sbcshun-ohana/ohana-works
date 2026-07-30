-- 新機能「園内記録」Phase B。
-- 参照: docs/Ohana_Works_園内記録機能_実装設計書_v2_2026-07-30.md §4〜§6、
--       docs/園内記録_PhaseA調査報告_2026-07-30.md(承認済み)。
--
-- 権限判定関数(2026-07-30 ユーザー指示: 既存の判定関数を呼び出す薄いラッパーとし、
-- 判定ロジック自体を複製しない):
--   - is_child_internal_notes_chief(office_id) = is_support_childcare_chief(office_id) を
--     そのまま呼ぶ薄いラッパー(主任・管理者・園長=自施設、施設長・system_admin=複数施設/全施設
--     を同じ役職対応表で正しく判定できるため、Phase3の関数をそのまま再利用する)
--   - is_child_internal_notes_enabled_for_office(office_id) は、既存の
--     is_childcare_enabled_for_office/is_support_childcare_enabled_for_office で
--     3回重複していたcoalesceロジックを共通化する is_feature_enabled_for_office(key, office_id)
--     を新設し、それを呼ぶ薄いラッパーとする(既存2関数は無関係な既存機能のため触れない)
--
-- log_sensitive_access の呼び方(Phase A確認済み・fetch_payroll_transfer_recipients方式):
--   対象が職員でないため p_target_employee_id は null、p_target_data に文脈を文字列で渡す。
--
-- 機能フラグの施設別有効化(大和オハナ保育園のみステージングON)は、既存の
-- scripts/seed_staging.ts が feature_flags 全件を対象に施設別ONを行う設計のため、
-- 本マイグレーションでは行わない(全フラグ共通のexists()ガード付きロジックを再利用し、
-- 本番へ誤って有効化データが混入することを避ける)。適用後に seed_staging.ts を
-- 再実行することで、大和オハナ保育園に対して自動的に有効化される。

-- ============================================================
-- 1) 共通ヘルパー: 機能フラグの3段階coalesce判定(既存2関数の重複ロジックを一本化)
-- ============================================================
create or replace function is_feature_enabled_for_office(p_feature_key text, p_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(
    (select enabled from feature_flag_employee_overrides
     where feature_key = p_feature_key and employee_id = my_employee_id()),
    (select enabled from feature_flag_office_overrides
     where feature_key = p_feature_key and office_id = p_office_id),
    (select default_enabled from feature_flags where feature_key = p_feature_key),
    false
  );
$$;

-- ============================================================
-- 2) 園内記録専用の薄いラッパー(既存判定関数を呼ぶのみ、ロジック複製なし)
-- ============================================================
create or replace function is_child_internal_notes_chief(target_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select is_support_childcare_chief(target_office_id);
$$;

create or replace function is_child_internal_notes_enabled_for_office(p_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select is_feature_enabled_for_office('child_internal_notes_enabled', p_office_id);
$$;

-- ============================================================
-- 3) テーブル
-- ============================================================
create table child_internal_notes (
  id                uuid primary key default gen_random_uuid(),
  child_id          uuid not null references children(id),
  office_id         uuid not null references offices(id),
  note_date         date not null,
  category          text not null check (category in (
                      'handover',        -- 申し送り
                      'observation',     -- 個人日誌
                      'guardian_contact',-- 保護者との面談記録
                      'external_agency', -- 療育等との連携記録
                      'other'            -- その他
                    )),
  body              text not null check (length(body) > 0),
  ai_excluded       boolean not null default false,
  author_employee_id uuid not null references employees(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);

create index idx_cin_child_date  on child_internal_notes (child_id, note_date desc) where deleted_at is null;
create index idx_cin_office_date on child_internal_notes (office_id, note_date desc) where deleted_at is null;
create index idx_cin_child_cat   on child_internal_notes (child_id, category, note_date desc) where deleted_at is null;

create trigger trg_child_internal_notes_updated_at before update on child_internal_notes
  for each row execute function set_updated_at();
create trigger trg_audit_child_internal_notes
  after insert or update or delete on child_internal_notes
  for each row execute function log_event_change();

-- ============================================================
-- 4) RLS: 保護者ポリシーは1本も作らない(デフォルト拒否)。職員ドメインもSELECTのみ、
--    書き込みは全てRPC経由(office_id解決・24時間判定をバイパスさせないため)
-- ============================================================
alter table child_internal_notes enable row level security;
create policy child_internal_notes_select on child_internal_notes
  for select using (has_childcare_office_access(office_id) or is_system_admin());

-- ============================================================
-- 5) 機能フラグの登録(グローバルキーのみ。施設別ONはseed_staging.ts再実行で行う)
-- ============================================================
insert into feature_flags (feature_key, name, description, default_enabled) values
  ('child_internal_notes_enabled', '園内記録', '職員専用の園内記録機能の有効化', false);

-- ============================================================
-- RPC: 作成(office_idはchild_class_enrollmentsの有効レコードから解決し、呼び出し側に
-- 渡させない。転園後も書き込み時点の施設が保持される)
-- ============================================================
create or replace function create_child_internal_note(
  p_child_id uuid, p_note_date date, p_category text, p_body text, p_ai_excluded boolean
)
returns child_internal_notes
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_row child_internal_notes;
begin
  select cc.office_id into v_office_id
  from child_class_enrollments cce
  join childcare_classes cc on cc.id = cce.class_id
  where cce.child_id = p_child_id and cce.effective_end_date is null
  limit 1;
  if v_office_id is null then
    raise exception 'child not found or not currently enrolled';
  end if;
  if not is_child_internal_notes_enabled_for_office(v_office_id) then
    raise exception 'feature not enabled for this office';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;
  if p_category not in ('handover', 'observation', 'guardian_contact', 'external_agency', 'other') then
    raise exception 'invalid category';
  end if;

  insert into child_internal_notes (child_id, office_id, note_date, category, body, ai_excluded, author_employee_id)
  values (p_child_id, v_office_id, p_note_date, p_category, p_body, coalesce(p_ai_excluded, false), my_employee_id())
  returning * into v_row;

  return v_row;
end;
$$;

-- ============================================================
-- RPC: 編集(自分の記録は24時間以内、主任以上は自施設の全記録)
-- ============================================================
create or replace function update_child_internal_note(
  p_note_id uuid, p_body text, p_category text, p_ai_excluded boolean, p_note_date date
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_author_id uuid;
  v_created_at timestamptz;
begin
  select office_id, author_employee_id, created_at into v_office_id, v_author_id, v_created_at
  from child_internal_notes where id = p_note_id and deleted_at is null;
  if v_office_id is null then
    raise exception 'note not found';
  end if;
  if p_category not in ('handover', 'observation', 'guardian_contact', 'external_agency', 'other') then
    raise exception 'invalid category';
  end if;

  if not (
    is_child_internal_notes_chief(v_office_id)
    or (v_author_id = my_employee_id() and v_created_at >= now() - interval '24 hours')
  ) then
    raise exception 'not authorized';
  end if;

  update child_internal_notes set
    body = p_body,
    category = p_category,
    ai_excluded = coalesce(p_ai_excluded, false),
    note_date = p_note_date
  where id = p_note_id;
end;
$$;

-- ============================================================
-- RPC: 論理削除(物理DELETEはしない。編集と同じ権限判定)
-- ============================================================
create or replace function soft_delete_child_internal_note(p_note_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_author_id uuid;
  v_created_at timestamptz;
begin
  select office_id, author_employee_id, created_at into v_office_id, v_author_id, v_created_at
  from child_internal_notes where id = p_note_id and deleted_at is null;
  if v_office_id is null then
    raise exception 'note not found';
  end if;

  if not (
    is_child_internal_notes_chief(v_office_id)
    or (v_author_id = my_employee_id() and v_created_at >= now() - interval '24 hours')
  ) then
    raise exception 'not authorized';
  end if;

  update child_internal_notes set deleted_at = now() where id = p_note_id;
end;
$$;

-- ============================================================
-- RPC: 閲覧(log_sensitive_access必須)
-- ============================================================
create or replace function fetch_child_internal_notes(
  p_child_id uuid, p_from date default null, p_to date default null,
  p_categories text[] default null, p_limit int default 50, p_offset int default 0
)
returns setof child_internal_notes
language plpgsql stable security definer set search_path = public
as $$
declare
  v_office_id uuid;
begin
  select cc.office_id into v_office_id
  from child_class_enrollments cce
  join childcare_classes cc on cc.id = cce.class_id
  where cce.child_id = p_child_id and cce.effective_end_date is null
  limit 1;
  if v_office_id is null then
    raise exception 'child not found or not currently enrolled';
  end if;
  if not is_child_internal_notes_enabled_for_office(v_office_id) then
    raise exception 'feature not enabled for this office';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  perform log_sensitive_access(
    '園内記録閲覧(fetch_child_internal_notes)', null, format('child_id=%s', p_child_id)
  );

  return query
  select n.*
  from child_internal_notes n
  where n.child_id = p_child_id
    and n.deleted_at is null
    and (p_from is null or n.note_date >= p_from)
    and (p_to is null or n.note_date <= p_to)
    and (p_categories is null or n.category = any (p_categories))
  order by n.note_date desc, n.created_at desc
  limit p_limit offset p_offset;
end;
$$;

-- ============================================================
-- RPC: AI参照用(判定ロジックはこの関数だけに存在させる。将来のAI下書き実装はこの
-- 関数のみを使うこと。児童氏名は返さない=id・本文のみ)
-- ============================================================
create or replace function fetch_child_internal_notes_for_ai(p_child_id uuid, p_from date, p_to date)
returns table (id uuid, body text)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_office_id uuid;
begin
  select cc.office_id into v_office_id
  from child_class_enrollments cce
  join childcare_classes cc on cc.id = cce.class_id
  where cce.child_id = p_child_id and cce.effective_end_date is null
  limit 1;
  if v_office_id is null then
    raise exception 'child not found or not currently enrolled';
  end if;
  if not is_child_internal_notes_enabled_for_office(v_office_id) then
    raise exception 'feature not enabled for this office';
  end if;
  if not is_child_internal_notes_chief(v_office_id) then
    raise exception 'not authorized';
  end if;
  if p_from is null or p_to is null then
    raise exception 'p_from and p_to are required';
  end if;

  perform log_sensitive_access(
    '園内記録AI参照(fetch_child_internal_notes_for_ai)', null,
    format('child_id=%s, from=%s, to=%s', p_child_id, p_from, p_to)
  );

  return query
  select n.id, n.body
  from child_internal_notes n
  where n.child_id = p_child_id
    and n.category in ('handover', 'observation')
    and n.ai_excluded = false
    and n.deleted_at is null
    and n.note_date between p_from and p_to
  order by n.note_date;
end;
$$;
