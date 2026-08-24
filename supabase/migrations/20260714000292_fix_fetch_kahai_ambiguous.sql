-- 292: fetch_child_kahai_periods の "column reference id is ambiguous" を解消。
-- RETURNS TABLE(id ...) の OUT列名がテーブル child_kahai_periods.id と衝突していた。
-- returns setof child_kahai_periods に変更(OUT列名の衝突が起きない)。戻り列は id/start_date/end_date/note 等を含む。

drop function if exists fetch_child_kahai_periods(uuid);
create or replace function fetch_child_kahai_periods(p_child_id uuid)
returns setof child_kahai_periods
language plpgsql stable security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  return query select * from child_kahai_periods where child_id = p_child_id order by start_date desc;
end $$;
grant execute on function fetch_child_kahai_periods(uuid) to authenticated, service_role;
