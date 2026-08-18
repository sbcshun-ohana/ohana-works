-- 233: fetch_daily_elimination_for_office の列名衝突修正(232のバグ・staging適用済 2026-08-18)。
-- サマリー関数内の unnest/count が戻り値 class_name と衝突(42702)。base側をエイリアス(bid/bname/bclass)で分離。
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
    select c.id as bid, c.display_name as bname, cc.class_name as bclass,
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
  select bid, bname, bclass,
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
  order by bclass, bname;
end;
$$;
