-- 297: 前回の計画IDを返す(横並び参照用)。copy_previous_guidance_plan と同じ「前回」判定。
-- 参照(印刷ビューを別タブで開いて左右に並べる)に使う。承認状態は問わない。

create or replace function fetch_previous_guidance_plan_id(p_id uuid)
returns uuid language plpgsql stable security definer set search_path = public as $$
declare
  v_office uuid; v_class uuid; v_type text; v_year int; v_month int; v_week date;
  v_cy int; v_cm int; v_pcy int; v_pcm int; v_pfiscal int; v_pmonth int; v_pweek date; v_prev uuid;
begin
  select office_id, class_id, plan_type, fiscal_year, month, week_start_date
    into v_office, v_class, v_type, v_year, v_month, v_week from guidance_plans where id = p_id;
  if v_office is null then raise exception 'not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;

  if v_type = 'monthly' then
    v_cy := case when v_month >= 4 then v_year else v_year + 1 end; v_cm := v_month;
    if v_cm = 1 then v_pcm := 12; v_pcy := v_cy - 1; else v_pcm := v_cm - 1; v_pcy := v_cy; end if;
    v_pmonth := v_pcm; v_pfiscal := case when v_pcm >= 4 then v_pcy else v_pcy - 1 end;
    select id into v_prev from guidance_plans
      where office_id = v_office and class_id = v_class and plan_type = 'monthly'
        and fiscal_year = v_pfiscal and month = v_pmonth and id <> p_id limit 1;
  elsif v_type = 'weekly' then
    select id into v_prev from guidance_plans
      where office_id = v_office and class_id = v_class and plan_type = 'weekly'
        and week_start_date = v_week - 7 and id <> p_id limit 1;
  elsif v_type = 'annual' then
    select id into v_prev from guidance_plans
      where office_id = v_office and class_id = v_class and plan_type = 'annual'
        and fiscal_year = v_year - 1 and id <> p_id limit 1;
  else
    select id into v_prev from guidance_plans
      where office_id = v_office and plan_type = v_type and fiscal_year = v_year - 1 and id <> p_id limit 1;
  end if;
  return v_prev;
end $$;
grant execute on function fetch_previous_guidance_plan_id(uuid) to authenticated, service_role;
