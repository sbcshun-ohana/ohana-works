-- 267: 献立管理 Phase 1 基盤。献立管理設計書v1.0(2026-08-20)§6準拠。
-- (1) menu_imports(264)を設計書に合わせて拡張(status: analyzing/reviewing/published/fallback、format_kind、ai_run_id、confirmed_by/at)
-- (2) menu_days: 行=食種(food_type)×区分(meal_slot)の構造化献立(ingredients/nutrition=jsonb、除去食=removal_kind/removal_note)
-- (3) menu_format_assignments: 施設ごとのフォーマット割当(A=YASUDA委託 / B=Halelea業者 / other)
-- AI解析はEdge Function(別・Anthropic・APIキー未設定時はモック)。除去食の保護者公開はアレルギー管理実装後(本Phaseは園側のみ)。

-- ============================================================
-- (1) menu_imports 拡張
-- ============================================================
alter table menu_imports add column if not exists format_kind text;               -- 'yasuda'(A)/'halelea'(B)/'other'
alter table menu_imports add column if not exists ai_run_id uuid references ai_runs(id);
alter table menu_imports add column if not exists confirmed_by uuid references employees(id);
alter table menu_imports add column if not exists confirmed_at timestamptz;

-- 既存 status(draft/published/superseded)を設計書の値へ。draft→reviewing に移行。
update menu_imports set status = 'reviewing' where status = 'draft';
alter table menu_imports drop constraint if exists menu_imports_status_check;
alter table menu_imports add constraint menu_imports_status_check
  check (status in ('analyzing', 'reviewing', 'published', 'fallback', 'superseded'));
alter table menu_imports alter column status set default 'reviewing';

