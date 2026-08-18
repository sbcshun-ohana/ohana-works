-- 239: 発達記録 Phase 2 = 達成記録・申請・承認・取消(RPC+RLS)。
-- 正本=docs/Ohana_Works_設計指示書_発達記録_Opus実装用_v1_0_2026-08-18.md §6/§8/§10。
-- 状態=未達成/達成済みの2値。一園児一項目の有効達成は最大1件(partial unique)。
-- 権限(全てサーバー側で強制):
--   閲覧            = has_childcare_office_access(office)  … 全職員(所属施設・保護者は不可)
--   申請/却下/取下げ = 担任(担当クラス) or manages_childcare(office)  … 担当外staffは不可
--   承認/差戻/直接登録/取消 = manages_childcare(office)          … 主任(chief)以上
-- AI候補(development_ai_candidates)はPhase 4で新設。本Phaseは ai_candidate_id を nullable uuid
-- 列として先に持たせる(FKはPhase 4で追加)。source='ai_candidate' 経路はPhase 4で実際に使う。

-- ─────────────────────────────────────────────────────────────
-- 担任・担当クラス判定: my_employee_id が対象園児の現在の在籍クラスの担任か。
-- 現在の在籍 = child_class_enrollments.effective_end_date is null。
-- 現在の担任 = class_homeroom_assignments.unassigned_at is null。
create or replace function is_child_homeroom_staff(p_child_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from child_class_enrollments cce
    join class_homeroom_assignments cha
      on cha.class_id = cce.class_id and cha.unassigned_at is null
    where cce.child_id = p_child_id
      and cce.effective_end_date is null
      and cha.employee_id = my_employee_id()
  );
$$;
grant execute on function is_child_homeroom_staff(uuid) to authenticated, service_role;
comment on function is_child_homeroom_staff(uuid) is
  '対象園児の現在の在籍クラスの担任か(担任・担当クラス判定・239)。';

-- ─────────────────────────────────────────────────────────────
-- 達成記録(確定した達成。一園児一項目の有効行は最大1件)
create table child_development_achievements (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  office_id uuid not null references offices(id),
  item_id uuid not null references development_item_masters(id),
  item_version_id uuid references development_item_master_versions(id),
  target_year_month text not null,              -- 'YYYY-MM'(保育年度内の対象月)
  first_achieved_on date not null,
  approved_by uuid not null references employees(id),  -- 確定した職員
  requested_by uuid references employees(id),          -- 申請者(直接登録時はnull)
  method text not null check (method in ('manual_request','ai_request','direct')),
  ai_candidate_id uuid,                          -- Phase 4でFK追加
  -- マスター内容のスナップショット(確定時点)
  item_name text not null,
  domain_code text not null,
  observation_point text,
  is_active boolean not null default true,
  cancelled_at timestamptz,
  cancelled_by uuid references employees(id),
  cancel_reason text,
  created_at timestamptz not null default now()
);
-- 有効な達成は一園児一項目につき最大1件
create unique index uq_cda_active on child_development_achievements(child_id, item_id) where is_active;
create index idx_cda_child on child_development_achievements(child_id);
create index idx_cda_office on child_development_achievements(office_id);
alter table child_development_achievements enable row level security;
create policy cda_select on child_development_achievements
  for select using (has_childcare_office_access(office_id));
comment on table child_development_achievements is
  '園児×発達項目の達成記録(239)。確定=主任以上。有効行は一園児一項目1件(partial unique)。';

-- 達成申請(承認待ち/承認済み/差戻し/取下げ)
create table development_achievement_requests (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  office_id uuid not null references offices(id),
  item_id uuid not null references development_item_masters(id),
  source text not null default 'manual' check (source in ('manual','ai_candidate')),
  ai_candidate_id uuid,
  note text,
  status text not null default 'pending_review'
    check (status in ('pending_review','approved','returned','withdrawn')),
  requested_by uuid not null references employees(id),
  requested_at timestamptz not null default now(),
  decided_by uuid references employees(id),
  decided_at timestamptz,
  decide_note text,
  created_at timestamptz not null default now()
);
-- 同一園児×項目で承認待ちは同時に1件(二重申請防止)
create unique index uq_dar_pending on development_achievement_requests(child_id, item_id)
  where status = 'pending_review';
create index idx_dar_office_status on development_achievement_requests(office_id, status);
create index idx_dar_requested_by on development_achievement_requests(requested_by);
alter table development_achievement_requests enable row level security;
create policy dar_select on development_achievement_requests
  for select using (has_childcare_office_access(office_id));
comment on table development_achievement_requests is
  '発達達成の申請(239)。申請=担任/主任以上、承認=主任以上。承認待ちは一園児一項目1件。';

-- 監査
do $$
begin
  execute format('create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();', 'child_development_achievements');
  execute format('create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();', 'development_achievement_requests');
end $$;

