-- 256: 給食管理 Phase 1 ③-a。給食状態判定を authzなしの内部版に切り出す(算出エンジンのcronから呼ぶため)。
-- 228の fetch_child_meal_status を「内部(authzなし)」と「公開(authzのみ・戻り型不変)」に分離。既存呼出は不変。
create or replace function fetch_child_meal_status_internal(p_child_id uuid)
returns table (
  months_old int, stage_initial_done boolean, stage_middle_done boolean, stage_late_done boolean,
  stage_complete_done boolean, pending_symptom_count bigint, in_medical_review_count bigint,
  active_elimination_targets text[], has_pending_diagnosis boolean, candidate_stage text,
  current_stage text, current_serving_start date, approved_stage text, approved_serving_start date,
  meal_status text
)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_office_id uuid; v_birth date; v_months int;
  v_init boolean; v_mid boolean; v_late boolean; v_comp boolean;
  v_pending bigint; v_review bigint; v_targets text[];
  v_pending_diag boolean; v_medical_resolved boolean;
  v_candidate text; v_cur_stage text; v_cur_start date; v_app_stage text; v_app_start date; v_status text;
begin
  select office_id, birth_date into v_office_id, v_birth from children where id = p_child_id;
  if v_office_id is null then raise exception 'child not found'; end if;

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
  v_medical_resolved := exists (
    select 1 from child_allergy_diagnoses where child_id = p_child_id and status in ('received', 'released')
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
    when v_review > 0 and not v_medical_resolved then '給食開始保留'
    when v_cur_stage is not null then '通常食'
    else '給食提供前'
  end;

  return query select v_months, v_init, v_mid, v_late, v_comp, v_pending, v_review,
    coalesce(v_targets, '{}'), v_pending_diag, v_candidate,
    v_cur_stage, v_cur_start, v_app_stage, v_app_start, v_status;
end;
$$;

-- 公開版: 認可のみ担当し内部へ委譲(戻り型不変・既存呼出互換)
create or replace function fetch_child_meal_status(p_child_id uuid)
returns table (
  months_old int, stage_initial_done boolean, stage_middle_done boolean, stage_late_done boolean,
  stage_complete_done boolean, pending_symptom_count bigint, in_medical_review_count bigint,
  active_elimination_targets text[], has_pending_diagnosis boolean, candidate_stage text,
  current_stage text, current_serving_start date, approved_stage text, approved_serving_start date,
  meal_status text
)
language plpgsql stable security definer set search_path = public
as $$
declare v_office uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  return query select * from fetch_child_meal_status_internal(p_child_id);
end;
$$;
grant execute on function fetch_child_meal_status(uuid) to authenticated, service_role;
