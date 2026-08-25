-- 327: バグ修正。重要事項説明書の同意カードが同意後も消えない(俊指示 2026-08-25)。
-- 原因: submit_important_matters_consent は household = coalesce(子の世帯, 同意者=保護者の世帯) で保存するのに、
--   fetch_active_important_matters(312)は「子の世帯」だけで照合していた。子の household_id が NULL(段階移行)だと
--   照合が外れ consented=false のままになる。
-- 修正: fetch も submit と同じ world 解決(coalesce(子の世帯, 閲覧中の保護者の世帯))で照合する。
create or replace function fetch_active_important_matters(p_child_id uuid)
returns table (id uuid, title text, fiscal_year int, version int, storage_path text, published_at timestamptz,
               consented boolean, agreed_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare v_office uuid; v_household uuid;
begin
  if not guardian_has_child_access(p_child_id) then raise exception 'not authorized'; end if;
  -- 世帯単位。子の世帯→無ければ閲覧中の保護者の世帯(submitと同一ロジック)。
  select ch.office_id, coalesce(ch.household_id, g.household_id)
    into v_office, v_household
    from children ch
    left join guardians g on g.id = my_guardian_id()
    where ch.id = p_child_id;
  return query
    select d.id, d.title, d.fiscal_year, d.version, d.storage_path, d.published_at,
           (c.id is not null), c.agreed_at
    from important_matters_documents d
    left join important_matters_consents c on c.document_id = d.id and c.household_id = v_household
    where d.office_id = v_office and d.is_published
    order by d.fiscal_year desc, d.version desc
    limit 1;
end $$;
grant execute on function fetch_active_important_matters(uuid) to authenticated, service_role;
