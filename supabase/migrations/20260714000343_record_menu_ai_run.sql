-- 343: 献立取込AIの実行を ai_runs に記録(献立管理 AC-08「取込がai_runsに記録される」)。
--   analyze-menu-import(Edge Function)が解析後に本RPCを呼び、ai_runs に1件記録して
--   menu_imports.ai_run_id へ紐付ける。provider/model/prompt_version/出力を保存(モデル/様式変更の監査)。
--   ※システムの実標準はAnthropic直呼び(ai_runs.provider既定=anthropic)。OpenRouterは使用しない。
create or replace function record_menu_ai_run(
  p_import_id uuid, p_provider text, p_model text, p_prompt_version text,
  p_output text, p_input jsonb default '{}'::jsonb
)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_run uuid;
begin
  select office_id into v_office from menu_imports where id = p_import_id;
  if v_office is null then raise exception 'menu import not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;

  insert into ai_runs (document_type, document_id, target_field, input_data, provider, model, prompt_version, output_text, executed_by)
  values ('menu_import', p_import_id, 'menu', coalesce(p_input, '{}'::jsonb),
          coalesce(nullif(p_provider, ''), 'anthropic'), p_model, p_prompt_version, p_output, my_employee_id())
  returning id into v_run;

  update menu_imports set ai_run_id = v_run where id = p_import_id;
  return v_run;
end $$;
grant execute on function record_menu_ai_run(uuid, text, text, text, text, jsonb) to authenticated, service_role;
