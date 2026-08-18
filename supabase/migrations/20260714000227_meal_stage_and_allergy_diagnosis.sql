-- 227: 給食段階判定+アレルギー診断書(M6 Phase 5・本案§3-1/3-2・草案§15-16)。staging適用済(2026-08-18)。
-- 1) child_allergy_diagnoses(§16.3・原本受領が正・履歴): requested→received→released/expired
-- 2) child_meal_stages(承認済み給食段階の履歴・提供開始日を分ける)
-- 3) RPC: fetch_child_meal_status(全職員・5区分導出+候補算出)/fetch_meal_status_for_office(管理者以上)
--         approve_meal_stage(管理者以上)/診断書 create_request/record/release/fetch(依頼系=管理者以上・閲覧=全職員)
-- 5区分(本案§3-1): 給食開始保留(症状未処理/医療確認中)→弁当持参(診断書待ち)→共通除去食(診断確定)→通常食→給食提供前
-- 候補(本案§3-2): late=9か月+初中後期必須完了/complete=12か月+完了期完了/toddler=18か月。承認・提供開始日は別。
-- フラグは food_check_enabled を流用。冪等: テーブル=素create・関数=create or replace。

create table child_allergy_diagnoses (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  office_id uuid not null references offices(id),
  status text not null default 'requested'
    check (status in ('requested', 'received', 'released', 'expired')),
  requested_at date,
  received_at date,
  confirmed_by uuid references employees(id),
  doctor_name text,
  medical_institution text,
  diagnosis_content text,
  elimination_targets text[],
  effective_from date,
  effective_until date,
  renewal_deadline date,
  document_path text,
  release_note text,
  superseded_by uuid references child_allergy_diagnoses(id),
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_child_allergy_diagnoses_updated_at before update on child_allergy_diagnoses
  for each row execute function set_updated_at();
create index idx_child_allergy_diagnoses_child on child_allergy_diagnoses(child_id, status);
comment on table child_allergy_diagnoses is
  'アレルギー診断書(227・§16.3)。原本受領(status=received)が正・ファイル添付は補助。変更時はsuperseded_byで履歴。';
alter table child_allergy_diagnoses enable row level security;

create table child_meal_stages (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  office_id uuid not null references offices(id),
  stage text not null check (stage in ('late', 'complete', 'toddler')),
  approved_by uuid references employees(id),
  approved_at timestamptz not null default now(),
  serving_start_date date not null,
  note text,
  created_at timestamptz not null default now()
);
create index idx_child_meal_stages_child on child_meal_stages(child_id, approved_at desc);
comment on table child_meal_stages is
  '承認済み給食段階(227)。後期食/完了食/幼児食。承認日と提供開始日を分ける(本案§3-2)。現在=最新行。';
alter table child_meal_stages enable row level security;

create or replace function fetch_child_meal_status(p_child_id uuid)
returns table (
  months_old int,
  stage_initial_done boolean,
  stage_middle_done boolean,
  stage_late_done boolean,
  stage_complete_done boolean,
  pending_symptom_count bigint,
  in_medical_review_count bigint,
  active_elimination_targets text[],
  has_pending_diagnosis boolean,
  candidate_stage text,
  current_stage text,
  current_serving_start date,
  approved_stage text,
  approved_serving_start date,
  meal_status text
)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_birth date;
  v_months int;
  v_init boolean; v_mid boolean; v_late boolean; v_comp boolean;
  v_pending bigint; v_review bigint;
  v_targets text[];
  v_pending_diag boolean;
  v_candidate text;
  v_cur_stage text; v_cur_start date;
  v_app_stage text; v_app_start date;
  v_status text;
begin
  select office_id, birth_date into v_office_id, v_birth from children where id = p_child_id;
  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  v_months := case when v_birth is null then null
    else (extract(year from age(current_date, v_birth)) * 12
          + extract(month from age(current_date, v_birth)))::int end;

  with v as (
    select id, food_checklist_versions.required_times from food_checklist_versions
    where status = 'published' order by version desc limit 1
  ),
  items as (
    select ci.stage as st, ci.food_item_id, coalesce(ci.alt_group, ci.food_item_id::text) as grp, v.required_times
    from v join food_checklist_items ci on ci.version_id = v.id where ci.category = 'required'
  ),
  done_items as (
    select i.st, i.grp,
      (select count(*) filter (where r.result = 'ok') >= i.required_times
              or bool_or(r.result = 'ok' and r.multiple_confirmed)
       from child_food_records r where r.child_id = p_child_id and r.food_item_id = i.food_item_id) as is_done
    from items i
  ),
  grp_agg as (select st, grp, bool_or(coalesce(is_done, false)) as grp_done from done_items group by st, grp),
  stage_done as (select st, bool_and(grp_done) as all_done from grp_agg group by st)
  select
    coalesce((select all_done from stage_done where st = '初期'), false),
    coalesce((select all_done from stage_done where st = '中期'), false),
    coalesce((select all_done from stage_done where st = '後期'), false),
    coalesce((select all_done from stage_done where st = '完了期'), false)
  into v_init, v_mid, v_late, v_comp;

  select count(*) filter (where result = 'symptom' and staff_confirmed_at is null),
         count(*) filter (where result = 'symptom' and staff_confirmed_at is not null)
    into v_pending, v_review
  from child_food_records where child_id = p_child_id;

  select array_agg(distinct t) into v_targets
  from child_allergy_diagnoses d, unnest(coalesce(d.elimination_targets, '{}')) t
  where d.child_id = p_child_id and d.status = 'received'
    and (d.effective_from is null or d.effective_from <= current_date)
    and (d.effective_until is null or d.effective_until >= current_date);

  v_pending_diag := exists (
    select 1 from child_allergy_diagnoses where child_id = p_child_id and status = 'requested'
  );

  v_candidate := case
    when v_months is null then null
    when v_months >= 18 and v_comp and v_init and v_mid and v_late and v_pending = 0 then 'toddler'
    when v_months >= 12 and v_comp and v_init and v_mid and v_late and v_pending = 0 then 'complete'
    when v_months >= 9 and v_init and v_mid and v_late and v_pending = 0 then 'late'
    else null
  end;

  select stage, serving_start_date into v_app_stage, v_app_start
  from child_meal_stages where child_id = p_child_id order by approved_at desc limit 1;

  select stage, serving_start_date into v_cur_stage, v_cur_start
  from child_meal_stages
  where child_id = p_child_id and serving_start_date <= current_date
  order by approved_at desc limit 1;

  v_status := case
    when v_pending > 0 then '給食開始保留'
    when v_pending_diag then '弁当持参'
    when array_length(v_targets, 1) > 0 then '共通除去食'
    when v_review > 0 then '給食開始保留'
    when v_cur_stage is not null then '通常食'
    else '給食提供前'
  end;

  return query select v_months, v_init, v_mid, v_late, v_comp, v_pending, v_review,
    coalesce(v_targets, '{}'), v_pending_diag, v_candidate,
    v_cur_stage, v_cur_start, v_app_stage, v_app_start, v_status;
end;
$$;

create or replace function fetch_meal_status_for_office(p_office_id uuid)
returns table (
  child_id uuid,
  child_name text,
  class_name text,
  meal_status text,
  candidate_stage text,
  current_stage text,
  approved_stage text,
  approved_serving_start date
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not is_childcare_admin(p_office_id) then
    raise exception 'not authorized';
  end if;
  return query
  select c.id, c.display_name, cc.class_name,
    s.meal_status, s.candidate_stage, s.current_stage, s.approved_stage, s.approved_serving_start
  from children c
  left join child_class_enrollments cce on cce.child_id = c.id and cce.effective_end_date is null
  left join childcare_classes cc on cc.id = cce.class_id
  cross join lateral fetch_child_meal_status(c.id) s
  where c.office_id = p_office_id and c.enrollment_status = '在籍中'
  order by cc.class_name, c.display_name;
end;
$$;

create or replace function approve_meal_stage(
  p_child_id uuid, p_stage text, p_serving_start_date date, p_note text default null
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_id uuid;
begin
  select office_id into v_office_id from children where id = p_child_id;
  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not is_childcare_admin(v_office_id) then
    raise exception 'not authorized';
  end if;
  if p_stage not in ('late', 'complete', 'toddler') then
    raise exception 'invalid stage';
  end if;
  if p_serving_start_date is null or p_serving_start_date < current_date then
    raise exception 'serving start date must be today or later';
  end if;

  insert into child_meal_stages (child_id, office_id, stage, approved_by, serving_start_date, note)
  values (p_child_id, v_office_id, p_stage, my_employee_id(), p_serving_start_date, p_note)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function create_allergy_diagnosis_request(p_child_id uuid, p_requested_at date default null)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_office_id uuid; v_id uuid;
begin
  select office_id into v_office_id from children where id = p_child_id;
  if v_office_id is null then raise exception 'child not found'; end if;
  if not is_childcare_admin(v_office_id) then raise exception 'not authorized'; end if;
  insert into child_allergy_diagnoses (child_id, office_id, status, requested_at, created_by)
  values (p_child_id, v_office_id, 'requested', coalesce(p_requested_at, current_date), my_employee_id())
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function record_allergy_diagnosis(
  p_diagnosis_id uuid,
  p_received_at date,
  p_doctor_name text,
  p_medical_institution text,
  p_diagnosis_content text,
  p_elimination_targets text[],
  p_effective_from date,
  p_effective_until date default null,
  p_renewal_deadline date default null,
  p_document_path text default null
)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_office_id uuid;
begin
  select office_id into v_office_id from child_allergy_diagnoses where id = p_diagnosis_id;
  if v_office_id is null then raise exception 'diagnosis not found'; end if;
  if not is_childcare_admin(v_office_id) then raise exception 'not authorized'; end if;
  update child_allergy_diagnoses set
    status = 'received',
    received_at = coalesce(p_received_at, current_date),
    confirmed_by = my_employee_id(),
    doctor_name = p_doctor_name,
    medical_institution = p_medical_institution,
    diagnosis_content = p_diagnosis_content,
    elimination_targets = p_elimination_targets,
    effective_from = p_effective_from,
    effective_until = p_effective_until,
    renewal_deadline = p_renewal_deadline,
    document_path = p_document_path
  where id = p_diagnosis_id;
end;
$$;

create or replace function release_allergy_diagnosis(p_diagnosis_id uuid, p_note text default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_office_id uuid;
begin
  select office_id into v_office_id from child_allergy_diagnoses where id = p_diagnosis_id;
  if v_office_id is null then raise exception 'diagnosis not found'; end if;
  if not is_childcare_admin(v_office_id) then raise exception 'not authorized'; end if;
  update child_allergy_diagnoses set status = 'released', release_note = p_note where id = p_diagnosis_id;
end;
$$;

create or replace function fetch_child_allergy_diagnoses(p_child_id uuid)
returns table (
  id uuid, status text, requested_at date, received_at date,
  doctor_name text, medical_institution text, diagnosis_content text,
  elimination_targets text[], effective_from date, effective_until date,
  renewal_deadline date, document_path text, release_note text, created_at timestamptz
)
language plpgsql stable security definer set search_path = public
as $$
declare v_office_id uuid;
begin
  select office_id into v_office_id from children where id = p_child_id;
  if v_office_id is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office_id) then raise exception 'not authorized'; end if;
  return query
  select d.id, d.status, d.requested_at, d.received_at, d.doctor_name, d.medical_institution,
    d.diagnosis_content, d.elimination_targets, d.effective_from, d.effective_until,
    d.renewal_deadline, d.document_path, d.release_note, d.created_at
  from child_allergy_diagnoses d where d.child_id = p_child_id order by d.created_at desc;
end;
$$;
