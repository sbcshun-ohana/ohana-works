-- 療育外出・戻り登録 §2: テーブル+RLS+機能フラグ+外出中導出ヘルパー。
-- 目的=外部療育事業者との保育・保護責任の線引き記録(正確な時刻・改ざん耐性優先)。
-- 保護者からは一切見えない(保護者向けRLSポリシーを作らない)。書き込みはEF/RPC経由。
-- 権限写像(2026-08-04 俊確定): 事業者マスタ登録/編集=統括園長以上、
-- 対象児設定・QR発行/revoke・イベント修正=主任以上(manages_childcare、後続173で適用)。

create extension if not exists btree_gist;

-- 機能フラグ(既定OFF)。対象園児が実在する施設のみON。
insert into feature_flags (feature_key, name, description, default_enabled) values
  ('therapy_outing_enabled', '療育外出・戻り登録',
   '療育併用園児の一時外出/戻りをキオスク固定QRで記録。OFF時はキオスク読み分け・デイリー表示・admin導線を出さない', false)
on conflict (feature_key) do nothing;

create or replace function is_therapy_outing_enabled_for_office(p_office_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select is_feature_enabled_for_office('therapy_outing_enabled', p_office_id); $$;

-- 事業者マスタ(グローバル。現状1事業者・複数事業者に備える)
create table therapy_providers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- 対象園児設定(適用期間つき)。同一園児×事業者の期間重複を EXCLUDE で禁止。
create table child_therapy_settings (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  provider_id uuid not null references therapy_providers(id),
  start_date date not null,
  end_date date,   -- null=無期限
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  constraint child_therapy_settings_date_order check (end_date is null or end_date >= start_date),
  exclude using gist (
    child_id with =,
    provider_id with =,
    daterange(start_date, coalesce(end_date, 'infinity'::date), '[]') with &&
  )
);

-- 固定QR。token は保存せず token_hash のみ(発行時に生tokenを1回返しPDF描画)。紛失時 revoke→再発行。
create table therapy_outing_qr_codes (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  provider_id uuid not null references therapy_providers(id),
  token_hash text not null unique,
  revoked_at timestamptz,
  issued_by uuid references employees(id),
  issued_at timestamptz not null default now()
);

-- 打刻記録。event_type=out/return、source=kiosk_qr/staff_manual。手動修正は上書きせず訂正履歴で辿る。
create table therapy_outing_events (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  provider_id uuid not null references therapy_providers(id),
  event_type text not null check (event_type in ('out', 'return')),
  occurred_at timestamptz not null default now(),
  source text not null check (source in ('kiosk_qr', 'staff_manual')),
  qr_code_id uuid references therapy_outing_qr_codes(id),
  recorded_by uuid references employees(id),
  correction_note text,
  created_at timestamptz not null default now()
);
create index idx_therapy_outing_events_child on therapy_outing_events (child_id, occurred_at);

-- RLS(SELECTのみ。保護者ポリシーは作らない=保護者不可視)
alter table therapy_providers enable row level security;
create policy therapy_providers_select on therapy_providers
  for select using (my_employee_id() is not null);

alter table child_therapy_settings enable row level security;
create policy child_therapy_settings_select on child_therapy_settings
  for select using (
    exists (select 1 from children c where c.id = child_id and has_childcare_office_access(c.office_id))
  );

alter table therapy_outing_qr_codes enable row level security;
create policy therapy_outing_qr_codes_select on therapy_outing_qr_codes
  for select using (
    exists (select 1 from children c where c.id = child_id and has_childcare_office_access(c.office_id))
  );

alter table therapy_outing_events enable row level security;
create policy therapy_outing_events_select on therapy_outing_events
  for select using (
    exists (select 1 from children c where c.id = child_id and has_childcare_office_access(c.office_id))
  );

-- 監査トリガ(4表)
do $$
declare t text;
begin
  foreach t in array array['therapy_providers','child_therapy_settings','therapy_outing_qr_codes','therapy_outing_events']
  loop
    execute format(
      'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();', t);
  end loop;
end $$;

-- 外出中導出: 当日(JST)の最終イベントが out なら外出中。board/サマリー/キオスクで共有。
create or replace function is_child_on_therapy_outing(p_child_id uuid, p_business_date date)
returns boolean language sql stable security definer set search_path = public
as $$
  select coalesce((
    select e.event_type = 'out'
    from therapy_outing_events e
    where e.child_id = p_child_id
      and (e.occurred_at at time zone 'Asia/Tokyo')::date = p_business_date
    order by e.occurred_at desc
    limit 1
  ), false);
$$;
