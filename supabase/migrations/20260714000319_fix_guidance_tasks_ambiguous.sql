-- 319: バグ修正。fetch_guidance_plan_tasks_for_office(306)の実行時例外
--   `column reference "plan_type" is ambiguous (42702)` を解消する。
-- 原因: RETURNS TABLE の OUT列 plan_type / class_name が、本体の
--   `... where plan_type = 'overall'` 等(guidance_plans の列参照)と名前衝突していた。
-- 影響: この関数を呼ぶ fetch_childcare_alerts_for_office が、guidance_plans 有効な施設(大和ほか)で
--   常に例外を投げ、アラートバー全体が表示されない状態だった(クライアントがエラーを握りつぶしていたため発覚が遅れた)。
-- 修正: 関数先頭に #variable_conflict use_column を付与し、曖昧参照は常に列を優先する。
--   OUT列(plan_type/class_name)は return query のリテラルでのみ出力し、クエリ内で変数として読まないため安全。
-- signature 不変のため create or replace（drop不要）。ロジックは306と同一。
create or replace function fetch_guidance_plan_tasks_for_office(p_office_id uuid)
returns table (message text, level text, plan_type text, class_name text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_cat text; v_fiscal int; v_month int; v_week date; v_y int; cc record; v_status text;
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  if not is_guidance_plans_enabled_for_office(p_office_id) then return; end if;
  select office_category into v_cat from offices where id = p_office_id;
  v_y := extract(year from current_date)::int;
  v_month := extract(month from current_date)::int;
  v_fiscal := case when v_month >= 4 then v_y else v_y - 1 end;
  v_week := (date_trunc('week', current_date))::date;  -- 月曜

  -- 園単位: 全体的な計画
  v_status := (select status from guidance_plans where office_id = p_office_id and plan_type = 'overall' and fiscal_year = v_fiscal and class_id is null limit 1);
  if coalesce(v_status, '') in ('', 'draft') then return query select '全体的な計画 未提出'::text, 'action'::text, 'overall'::text, null::text;
  elsif v_status in ('submitted', 'chief_checked') then return query select '全体的な計画 承認待ち'::text, 'info'::text, 'overall'::text, null::text; end if;

  -- 園単位: 保育安全計画
  v_status := (select status from guidance_plans where office_id = p_office_id and plan_type = 'safety' and fiscal_year = v_fiscal and class_id is null limit 1);
  if coalesce(v_status, '') in ('', 'draft') then return query select '保育安全計画 未提出'::text, 'action'::text, 'safety'::text, null::text;
  elsif v_status in ('submitted', 'chief_checked') then return query select '保育安全計画 承認待ち'::text, 'info'::text, 'safety'::text, null::text; end if;

  -- クラス単位
  for cc in select id, class_name from childcare_classes where office_id = p_office_id and is_active order by class_name loop
    -- 年間指導計画
    v_status := (select status from guidance_plans where office_id = p_office_id and class_id = cc.id and plan_type = 'annual' and fiscal_year = v_fiscal limit 1);
    if coalesce(v_status, '') in ('', 'draft') then return query select cc.class_name || ' 年間指導計画 未提出', 'action'::text, 'annual'::text, cc.class_name;
    elsif v_status in ('submitted', 'chief_checked') then return query select cc.class_name || ' 年間指導計画 承認待ち', 'info'::text, 'annual'::text, cc.class_name; end if;

    -- 月案(当月)
    v_status := (select status from guidance_plans where office_id = p_office_id and class_id = cc.id and plan_type = 'monthly' and fiscal_year = v_fiscal and month = v_month limit 1);
    if coalesce(v_status, '') in ('', 'draft') then return query select cc.class_name || ' ' || v_month || '月の月案 未提出', 'action'::text, 'monthly'::text, cc.class_name;
    elsif v_status in ('submitted', 'chief_checked') then return query select cc.class_name || ' ' || v_month || '月の月案 承認待ち', 'info'::text, 'monthly'::text, cc.class_name; end if;

    -- 週案(企業主導型のみ・当週)
    if v_cat = 'corporate_led' then
      v_status := (select status from guidance_plans where office_id = p_office_id and class_id = cc.id and plan_type = 'weekly' and week_start_date = v_week limit 1);
      if coalesce(v_status, '') in ('', 'draft') then return query select cc.class_name || ' 今週の週案 未提出', 'action'::text, 'weekly'::text, cc.class_name;
      elsif v_status in ('submitted', 'chief_checked') then return query select cc.class_name || ' 今週の週案 承認待ち', 'info'::text, 'weekly'::text, cc.class_name; end if;
    end if;
  end loop;
end $$;
grant execute on function fetch_guidance_plan_tasks_for_office(uuid) to authenticated, service_role;
