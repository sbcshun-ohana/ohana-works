-- 309: 給食会議の記録内容(除去・代替の提供方針=話し合われた内容)を管理者一覧でも後から確認できるように、
-- fetch_meal_conferences_for_office の返却に elimination_plan を追加。戻り値型変更のため drop→create。
-- 委託業者(厨房)側は fetch_meal_conferences_for_kitchen(305)で既に閲覧可。
drop function if exists fetch_meal_conferences_for_office(uuid, boolean);
create or replace function fetch_meal_conferences_for_office(p_office_id uuid, p_only_unconsented boolean default false)
returns table (id uuid, child_id uuid, child_name text, held_on date, nutritionist_name text,
               elimination_plan text, status text, created_at timestamptz, consent_at timestamptz, attendee_names text[])
language plpgsql security definer set search_path = public as $$
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  return query
    select mc.id, mc.child_id, c.display_name, mc.held_on, mc.nutritionist_name, mc.elimination_plan,
           mc.status, mc.created_at,
           (select max(agreed_at) from meal_conference_consents where conference_id = mc.id),
           (select array_agg(ae.name order by ae.name) from employees ae
            where ae.id = any(mc.attendee_employee_ids))
    from meal_conferences mc join children c on c.id = mc.child_id
    where mc.office_id = p_office_id and mc.status <> 'cancelled'
      and (not p_only_unconsented or mc.status = 'held')
    order by mc.created_at desc;
end $$;
grant execute on function fetch_meal_conferences_for_office(uuid, boolean) to authenticated, service_role;
