-- 226: fetch_child_food_progress の戻り型修正(sum()がnumericを返すため::bigintへキャスト。224のバグ修正・staging適用済)
create or replace function fetch_child_food_progress(p_child_id uuid)
returns table (
  stage text,
  required_total bigint,
  required_done bigint,
  symptom_count bigint
)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_office_id uuid;
begin
  select office_id into v_office_id from children where id = p_child_id;
  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;
  return query
  with v as (
    select id, food_checklist_versions.required_times from food_checklist_versions
    where status = 'published' order by version desc limit 1
  ),
  items as (
    select ci.stage as st, ci.food_item_id, coalesce(ci.alt_group, ci.food_item_id::text) as grp,
      ci.alt_group_rule, v.required_times
    from v join food_checklist_items ci on ci.version_id = v.id
    where ci.category = 'required'
  ),
  done_items as (
    select i.st, i.grp, i.food_item_id,
      (select count(*) filter (where r.result = 'ok') >= i.required_times
              or bool_or(r.result = 'ok' and r.multiple_confirmed)
       from child_food_records r
       where r.child_id = p_child_id and r.food_item_id = i.food_item_id) as is_done,
      (select count(*) from child_food_records r
       where r.child_id = p_child_id and r.food_item_id = i.food_item_id and r.result = 'symptom') as sym
    from items i
  ),
  grp_agg as (
    select st, grp,
      case when max(coalesce((select alt_group_rule from items i2 where i2.grp = done_items.grp limit 1), 'any')) = 'all'
        then bool_and(coalesce(is_done, false))
        else bool_or(coalesce(is_done, false))
      end as grp_done,
      sum(coalesce(sym, 0)) as sym_sum
    from done_items
    group by st, grp
  )
  select st, count(*), count(*) filter (where grp_done), coalesce(sum(sym_sum), 0)::bigint
  from grp_agg
  group by st
  order by array_position(array['初期','中期','後期','完了期'], st);
end;
$$;
