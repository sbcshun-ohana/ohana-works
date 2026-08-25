-- 320: 指導計画タスクアラートに「月案の提出締切=毎月25日・翌月分」を反映(俊指示2026-08-25)。
-- 月Xの月案は「月X-1の25日」が締切(例: 8/25締切=9月分)。25日が土/日なら直前の金曜へ繰上げ。
-- 個人案(0-2歳+加配児)は月案提出に内包(submit_guidance_plan/294 が対象児の個人案未記入だと提出不可)ため、
--   月案アラートが個人案も包含する。
-- 主任以上のアラートバー: 当月Mの月案(締切=先月25日・既に過去)に加え、締切(繰上げ後)到来で翌月M+1の月案も要対応。
-- #variable_conflict use_column は319の修正を維持。signature 不変=create or replace。

-- 締切ヘルパー: 指定年月の提出締切日。基本は25日。25日が土曜→24日(金)、日曜→23日(金)へ繰上げ。平日はそのまま25日。
create or replace function guidance_monthly_deadline(p_year int, p_month int)
returns date language sql immutable set search_path = public as $$
  select case extract(dow from make_date(p_year, p_month, 25))
    when 6 then make_date(p_year, p_month, 25) - 1   -- 土 → 前日(金)24日
    when 0 then make_date(p_year, p_month, 25) - 2   -- 日 → 前々日(金)23日
    else make_date(p_year, p_month, 25)
  end;
$$;
grant execute on function guidance_monthly_deadline(int, int) to authenticated, service_role;

create or replace function fetch_guidance_plan_tasks_for_office(p_office_id uuid)
returns table (message text, level text, plan_type text, class_name text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_cat text; v_fiscal int; v_month int; v_week date; v_y int; cc record; v_status text;
  v_next_month int; v_next_fiscal int; v_deadline date;
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  if not is_guidance_plans_enabled_for_office(p_office_id) then return; end if;
  select office_category into v_cat from offices where id = p_office_id;
  v_y := extract(year from current_date)::int;
  v_month := extract(month from current_date)::int;
  v_fiscal := case when v_month >= 4 then v_y else v_y - 1 end;
  v_week := (date_trunc('week', current_date))::date;  -- 月曜
  -- 翌月(締切=今月25日で提出すべき月)。年度は3月→4月でのみ繰り上がる。締切は土日で金曜へ繰上げ。
  v_next_month := case when v_month = 12 then 1 else v_month + 1 end;
  v_next_fiscal := case when v_month = 3 then v_fiscal + 1 else v_fiscal end;
  v_deadline := guidance_monthly_deadline(v_y, v_month);

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

    -- 月案(当月・締切=先月25日で既に過去)。個人案(0-2歳+加配)は月案提出に内包。
    v_status := (select status from guidance_plans where office_id = p_office_id and class_id = cc.id and plan_type = 'monthly' and fiscal_year = v_fiscal and month = v_month limit 1);
    if coalesce(v_status, '') in ('', 'draft') then return query select cc.class_name || ' ' || v_month || '月の月案 未提出', 'action'::text, 'monthly'::text, cc.class_name;
    elsif v_status in ('submitted', 'chief_checked') then return query select cc.class_name || ' ' || v_month || '月の月案 承認待ち', 'info'::text, 'monthly'::text, cc.class_name; end if;

    -- 月案(翌月・締切=毎月25日/土日は前金曜)。締切到来後に未提出なら要対応(主任以上のバー)。
    if current_date >= v_deadline then
      v_status := (select status from guidance_plans where office_id = p_office_id and class_id = cc.id and plan_type = 'monthly' and fiscal_year = v_next_fiscal and month = v_next_month limit 1);
      if coalesce(v_status, '') in ('', 'draft') then return query select cc.class_name || ' ' || v_next_month || '月の月案 未提出(締切超過)', 'action'::text, 'monthly'::text, cc.class_name;
      elsif v_status in ('submitted', 'chief_checked') then return query select cc.class_name || ' ' || v_next_month || '月の月案 承認待ち', 'info'::text, 'monthly'::text, cc.class_name; end if;
    end if;

    -- 週案(企業主導型のみ・当週)
    if v_cat = 'corporate_led' then
      v_status := (select status from guidance_plans where office_id = p_office_id and class_id = cc.id and plan_type = 'weekly' and week_start_date = v_week limit 1);
      if coalesce(v_status, '') in ('', 'draft') then return query select cc.class_name || ' 今週の週案 未提出', 'action'::text, 'weekly'::text, cc.class_name;
      elsif v_status in ('submitted', 'chief_checked') then return query select cc.class_name || ' 今週の週案 承認待ち', 'info'::text, 'weekly'::text, cc.class_name; end if;
    end if;
  end loop;
end $$;
grant execute on function fetch_guidance_plan_tasks_for_office(uuid) to authenticated, service_role;
