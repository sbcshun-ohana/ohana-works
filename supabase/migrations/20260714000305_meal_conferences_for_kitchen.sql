-- 305: 厨房向け 給食会議の読み取り(閲覧専用)。既存 fetch_meal_conferences_for_office は主任以上限定のため、
-- 厨房アカウント(has_childcare_office_access)が調理に必要な情報(対象児・除去/代替の提供方針・同意状況)を閲覧できる版。
-- 記録者や出席者などの内部情報は返さない(委託業者にも見せる前提の最小限)。
create or replace function fetch_meal_conferences_for_kitchen(p_office_id uuid)
returns table (id uuid, child_name text, held_on date, nutritionist_name text,
               elimination_plan text, status text, consent_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  return query
    select mc.id, c.display_name, mc.held_on, mc.nutritionist_name, mc.elimination_plan, mc.status,
           (select max(agreed_at) from meal_conference_consents where conference_id = mc.id)
    from meal_conferences mc join children c on c.id = mc.child_id
    where mc.office_id = p_office_id and mc.status <> 'cancelled'
    order by mc.created_at desc;
end $$;
grant execute on function fetch_meal_conferences_for_kitchen(uuid) to authenticated, service_role;