-- ============================================================
-- (2) menu_days(行=食種×区分)
-- ============================================================
create table menu_days (
  id uuid primary key default gen_random_uuid(),
  import_id uuid not null references menu_imports(id) on delete cascade,  -- 取込版(スナップショット単位)
  office_id uuid not null references offices(id) on delete cascade,
  menu_date date not null,
  -- 食種: 以上児/未満児(通常)/離乳食後期/完了期/除去食
  food_type text not null check (food_type in ('regular_over3', 'regular_under3', 'weaning_late', 'weaning_final', 'allergy_removed')),
  removal_kind text,   -- allergy_removed のとき 卵/そば/ピーナッツ 等。それ以外は null
  meal_slot text not null check (meal_slot in ('am_snack', 'lunch', 'pm_snack')),
  menu_text text,      -- メニュー本文(複数行可)
  ingredients jsonb,   -- 材料(例: {"熱や力":..,"血や肉や骨":..,"体の調子":..,"その他":..})
  nutrition jsonb,     -- 栄養価(例: {"energy":..,"protein":..} / 未満児・以上児2段は配列可)
  removal_note text,   -- 除去食の 除去・代替内容
  created_by uuid references employees(id),
  updated_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- 同一取込版・日・食種・除去種別・区分は1行(除去種別nullは''として一意化)
create unique index uq_menu_days on menu_days (import_id, menu_date, food_type, coalesce(removal_kind, ''), meal_slot);
create index idx_menu_days_office_date on menu_days (office_id, menu_date);
create trigger trg_menu_days_updated_at before update on menu_days
  for each row execute function set_updated_at();
alter table menu_days enable row level security;  -- 直接アクセス不可(全てRPC経由)

-- ============================================================
-- (3) フォーマット割当マスタ(施設ごと)
-- ============================================================
create table menu_format_assignments (
  office_id uuid primary key references offices(id) on delete cascade,
  format_kind text not null check (format_kind in ('yasuda', 'halelea', 'other')),
  updated_by uuid references employees(id),
  updated_at timestamptz not null default now()
);
alter table menu_format_assignments enable row level security;

create or replace function set_menu_format_assignment(p_office_id uuid, p_format_kind text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_childcare_admin(p_office_id) then raise exception 'not authorized'; end if;  -- 管理者以上
  if p_format_kind not in ('yasuda', 'halelea', 'other') then raise exception 'invalid format_kind'; end if;
  insert into menu_format_assignments (office_id, format_kind, updated_by, updated_at)
  values (p_office_id, p_format_kind, my_employee_id(), now())
  on conflict (office_id) do update set format_kind = p_format_kind, updated_by = my_employee_id(), updated_at = now();
end $$;
grant execute on function set_menu_format_assignment(uuid, text) to authenticated, service_role;

create or replace function fetch_menu_format_assignment(p_office_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select format_kind from menu_format_assignments where office_id = p_office_id;
$$;
grant execute on function fetch_menu_format_assignment(uuid) to authenticated, service_role;

-- ============================================================
-- (4) create_menu_import を format_kind 対応へ(264と同シグネチャ・中でマスタ参照)
-- ============================================================
create or replace function create_menu_import(
  p_office_id uuid, p_target_month date, p_format text, p_source_path text, p_source_filename text
)
returns menu_imports language plpgsql security definer set search_path = public as $$
declare v_row menu_imports; v_month date := date_trunc('month', p_target_month)::date; v_ver int; v_kind text;
begin
  if not is_meal_management_enabled_for_office(p_office_id) then raise exception 'feature disabled'; end if;
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  if p_format not in ('excel', 'pdf', 'image') then raise exception 'invalid format'; end if;
  select coalesce(max(version), 0) + 1 into v_ver from menu_imports where office_id = p_office_id and target_month = v_month;
  select format_kind into v_kind from menu_format_assignments where office_id = p_office_id;
  insert into menu_imports (office_id, target_month, format, source_path, source_filename, version, format_kind, status, uploaded_by)
  values (p_office_id, v_month, p_format, p_source_path, p_source_filename, v_ver, coalesce(v_kind, 'other'), 'reviewing', my_employee_id())
  returning * into v_row;
  return v_row;
end $$;
grant execute on function create_menu_import(uuid, date, text, text, text) to authenticated, service_role;

-- ============================================================
-- (5) menu_days の作成/更新(AI下書き・職員の確認修正)。編集=主任以上。
-- ============================================================
create or replace function upsert_menu_day(
  p_import_id uuid, p_menu_date date, p_food_type text, p_removal_kind text, p_meal_slot text,
  p_menu_text text, p_ingredients jsonb, p_nutrition jsonb, p_removal_note text
)
returns menu_days language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_row menu_days;
begin
  select office_id into v_office from menu_imports where id = p_import_id;
  if v_office is null then raise exception 'import not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  if p_food_type not in ('regular_over3', 'regular_under3', 'weaning_late', 'weaning_final', 'allergy_removed') then
    raise exception 'invalid food_type'; end if;
  if p_meal_slot not in ('am_snack', 'lunch', 'pm_snack') then raise exception 'invalid meal_slot'; end if;

  insert into menu_days (import_id, office_id, menu_date, food_type, removal_kind, meal_slot,
                         menu_text, ingredients, nutrition, removal_note, created_by, updated_by)
  values (p_import_id, v_office, p_menu_date, p_food_type, p_removal_kind, p_meal_slot,
          p_menu_text, p_ingredients, p_nutrition, p_removal_note, my_employee_id(), my_employee_id())
  on conflict (import_id, menu_date, food_type, coalesce(removal_kind, ''), meal_slot) do update
    set menu_text = excluded.menu_text, ingredients = excluded.ingredients, nutrition = excluded.nutrition,
        removal_note = excluded.removal_note, updated_by = my_employee_id(), updated_at = now()
  returning * into v_row;
  return v_row;
end $$;
grant execute on function upsert_menu_day(uuid, date, text, text, text, text, jsonb, jsonb, text) to authenticated, service_role;

create or replace function delete_menu_day(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from menu_days where id = p_id;
  if v_office is null then raise exception 'not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  delete from menu_days where id = p_id;
end $$;
grant execute on function delete_menu_day(uuid) to authenticated, service_role;

-- ============================================================
-- (6) 確認・公開・退避(主任以上=確認、管理者以上=公開/退避)
-- ============================================================
create or replace function confirm_menu_import(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v menu_imports;
begin
  select * into v from menu_imports where id = p_id;
  if v.id is null then raise exception 'not found'; end if;
  if not manages_childcare(v.office_id) then raise exception 'not authorized'; end if;  -- 主任以上
  update menu_imports set confirmed_by = my_employee_id(), confirmed_at = now() where id = p_id;
end $$;
grant execute on function confirm_menu_import(uuid) to authenticated, service_role;

-- 公開: 同一月の旧公開版を superseded にし本版を published に。fallback指定で退避モード公開。
create or replace function publish_menu_import(p_id uuid, p_fallback boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare v menu_imports;
begin
  select * into v from menu_imports where id = p_id;
  if v.id is null then raise exception 'not found'; end if;
  if not is_childcare_admin(v.office_id) then raise exception 'not authorized'; end if;  -- 管理者以上
  update menu_imports set status = 'superseded'
    where office_id = v.office_id and target_month = v.target_month and status in ('published', 'fallback') and id <> p_id;
  update menu_imports
    set status = case when p_fallback then 'fallback' else 'published' end,
        published_by = my_employee_id(), published_at = now()
    where id = p_id;
end $$;
-- 264の publish_menu_import(uuid) は本定義(引数追加=別シグネチャ)で置換。旧1引数版をdrop。
drop function if exists publish_menu_import(uuid);
grant execute on function publish_menu_import(uuid, boolean) to authenticated, service_role;

-- ============================================================
-- (7) 取得RPC(職員側)
-- ============================================================
-- 指定取込版の menu_days(確認画面用)。
create or replace function fetch_menu_days_for_import(p_import_id uuid)
returns table (
  id uuid, menu_date date, food_type text, removal_kind text, meal_slot text,
  menu_text text, ingredients jsonb, nutrition jsonb, removal_note text
) language plpgsql security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from menu_imports where id = p_import_id;
  if v_office is null then raise exception 'not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  return query
    select d.id, d.menu_date, d.food_type, d.removal_kind, d.meal_slot,
           d.menu_text, d.ingredients, d.nutrition, d.removal_note
    from menu_days d where d.import_id = p_import_id
    order by d.menu_date, d.food_type, d.meal_slot;
end $$;
grant execute on function fetch_menu_days_for_import(uuid) to authenticated, service_role;

-- 施設×日の公開済み献立(園側の日別ビュー・ボード連動用。全食種)。
create or replace function fetch_published_menu_day(p_office_id uuid, p_menu_date date)
returns table (food_type text, removal_kind text, meal_slot text, menu_text text,
               ingredients jsonb, nutrition jsonb, removal_note text)
language plpgsql security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  return query
    select d.food_type, d.removal_kind, d.meal_slot, d.menu_text, d.ingredients, d.nutrition, d.removal_note
    from menu_days d
    join menu_imports mi on mi.id = d.import_id
    where d.office_id = p_office_id and d.menu_date = p_menu_date and mi.status = 'published'
    order by d.food_type, d.meal_slot;
end $$;
grant execute on function fetch_published_menu_day(uuid, date) to authenticated, service_role;

-- ============================================================
-- (8) 保護者側: 公開済み・通常食種のみ(除去食=allergy_removed はアレルギー管理実装まで非公開=縮退)。
-- ============================================================
create or replace function fetch_published_menu_days_for_guardian(p_office_id uuid, p_target_month date, p_food_type text)
returns table (menu_date date, meal_slot text, menu_text text)
language plpgsql security definer set search_path = public as $$
declare v_month date := date_trunc('month', p_target_month)::date;
begin
  if not exists (
    select 1 from guardian_child_links gcl join children c on c.id = gcl.child_id
    where gcl.guardian_id = my_guardian_id() and c.office_id = p_office_id
  ) then raise exception 'not authorized'; end if;
  if not is_meal_parent_section_enabled_for_office(p_office_id) then return; end if;
  if p_food_type = 'allergy_removed' then return; end if;  -- 除去食の保護者公開は縮退で無効
  return query
    select d.menu_date, d.meal_slot, d.menu_text
    from menu_days d
    join menu_imports mi on mi.id = d.import_id
    where d.office_id = p_office_id and d.food_type = p_food_type and mi.status = 'published'
      and d.menu_date >= v_month and d.menu_date < (v_month + interval '1 month')::date
    order by d.menu_date, d.meal_slot;
end $$;
grant execute on function fetch_published_menu_days_for_guardian(uuid, date, text) to authenticated, service_role;
