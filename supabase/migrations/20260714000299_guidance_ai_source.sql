-- 299: 指導計画 AI下書きのソース収集RPC。計画のクラス・期間から、連絡帳(園→保護者)・
-- クラス活動・家庭からの連絡・前回計画をまとめて返す。Edge Function generate-guidance-draft が
-- service role で呼び、Anthropic へ渡すプロンプト素材にする。権限=当該施設の職員(閲覧可)。
create or replace function fetch_guidance_ai_source(p_plan_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_office uuid; v_class uuid; v_type text; v_year int; v_month int; v_week date; v_template uuid;
  v_start date; v_end date; v_y int; v_class_name text; v_period text; v_prev uuid;
begin
  select office_id, class_id, plan_type, fiscal_year, month, week_start_date, template_id
    into v_office, v_class, v_type, v_year, v_month, v_week, v_template
  from guidance_plans where id = p_plan_id;
  if v_office is null then raise exception 'not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;

  -- 対象期間の算出(会計年度→暦の変換)。
  if v_type = 'monthly' then
    v_y := case when v_month >= 4 then v_year else v_year + 1 end;
    v_start := make_date(v_y, v_month, 1);
    v_end := (v_start + interval '1 month - 1 day')::date;
    v_period := v_month || '月';
  elsif v_type = 'weekly' then
    v_start := v_week; v_end := v_week + 6;
    v_period := to_char(v_week, 'MM/DD') || '〜';
  else -- annual / overall / safety
    v_start := make_date(v_year, 4, 1); v_end := make_date(v_year + 1, 3, 31);
    v_period := v_year || '年度';
  end if;

  if v_class is not null then
    select class_name into v_class_name from childcare_classes where id = v_class;
  end if;

  v_prev := fetch_previous_guidance_plan_id(p_plan_id);

  return jsonb_build_object(
    'plan_type', v_type,
    'class_name', coalesce(v_class_name, '園全体'),
    'period', v_period,
    'start_date', v_start,
    'end_date', v_end,
    'template_sections', (select sections from guidance_plan_templates where id = v_template),
    'previous_content', (select content from guidance_plans where id = v_prev),
    -- 連絡帳(園→保護者): 子どもの様子。主ソース。
    'contacts', (
      select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
        select cdc.business_date,
               ch.display_name as child,
               concat_ws(' / ', nullif(cdc.child_today_notes, ''), nullif(cdc.current_text, ''), nullif(cdc.free_notes, '')) as text
        from child_daily_contacts cdc
        join children ch on ch.id = cdc.child_id
        join child_class_enrollments cce on cce.child_id = ch.id and cce.class_id = v_class
          and cce.effective_start_date <= cdc.business_date
          and (cce.effective_end_date is null or cce.effective_end_date >= cdc.business_date)
        where v_class is not null
          and cdc.business_date between v_start and v_end
          and concat_ws('', cdc.child_today_notes, cdc.current_text, cdc.free_notes) <> ''
        order by cdc.business_date
        limit 400
      ) x
    ),
    -- クラス活動: クラス全体の活動。
    'activities', (
      select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
        select cda.business_date,
               concat_ws(' / ', nullif(cda.today_theme, ''), nullif(cda.activity_content, ''), nullif(cda.class_overview, '')) as text
        from class_daily_activities cda
        where cda.class_id = v_class
          and cda.business_date between v_start and v_end
          and concat_ws('', cda.today_theme, cda.activity_content, cda.class_overview) <> ''
        order by cda.business_date
        limit 200
      ) x
    ),
    -- 家庭からの連絡: 補助。
    'home', (
      select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
        select fdr.business_date, ch.display_name as child, fdr.home_notes as text
        from family_daily_reports fdr
        join children ch on ch.id = fdr.child_id
        join child_class_enrollments cce on cce.child_id = ch.id and cce.class_id = v_class
          and cce.effective_start_date <= fdr.business_date
          and (cce.effective_end_date is null or cce.effective_end_date >= fdr.business_date)
        where v_class is not null
          and fdr.business_date between v_start and v_end
          and coalesce(fdr.home_notes, '') <> ''
        order by fdr.business_date
        limit 400
      ) x
    )
  );
end $$;
grant execute on function fetch_guidance_ai_source(uuid) to authenticated, service_role;
