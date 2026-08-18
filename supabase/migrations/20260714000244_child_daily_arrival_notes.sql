-- 244: 登園メモ(職員内部・当日状況把握用)。俊指示 2026-08-19。
-- 位置づけ: 保護者非公開の職員内部メモ。受け入れ時の口頭連絡等を素早く記録し、
-- デイリーボードで当日の各園児分を一覧・インライン編集する。
-- 保護者向け連絡帳には反映しない/AI連絡帳生成の入力にもしない(family_daily_reportsとは別物)。
-- 園児×日で1件(upsert・空文字で削除)。閲覧=全職員(所属施設)、書込=RPC経由のみ。

create table child_daily_arrival_notes (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  office_id uuid not null references offices(id),
  business_date date not null,
  body text not null check (length(body) > 0),
  author_employee_id uuid not null references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (child_id, business_date)
);
create index idx_arrival_notes_office_date on child_daily_arrival_notes(office_id, business_date);
create trigger trg_arrival_notes_updated_at before update on child_daily_arrival_notes
  for each row execute function set_updated_at();
comment on table child_daily_arrival_notes is
  '登園メモ(244)。職員内部・保護者非公開・AI非参照。園児×日1件。デイリーボードで一覧/インライン編集。';
alter table child_daily_arrival_notes enable row level security;
create policy arrival_notes_select on child_daily_arrival_notes
  for select using (has_childcare_office_access(office_id));

-- 監査
do $$
begin
  execute format('create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();', 'child_daily_arrival_notes');
end $$;

-- ─────────────────────────────────────────────────────────────
-- 保存(upsert)。本文が空なら削除(セルを空にした=メモ消去)。書込=所属施設の職員。
create or replace function upsert_child_arrival_note(
  p_child_id uuid, p_business_date date, p_body text
) returns void
language plpgsql security definer set search_path = public
as $$
declare v_office uuid; v_body text;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;

  v_body := nullif(btrim(coalesce(p_body, '')), '');
  if v_body is null then
    delete from child_daily_arrival_notes where child_id = p_child_id and business_date = p_business_date;
    return;
  end if;

  insert into child_daily_arrival_notes (child_id, office_id, business_date, body, author_employee_id)
  values (p_child_id, v_office, p_business_date, v_body, my_employee_id())
  on conflict (child_id, business_date) do update set
    body = excluded.body,
    author_employee_id = excluded.author_employee_id,
    updated_at = now();
end $$;
grant execute on function upsert_child_arrival_note(uuid, date, text) to authenticated, service_role;

-- 施設×日の登園メモ一覧(デイリーボード用)。
create or replace function fetch_arrival_notes_for_office(
  p_office_id uuid, p_business_date date
) returns table (
  child_id uuid, body text, author_name text, updated_at timestamptz
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  return query
  select n.child_id, n.body, e.name, n.updated_at
  from child_daily_arrival_notes n
  left join employees e on e.id = n.author_employee_id
  where n.office_id = p_office_id and n.business_date = p_business_date;
end $$;
grant execute on function fetch_arrival_notes_for_office(uuid, date) to authenticated, service_role;
