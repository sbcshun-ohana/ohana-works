-- 232: 共通除去食の日次判定(M6 Phase 6・草案§16.2・本案§4の除去部分)。staging適用済(2026-08-18)。
-- 施設×提供日の除去対応が必要な児と、共通除去食で使わないアレルゲン集合を自動導出する。
-- 対象=在籍中かつ当日欠席でない児。分類=給食状態5区分の優先順(hold→bento→elimination)。
-- 全職員閲覧可(厨房・現場が見る)。食数カウント・確定スナップショット・厨房ページはPhase 7。

create or replace function fetch_daily_elimination_for_office(p_office_id uuid, p_business_date date)
returns table (
  child_id uuid,
  child_name text,
  class_name text,
  handling text,
  elimination_targets text[]
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not has_childcare_office_access(p_office_id) then
    raise exception 'not authorized';
  end if;
  return query
  with base as (
    select c.id, c.display_name, cc.class_name,
      (select array_agg(distinct t)
       from child_allergy_diagnoses d, unnest(coalesce(d.elimination_targets, '{}')) t
       where d.child_id = c.id and d.status = 'received'
         and (d.effective_from is null or d.effective_from <= p_business_date)
         and (d.effective_until is null or d.effective_until >= p_business_date)) as targets,
      exists (select 1 from child_allergy_diagnoses d
              where d.child_id = c.id and d.status = 'requested') as pending_diag,
      exists (select 1 from child_food_records r
              where r.child_id = c.id and r.result = 'symptom' and r.staff_confirmed_at is null) as pending_sym,
      exists (select 1 from child_food_records r
              where r.child_id = c.id and r.result = 'symptom' and r.staff_confirmed_at is not null) as review_sym,
      exists (select 1 from child_allergy_diagnoses d
              where d.child_id = c.id and d.status in ('received', 'released')) as medical_resolved
    from children c
    left join child_class_enrollments cce on cce.child_id = c.id and cce.effective_end_date is null
    left join childcare_classes cc on cc.id = cce.class_id
    where c.office_id = p_office_id and c.enrollment_status = '在籍中'
      and not exists (
        select 1 from child_daily_attendance a
        where a.child_id = c.id and a.business_date = p_business_date and a.is_absent
      )
  )
  select id, display_name, class_name,
    case
      when pending_sym then 'hold'
      when pending_diag then 'bento'
      when array_length(targets, 1) > 0 then 'elimination'
      when review_sym and not medical_resolved then 'hold'
      else null
    end,
    case when array_length(targets, 1) > 0
             and not pending_sym and not pending_diag
         then coalesce(targets, '{}') else '{}'::text[] end
  from base
  where pending_sym or pending_diag or array_length(targets, 1) > 0
     or (review_sym and not medical_resolved)
  order by class_name, display_name;
end;
$$;

create or replace function fetch_daily_elimination_summary(p_office_id uuid, p_business_date date)
returns table (
  common_elimination_allergens text[],
  elimination_count bigint,
  bento_count bigint,
  hold_count bigint
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not has_childcare_office_access(p_office_id) then
    raise exception 'not authorized';
  end if;
  return query
  select
    coalesce((select array_agg(distinct t order by t)
              from fetch_daily_elimination_for_office(p_office_id, p_business_date) x,
                   unnest(x.elimination_targets) t
              where x.handling = 'elimination'), '{}'::text[]),
    count(*) filter (where handling = 'elimination'),
    count(*) filter (where handling = 'bento'),
    count(*) filter (where handling = 'hold')
  from fetch_daily_elimination_for_office(p_office_id, p_business_date);
end;
$$;
