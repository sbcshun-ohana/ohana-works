-- 271: アレルギー管理 Phase 1 = 発症報告 + 給食停止/再開。給食管理設計書§7.2/7.3。
-- 保護者が発症報告→主任以上へ重要通知→主任以上が確認して給食停止(弁当持参・自動停止しない)→受診結果で再開。
-- 停止しない判断も理由付き記録。フラグ=meal_management_enabled。

-- (1) 発症報告
create table allergy_incident_reports (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  office_id uuid not null references offices(id) on delete cascade,
  eaten_food text,                     -- 食べたもの
  symptoms text not null,              -- 症状
  occurred_at timestamptz,             -- 発生日時
  hospital_plan text,                  -- 受診予定
  reported_by_guardian_id uuid references guardians(id),
  status text not null default 'reported' check (status in ('reported', 'handled')),
  reviewed_by uuid references employees(id),
  reviewed_at timestamptz,
  review_note text,                    -- 停止/停止しない判断のメモ
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_allergy_incident_office on allergy_incident_reports(office_id, status, created_at desc);
create trigger trg_allergy_incident_updated_at before update on allergy_incident_reports
  for each row execute function set_updated_at();
alter table allergy_incident_reports enable row level security;

-- (2) 給食停止(弁当持参)。active = ended_at is null。
create table meal_suspensions (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  office_id uuid not null references offices(id) on delete cascade,
  reason text not null default 'allergy_incident',
  incident_report_id uuid references allergy_incident_reports(id) on delete set null,
  note text,
  started_by uuid references employees(id),
  started_at timestamptz not null default now(),
  ended_by uuid references employees(id),
  ended_at timestamptz,
  end_note text,
  created_at timestamptz not null default now()
);
create index idx_meal_suspensions_child on meal_suspensions(child_id) where ended_at is null;
create index idx_meal_suspensions_office on meal_suspensions(office_id) where ended_at is null;
alter table meal_suspensions enable row level security;

-- (3) 保護者: 発症報告の登録 → 主任以上へ重要通知
create or replace function submit_allergy_incident_report(
  p_child_id uuid, p_eaten_food text, p_symptoms text, p_occurred_at timestamptz, p_hospital_plan text
)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_office uuid; v_name text;
begin
  if not guardian_has_child_access(p_child_id) then raise exception 'not authorized'; end if;
  if coalesce(trim(p_symptoms), '') = '' then raise exception 'symptoms required'; end if;
  select office_id, display_name into v_office, v_name from children where id = p_child_id;
  if not is_meal_management_enabled_for_office(v_office) then raise exception 'feature disabled'; end if;
  insert into allergy_incident_reports (child_id, office_id, eaten_food, symptoms, occurred_at, hospital_plan, reported_by_guardian_id)
  values (p_child_id, v_office, p_eaten_food, p_symptoms, p_occurred_at, p_hospital_plan, my_guardian_id())
  returning id into v_id;
  insert into notifications (notification_type, title, body, channels, target_employee_id, payload, status)
  select 'allergy_incident', '【アレルギー】発症報告',
    v_name || 'さん: アレルギー反応の報告がありました。給食停止の要否を確認してください。',
    array['push'], emp, jsonb_build_object('report_id', v_id::text, 'child_id', p_child_id::text), 'pending'
  from childcare_office_manager_employee_ids(v_office) emp;
  return v_id;
end $$;
grant execute on function submit_allergy_incident_report(uuid, text, text, timestamptz, text) to authenticated, service_role;

-- (4) 主任以上: 給食停止(弁当持参)。自動停止しない=職員の明示操作。
create or replace function suspend_child_meal(p_child_id uuid, p_incident_report_id uuid, p_note text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_id uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  select id into v_id from meal_suspensions where child_id = p_child_id and ended_at is null limit 1;
  if v_id is null then
    insert into meal_suspensions (child_id, office_id, reason, incident_report_id, note, started_by)
    values (p_child_id, v_office, 'allergy_incident', p_incident_report_id, p_note, my_employee_id())
    returning id into v_id;
  end if;
  if p_incident_report_id is not null then
    update allergy_incident_reports set status = 'handled', reviewed_by = my_employee_id(), reviewed_at = now(),
      review_note = coalesce(nullif(trim(p_note), ''), '給食停止(弁当持参)')
    where id = p_incident_report_id;
  end if;
  return v_id;
end $$;
grant execute on function suspend_child_meal(uuid, uuid, text) to authenticated, service_role;

-- (5) 主任以上: 給食再開(active停止を終了)
create or replace function resume_child_meal(p_child_id uuid, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  update meal_suspensions set ended_by = my_employee_id(), ended_at = now(), end_note = p_note
  where child_id = p_child_id and ended_at is null;
end $$;
grant execute on function resume_child_meal(uuid, text) to authenticated, service_role;

-- (6) 主任以上: 停止しない判断(理由付き記録)
create or replace function record_incident_no_suspension(p_incident_report_id uuid, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from allergy_incident_reports where id = p_incident_report_id;
  if v_office is null then raise exception 'not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  update allergy_incident_reports set status = 'handled', reviewed_by = my_employee_id(), reviewed_at = now(),
    review_note = coalesce(nullif(trim(p_note), ''), '給食停止せず(提供食材と無関係等)')
  where id = p_incident_report_id;
end $$;
grant execute on function record_incident_no_suspension(uuid, text) to authenticated, service_role;

-- (7) 施設職員: 発症報告一覧
create or replace function fetch_allergy_incident_reports_for_office(p_office_id uuid, p_only_open boolean default false)
returns table (id uuid, child_id uuid, child_name text, eaten_food text, symptoms text, occurred_at timestamptz,
               hospital_plan text, status text, review_note text, reviewed_at timestamptz, created_at timestamptz,
               suspended boolean)
language plpgsql security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  return query
    select r.id, r.child_id, c.display_name, r.eaten_food, r.symptoms, r.occurred_at,
           r.hospital_plan, r.status, r.review_note, r.reviewed_at, r.created_at,
           exists(select 1 from meal_suspensions ms where ms.child_id = r.child_id and ms.ended_at is null)
    from allergy_incident_reports r join children c on c.id = r.child_id
    where r.office_id = p_office_id and (not p_only_open or r.status = 'reported')
    order by r.created_at desc;
end $$;
grant execute on function fetch_allergy_incident_reports_for_office(uuid, boolean) to authenticated, service_role;

-- (8) ボード用: 給食停止中の園児(弁当持参・アレルギー確認中)
create or replace function fetch_meal_suspended_children_for_office(p_office_id uuid)
returns table (child_id uuid, child_name text, note text, started_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  return query
    select ms.child_id, c.display_name, ms.note, ms.started_at
    from meal_suspensions ms join children c on c.id = ms.child_id
    where ms.office_id = p_office_id and ms.ended_at is null
    order by c.display_name;
end $$;
grant execute on function fetch_meal_suspended_children_for_office(uuid) to authenticated, service_role;
