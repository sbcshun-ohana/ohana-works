-- 269: 献立AI解析Edge Function用。取込ファイル1件の情報を返す(menu_imports はRLSで直接selectできないため)。
create or replace function fetch_menu_import(p_id uuid)
returns table (id uuid, office_id uuid, target_month date, format text, format_kind text,
               source_path text, source_filename text, status text)
language plpgsql stable security definer set search_path = public as $$
declare v_office uuid;
begin
  select menu_imports.office_id into v_office from menu_imports where menu_imports.id = p_id;
  if v_office is null then raise exception 'not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  return query
    select mi.id, mi.office_id, mi.target_month, mi.format, mi.format_kind, mi.source_path, mi.source_filename, mi.status
    from menu_imports mi where mi.id = p_id;
end $$;
grant execute on function fetch_menu_import(uuid) to authenticated, service_role;