-- ─────────────────────────────────────────────────────────────
-- 内部ヘルパー: 達成行を作成(スナップショット付き)。authzは呼び出し側で実施。
-- authenticatedへは付与しない(SECURITY DEFINERのRPCからのみ呼ぶ)。
create or replace function create_dev_achievement_internal(
  p_child_id uuid, p_item_id uuid, p_method text, p_requested_by uuid,
  p_ai_candidate_id uuid, p_first_achieved_on date, p_target_year_month text
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_office uuid;
  v_m development_item_masters%rowtype;
  v_on date;
  v_ym text;
  v_ver uuid;
  v_id uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found: %', p_child_id; end if;
  select * into v_m from development_item_masters where id = p_item_id;
  if v_m.id is null then raise exception 'item not found: %', p_item_id; end if;

  v_on := coalesce(p_first_achieved_on, (now() at time zone 'Asia/Tokyo')::date);
  v_ym := coalesce(p_target_year_month, to_char(v_on, 'YYYY-MM'));
  select id into v_ver from development_item_master_versions
    where item_id = p_item_id and version = v_m.current_version;

  insert into child_development_achievements
    (child_id, office_id, item_id, item_version_id, target_year_month, first_achieved_on,
     approved_by, requested_by, method, ai_candidate_id, item_name, domain_code, observation_point)
  values
    (p_child_id, v_office, p_item_id, v_ver, v_ym, v_on,
     my_employee_id(), p_requested_by, p_method, p_ai_candidate_id,
     v_m.item_name, v_m.domain_code, v_m.observation_point)
  returning id into v_id;
  return v_id;
exception when unique_violation then
  raise exception '既に達成済みです(同一項目の二重達成)';
end $$;

-- ─────────────────────────────────────────────────────────────
-- 1) 達成申請(担任・担当クラス or 主任以上)
create or replace function submit_development_achievement_request(
  p_child_id uuid, p_item_id uuid,
  p_source text default 'manual', p_ai_candidate_id uuid default null, p_note text default null
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_office uuid; v_req uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not (is_child_homeroom_staff(p_child_id) or manages_childcare(v_office)) then
    raise exception 'not authorized';
  end if;
  if p_source not in ('manual','ai_candidate') then raise exception 'invalid source'; end if;
  if not exists (select 1 from development_item_masters where id = p_item_id and is_active) then
    raise exception 'item not found or inactive';
  end if;
  if exists (select 1 from child_development_achievements
             where child_id = p_child_id and item_id = p_item_id and is_active) then
    raise exception '既に達成済みです';
  end if;

  insert into development_achievement_requests
    (child_id, office_id, item_id, source, ai_candidate_id, note, status, requested_by)
  values (p_child_id, v_office, p_item_id, p_source, p_ai_candidate_id, p_note, 'pending_review', my_employee_id())
  returning id into v_req;
  return v_req;
exception when unique_violation then
  raise exception '既に承認待ちの申請があります';
end $$;
grant execute on function submit_development_achievement_request(uuid, uuid, text, uuid, text) to authenticated, service_role;

-- 2) 申請の取下げ(自分の申請・承認前のみ)
create or replace function withdraw_development_achievement_request(
  p_request_id uuid, p_note text default null
) returns void
language plpgsql security definer set search_path = public
as $$
declare v_updated int;
begin
  update development_achievement_requests
    set status = 'withdrawn', decided_by = my_employee_id(), decided_at = now(), decide_note = p_note
    where id = p_request_id
      and requested_by = my_employee_id()
      and status = 'pending_review';
  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    raise exception 'not authorized or not pending';  -- 他人の申請/処理済み/存在しない
  end if;
end $$;
grant execute on function withdraw_development_achievement_request(uuid, text) to authenticated, service_role;

-- 3) 申請の承認/差し戻し(主任以上・自施設)
create or replace function decide_development_achievement_request(
  p_request_id uuid, p_approve boolean, p_note text default null,
  p_first_achieved_on date default null, p_target_year_month text default null
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare r development_achievement_requests%rowtype; v_ach uuid; v_method text;
begin
  select * into r from development_achievement_requests where id = p_request_id;
  if r.id is null then raise exception 'request not found'; end if;
  if not manages_childcare(r.office_id) then raise exception 'not authorized'; end if;
  if r.status <> 'pending_review' then raise exception '処理済みの申請です'; end if;

  if p_approve then
    v_method := case when r.source = 'ai_candidate' then 'ai_request' else 'manual_request' end;
    -- 達成行を作成(二重達成はcreate_dev_achievement_internal内のunique_violationで防止)
    v_ach := create_dev_achievement_internal(
      r.child_id, r.item_id, v_method, r.requested_by, r.ai_candidate_id,
      p_first_achieved_on, p_target_year_month);
    update development_achievement_requests
      set status = 'approved', decided_by = my_employee_id(), decided_at = now(), decide_note = p_note
      where id = p_request_id;
    return v_ach;
  else
    update development_achievement_requests
      set status = 'returned', decided_by = my_employee_id(), decided_at = now(), decide_note = p_note
      where id = p_request_id;
    return null;
  end if;
end $$;
grant execute on function decide_development_achievement_request(uuid, boolean, text, date, text) to authenticated, service_role;

-- 4) 直接達成登録(申請省略・主任以上)
create or replace function register_development_achievement_direct(
  p_child_id uuid, p_item_id uuid,
  p_first_achieved_on date default null, p_target_year_month text default null
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_office uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  if not exists (select 1 from development_item_masters where id = p_item_id and is_active) then
    raise exception 'item not found or inactive';
  end if;
  return create_dev_achievement_internal(
    p_child_id, p_item_id, 'direct', null, null, p_first_achieved_on, p_target_year_month);
end $$;
grant execute on function register_development_achievement_direct(uuid, uuid, date, text) to authenticated, service_role;

-- 5) 達成の取消(主任以上)。未達成へ戻すが履歴は残す。
create or replace function cancel_development_achievement(
  p_achievement_id uuid, p_reason text default null
) returns void
language plpgsql security definer set search_path = public
as $$
declare v_office uuid; v_updated int;
begin
  select office_id into v_office from child_development_achievements
    where id = p_achievement_id and is_active;
  if v_office is null then raise exception 'achievement not found or already cancelled'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;

  update child_development_achievements
    set is_active = false, cancelled_at = now(), cancelled_by = my_employee_id(), cancel_reason = p_reason
    where id = p_achievement_id and is_active;
  get diagnostics v_updated = row_count;
  if v_updated = 0 then raise exception 'achievement not found or already cancelled'; end if;
end $$;
grant execute on function cancel_development_achievement(uuid, text) to authenticated, service_role;
