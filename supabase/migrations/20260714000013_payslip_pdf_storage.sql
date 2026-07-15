-- 17.2/18章 給与明細PDF発行。
--
-- PDF自体の生成は管理者Web(Next.js)側のRoute Handlerで行い(pdfkit)、
-- 生成物をSupabase Storageの'payslips'バケットへ保存、payslips.file_pathを更新する。
-- ファイルパスは{employee_id}/{payroll_run_id}.pdfとし、将来の職員本人向け配信
-- (18章「明細PDFを職員アプリの個人ポストへ配信」)にそのまま使えるようSELECTポリシーを
-- 本人にも許可しておく(今回のスコープは管理者Webからのダウンロードのみ)。

insert into storage.buckets (id, name, public)
values ('payslips', 'payslips', false)
on conflict (id) do nothing;

create policy payslips_storage_insert on storage.objects
  for insert with check (bucket_id = 'payslips' and is_labor_manager_plus());

create policy payslips_storage_update on storage.objects
  for update using (bucket_id = 'payslips' and is_labor_manager_plus());

create policy payslips_storage_select on storage.objects
  for select using (
    bucket_id = 'payslips'
    and (
      is_labor_manager_plus()
      or (storage.foldername(name))[1] = my_employee_id()::text
    )
  );

-- 17.2: 給与確定済み(confirmed/transferred)の月のみPDF発行可能。生成完了後にfile_pathを記録する。
create or replace function mark_payslip_generated(
  p_payroll_run_id uuid,
  p_employee_id uuid,
  p_file_path text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status payroll_run_status;
begin
  if not is_labor_manager_plus() then
    raise exception 'not authorized';
  end if;

  select status into v_status from payroll_runs where id = p_payroll_run_id;
  if v_status is null then
    raise exception 'payroll run not found';
  end if;
  if v_status = 'draft' then
    raise exception '給与確定前の対象月は給与明細PDFを発行できません(17.2)';
  end if;

  update payslips
  set file_path = p_file_path, generated_at = now()
  where payroll_run_id = p_payroll_run_id and employee_id = p_employee_id;

  if not found then
    insert into payslips (payroll_run_id, employee_id, file_path, generated_at)
    values (p_payroll_run_id, p_employee_id, p_file_path, now());
  end if;
end;
$$;
