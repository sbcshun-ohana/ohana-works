-- 379: 登降園 — 帳票出力の監査ログ(本案§7「出力監査」)。
--   PDF/CSV/Excel をダウンロードした事実を記録: 誰が・いつ・どの施設の・どの帳票を・何件出したか。
--   記録=主任以上(manages_childcare)。閲覧=施設管理者以上(is_childcare_admin)。
--   直接アクセスは付与せず、RPC(security definer)経由に統一(既存踏襲)。
create table if not exists report_output_logs (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id),
  report_type text not null,     -- 'attendance_register'(出席簿) / 'attendance_actuals'(登降園実績表) 等
  format text not null check (format in ('pdf', 'csv', 'xlsx')),
  params jsonb not null default '{}'::jsonb,   -- 年月・対象園児等の出力条件
  row_count int,                 -- 出力件数(任意)
  output_by uuid references employees(id),
  output_at timestamptz not null default now()
);
create index if not exists idx_report_output_logs_office_at on report_output_logs (office_id, output_at desc);

alter table report_output_logs enable row level security;
-- RLSは有効化のみ(ポリシー無し=直接selectは不可)。アクセスは下記RPC経由。

-- 出力記録(DL成功後にクライアントが呼ぶ)。主任以上のみ。
create or replace function log_report_output(
  p_office_id uuid,
  p_report_type text,
  p_format text,
  p_params jsonb default '{}'::jsonb,
  p_row_count int default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if p_office_id is null then raise exception 'office required'; end if;
  if p_report_type is null or p_format is null then raise exception 'report_type/format required'; end if;
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  insert into report_output_logs (office_id, report_type, format, params, row_count, output_by)
  values (p_office_id, p_report_type, p_format, coalesce(p_params, '{}'::jsonb), p_row_count, my_employee_id())
  returning id into v_id;
  return v_id;
end $$;
grant execute on function log_report_output(uuid, text, text, jsonb, int) to authenticated, service_role;

-- 出力履歴の閲覧。施設管理者以上(主任=chief は不可)。
create or replace function fetch_report_output_logs(p_office_id uuid, p_limit int default 100)
returns table (output_at timestamptz, operator text, report_type text, format text, params jsonb, row_count int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_childcare_admin(p_office_id) then raise exception 'not authorized'; end if;
  return query
  select l.output_at, coalesce(e.name, '—') as operator, l.report_type, l.format, l.params, l.row_count
  from report_output_logs l
  left join employees e on e.id = l.output_by
  where l.office_id = p_office_id
  order by l.output_at desc
  limit greatest(1, least(coalesce(p_limit, 100), 500));
end $$;
grant execute on function fetch_report_output_logs(uuid, int) to authenticated, service_role;
