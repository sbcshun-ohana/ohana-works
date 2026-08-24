-- 302: fetch_meal_photos_for_office のバグ修正。employees の氏名列は display_name ではなく name。
-- (300で ue.display_name/ae.display_name と誤記 → "column ue.display_name does not exist")
create or replace function fetch_meal_photos_for_office(p_office_id uuid, p_business_date date)
returns table (id uuid, storage_path text, caption text, status text, rejected_reason text,
               uploaded_by_name text, approved_by_name text, approved_at timestamptz, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  return query
    select mp.id, mp.storage_path, mp.caption, mp.status, mp.rejected_reason,
           ue.name, ae.name, mp.approved_at, mp.created_at
    from meal_photos mp
    left join employees ue on ue.id = mp.uploaded_by
    left join employees ae on ae.id = mp.approved_by
    where mp.office_id = p_office_id and mp.business_date = p_business_date
    order by mp.created_at;
end $$;
grant execute on function fetch_meal_photos_for_office(uuid, date) to authenticated, service_role;
