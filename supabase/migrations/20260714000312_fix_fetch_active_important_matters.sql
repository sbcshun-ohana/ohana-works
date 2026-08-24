-- 312: fetch_active_important_matters の "column reference id is ambiguous" 修正。
-- RETURNS TABLE の出力列 id と children.id の衝突。children の id を別名で修飾。
create or replace function fetch_active_important_matters(p_child_id uuid)
returns table (id uuid, title text, fiscal_year int, version int, storage_path text, published_at timestamptz,
               consented boolean, agreed_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare v_office uuid;
begin
  if not guardian_has_child_access(p_child_id) then raise exception 'not authorized'; end if;
  select ch.office_id into v_office from children ch where ch.id = p_child_id;
  return query
    select d.id, d.title, d.fiscal_year, d.version, d.storage_path, d.published_at,
           (c.id is not null), c.agreed_at
    from important_matters_documents d
    left join children ch2 on ch2.id = p_child_id
    left join important_matters_consents c on c.document_id = d.id and c.household_id = ch2.household_id
    where d.office_id = v_office and d.is_published
    order by d.fiscal_year desc, d.version desc
    limit 1;
end $$;
grant execute on function fetch_active_important_matters(uuid) to authenticated, service_role;
