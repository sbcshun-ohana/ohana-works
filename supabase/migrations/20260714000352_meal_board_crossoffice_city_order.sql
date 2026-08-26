-- 352: 厨房ビューの施設並び順を固定する(俊指示 2026-08-26)。
--   並び順: 大和(O) → ベイビーマハロ(M) → マハロステーション(S) → ハレレア(H) → その他。
--   従来は office_code の文字順(M,O,S,…)で並んでいた。戻り値の列は346から変更なし(allergy_count維持)。
--   ※戻り値の列を変える可能性があるため drop してから作り直す(create or replace は戻り型変更不可のため)。
drop function if exists fetch_meal_board_crossoffice(uuid[], date);
create function fetch_meal_board_crossoffice(p_office_ids uuid[], p_business_date date)
returns table (
  office_id uuid, office_name text, office_code text,
  row_key text, row_label text, row_type text, sort_order int,
  meal_slot text, child_count int, staff_count int, allergy_count int
)
language plpgsql stable security definer set search_path = public as $$
declare v_oid uuid;
begin
  foreach v_oid in array p_office_ids loop
    if not has_childcare_office_access(v_oid) then raise exception 'not authorized for office %', v_oid; end if;
  end loop;
  return query
  with elim_children as (
    select u.oid as office_id, el.child_id, cce.class_id, s.current_stage
    from unnest(p_office_ids) as u(oid)
    cross join lateral fetch_daily_elimination_for_office(u.oid, p_business_date) el
    join child_class_enrollments cce on cce.child_id = el.child_id and cce.effective_end_date is null
    cross join lateral fetch_child_meal_status_internal(el.child_id) s
    where el.handling = 'elimination'
  ),
  elim_per_row as (
    select rd.office_id, rd.row_key, count(ec.child_id)::int as cnt
    from meal_row_definitions rd
    left join elim_children ec
      on ec.office_id = rd.office_id and ec.class_id = rd.class_id
         and (rd.meal_stage is null or rd.meal_stage = ec.current_stage)
    where rd.office_id = any(p_office_ids) and rd.is_active and rd.row_type = 'children'
    group by rd.office_id, rd.row_key
  )
  select o.id, o.name, o.office_code,
         rd.row_key, rd.row_label, rd.row_type, rd.sort_order,
         mr.meal_slot, mr.child_count, mr.staff_count, coalesce(epr.cnt, 0) as allergy_count
  from offices o
  join meal_row_definitions rd on rd.office_id = o.id and rd.is_active
  join meal_count_rows mr on mr.office_id = rd.office_id and mr.row_key = rd.row_key and mr.business_date = p_business_date
  left join elim_per_row epr on epr.office_id = rd.office_id and epr.row_key = rd.row_key
  where o.id = any(p_office_ids)
  order by
    case o.office_code when 'O' then 1 when 'M' then 2 when 'S' then 3 when 'H' then 4 else 9 end,
    rd.sort_order,
    case mr.meal_slot when 'am_snack' then 1 when 'lunch' then 2 else 3 end;
end $$;
grant execute on function fetch_meal_board_crossoffice(uuid[], date) to authenticated, service_role;
