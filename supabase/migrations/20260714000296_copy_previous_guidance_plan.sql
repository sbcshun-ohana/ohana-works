-- 296: 前回コピー。前月の月案/前週の週案/前年度の年間・全体・安全計画の本文を、今の下書きにコピーする。
-- 「書き写し」文化の置換(業務負担軽減)。下書きのみ対象。本文(content)をコピー、評価反省(evaluation)はコピーしない。
-- 月案は個人案(園児別)もコピー。前回が見つからなければエラー。

create or replace function copy_previous_guidance_plan(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_office uuid; v_class uuid; v_type text; v_year int; v_month int; v_week date; v_status text;
  v_cy int; v_cm int; v_pcy int; v_pcm int; v_pfiscal int; v_pmonth int; v_pweek date; v_prev uuid;
begin
  select office_id, class_id, plan_type, fiscal_year, month, week_start_date, status
    into v_office, v_class, v_type, v_year, v_month, v_week, v_status
    from guidance_plans where id = p_id;
  if v_office is null then raise exception 'not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  if v_status = 'approved' then raise exception '承認済みの計画にはコピーできません'; end if;

  if v_type = 'monthly' then
    v_cy := case when v_month >= 4 then v_year else v_year + 1 end; v_cm := v_month;
    if v_cm = 1 then v_pcm := 12; v_pcy := v_cy - 1; else v_pcm := v_cm - 1; v_pcy := v_cy; end if;
    v_pmonth := v_pcm; v_pfiscal := case when v_pcm >= 4 then v_pcy else v_pcy - 1 end;
    select id into v_prev from guidance_plans
      where office_id = v_office and class_id = v_class and plan_type = 'monthly'
        and fiscal_year = v_pfiscal and month = v_pmonth and id <> p_id limit 1;
  elsif v_type = 'weekly' then
    v_pweek := v_week - 7;
    select id into v_prev from guidance_plans
      where office_id = v_office and class_id = v_class and plan_type = 'weekly'
        and week_start_date = v_pweek and id <> p_id limit 1;
  elsif v_type = 'annual' then
    select id into v_prev from guidance_plans
      where office_id = v_office and class_id = v_class and plan_type = 'annual'
        and fiscal_year = v_year - 1 and id <> p_id limit 1;
  else  -- overall / safety(施設×年度)
    select id into v_prev from guidance_plans
      where office_id = v_office and plan_type = v_type
        and fiscal_year = v_year - 1 and id <> p_id limit 1;
  end if;

  if v_prev is null then raise exception '前回の計画が見つかりません(コピー元がありません)'; end if;

  update guidance_plans set content = (select content from guidance_plans where id = v_prev) where id = p_id;

  if v_type = 'monthly' then
    insert into guidance_plan_individual_entries (plan_id, child_id, content, created_by)
    select p_id, e.child_id, e.content, my_employee_id()
    from guidance_plan_individual_entries e where e.plan_id = v_prev
    on conflict (plan_id, child_id) do update set content = excluded.content, updated_at = now();
  end if;
end $$;
grant execute on function copy_previous_guidance_plan(uuid) to authenticated, service_role;
