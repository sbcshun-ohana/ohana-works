-- 保育業務 Phase1: 個別お知らせ候補マスタ
-- 着替え補充・おむつ補充・鼻水・咳等(設計書§10.3)を園ごとに編集可能なマスタとして持つ。
-- 正式一覧は別途決定のため、初期データとして指示書に明記された項目のみ投入する
-- (残りの項目は決定次第、管理者がseed_individual_notice_masters()または管理画面から追加する)。

create table individual_notice_masters (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id),
  code text not null,
  label text not null,
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (office_id, code)
);
create trigger trg_individual_notice_masters_updated_at before update on individual_notice_masters
  for each row execute function set_updated_at();

alter table individual_notice_masters enable row level security;
create policy individual_notice_masters_select_scoped on individual_notice_masters
  for select using (has_childcare_office_access(office_id));
create policy individual_notice_masters_write_managers on individual_notice_masters
  for all using (manages_childcare(office_id)) with check (manages_childcare(office_id));

do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'individual_notice_masters'
  );
end $$;

-- 施設ごとの初期データ投入(機能フラグ有効化時に管理者が施設単位で呼び出す想定。
-- 全施設へ自動投入はしない)。
create or replace function seed_individual_notice_masters(p_office_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not manages_childcare(p_office_id) then
    raise exception 'not authorized';
  end if;

  insert into individual_notice_masters (office_id, code, label, sort_order)
  values
    (p_office_id, 'clothes_change', '着替え補充', 10),
    (p_office_id, 'diaper_restock', 'おむつ補充', 20),
    (p_office_id, 'runny_nose', '鼻水', 30),
    (p_office_id, 'cough', '咳', 40)
  on conflict (office_id, code) do nothing;
end;
$$;
