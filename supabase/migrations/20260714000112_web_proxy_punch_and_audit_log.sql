-- 開発計画(改訂版 2026-07-17) Phase 1 / D: Web代理打刻(現在時刻)・監査ログ確認。
-- 「過去修正」は既存のcorrect_daily_attendance RPCで完結済みのため対象外。
-- proxy_punchesはこれまでキオスク(物理iPad, device_id必須)専用だったため、
-- Web(admin_web)発行の代理打刻を記録できるようdevice_idをnullable化し、
-- office_id列を新設する(office判定を device_id→devices.office_id 経由に限定しない)。
-- 既存4件はdevice_idからoffice_idをバックフィルする。grep調査の結果、device_idの
-- NOT NULL前提に依存するコードは他に存在しないことを確認済み(2026-07-21)。

alter table proxy_punches add column office_id uuid references offices(id);
alter table proxy_punches alter column device_id drop not null;

update proxy_punches pp
set office_id = d.office_id
from devices d
where pp.device_id = d.id and pp.office_id is null;

-- Web代理打刻(現在時刻)。record-punch.ts(Edge Function、キオスク向け)と同じ
-- time_punches/daily_attendances更新ロジックをSQL側に再実装する。
-- 管理者Webは既に認証済みセッションで呼ばれるため、キオスクのPIN照合は不要。
create or replace function record_web_proxy_punch(
  p_employee_id uuid,
  p_punch_type punch_type,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_home_office_id uuid;
  v_punched_at timestamptz := now();
  v_column text;
  v_payroll_status payroll_run_status;
  v_alert_rule_id uuid;
begin
  select home_office_id into v_home_office_id from employees where id = p_employee_id;
  if v_home_office_id is null or not manages_office(v_home_office_id) then
    raise exception 'not authorized to record proxy punch for this employee';
  end if;

  select status into v_payroll_status from payroll_runs
  where target_month = date_trunc('month', v_punched_at)::date;
  if v_payroll_status = 'transferred' then
    raise exception '振込実行済みの月の勤怠は編集できません(33章)';
  elsif v_payroll_status = 'confirmed' then
    raise exception '給与確定済みの月の勤怠は編集できません(17.4)';
  end if;

  insert into time_punches (employee_id, device_id, punch_type, punched_at, source, office_id)
  values (p_employee_id, null, p_punch_type, v_punched_at, 'proxy', v_home_office_id);

  v_column := case p_punch_type
    when 'clock_in' then 'actual_clock_in_at'
    when 'break_start' then 'actual_break_start_at'
    when 'break_end' then 'actual_break_end_at'
    when 'clock_out' then 'actual_clock_out_at'
  end;

  execute format(
    'insert into daily_attendances (employee_id, work_date, %1$I) values ($1, $2, $3)
     on conflict (employee_id, work_date) do update set %1$I = excluded.%1$I',
    v_column
  ) using p_employee_id, (v_punched_at at time zone 'Asia/Tokyo')::date, v_punched_at;

  insert into proxy_punches (employee_id, device_id, office_id, punch_type, punched_at, proxy_operator_id, note)
  values (p_employee_id, null, v_home_office_id, p_punch_type, v_punched_at, my_employee_id(), p_note);

  select id into v_alert_rule_id from alert_rules where alert_key = 'proxy_punch_used';
  if v_alert_rule_id is not null then
    insert into alerts (alert_rule_id, target_employee_id, target_office_id, context)
    values (
      v_alert_rule_id, p_employee_id, v_home_office_id,
      jsonb_build_object('proxy_operator_id', my_employee_id(), 'punch_type', p_punch_type, 'source', 'web')
    );
  end if;
end;
$$;

comment on function record_web_proxy_punch(uuid, punch_type, text) is
  'admin_web向けのWeb代理打刻(現在時刻のみ)。過去日時の修正はcorrect_daily_attendanceを使う。';

-- 代理打刻の監査ログ確認(施設単位、Web/キオスク両方をまとめて返す)。
create or replace function fetch_proxy_punches_for_office(
  p_office_id uuid,
  p_month_start date,
  p_month_end date
)
returns table (
  id uuid,
  employee_id uuid,
  employee_name text,
  punch_type text,
  punched_at timestamptz,
  proxy_operator_id uuid,
  proxy_operator_name text,
  source_label text,
  note text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not manages_office(p_office_id) then
    raise exception 'not authorized to view proxy punch log for this office';
  end if;

  return query
  select
    pp.id, pp.employee_id, e.name, pp.punch_type::text, pp.punched_at,
    pp.proxy_operator_id, op.name,
    case when pp.device_id is null then 'Web' else coalesce(d.device_code, 'キオスク') end,
    pp.note
  from proxy_punches pp
  join employees e on e.id = pp.employee_id
  join employees op on op.id = pp.proxy_operator_id
  left join devices d on d.id = pp.device_id
  where pp.office_id = p_office_id
    and pp.punched_at >= p_month_start
    and pp.punched_at < (p_month_end + 1)
  order by pp.punched_at desc;
end;
$$;
