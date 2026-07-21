-- 開発計画(改訂版 2026-07-17) Phase 1 / C: シフト機能(週次テンプレート+
-- イレギュラー例外)。C-1で調査した既存4テーブルのうち、fixed_shift_patterns は
-- employee_number_raw/source_import_id がNOT NULLでCSV取込専用のステージング設計
-- (職員ID未解決の行を許容する代わりにCSVバッチを常に要求する)だったため、手入力の
-- 直接編集には使えないと判断し、この2テーブルは新設する。shift_change_requests系
-- 3テーブル(交代相手指名・承認制)は今回の要件(役職者が直接編集するのみ)には
-- 該当しないため使用しない。
--
-- 権限は既存のmanages_office()をそのまま流用する(主任/園長/園管理者は既に
-- 対象ロールに含まれているため新規権限区分は不要、2026-07-21確認済み)。
--
-- shiftsは既存の実データテーブル(payroll/勤怠集計エンジンがstatus='confirmed'を
-- 参照)。週次テンプレート・例外はこのshiftsを生成するための入力層と位置づける。

-- shiftsに(employee_id, work_date)のUNIQUE制約を追加(現状無く、生成時のupsertが
-- 安全にできないため)。本番0件のため制約違反の心配は無い。
alter table shifts add constraint shifts_employee_work_date_key unique (employee_id, work_date);

-- source_pattern_idの参照先を、新設するshift_weekly_templatesに差し替える
-- (fixed_shift_patternsは今回使わないため)。
alter table shifts drop constraint shifts_source_pattern_id_fkey;

create table shift_weekly_templates (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id),
  office_id uuid not null references offices(id),
  weekday int not null check (weekday between 0 and 6), -- 0=月曜 〜 6=日曜
  start_time time not null,
  end_time time not null,
  break_minutes int not null default 0,
  created_by uuid references employees(id),
  updated_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (employee_id, weekday)
);

alter table shifts add constraint shifts_source_pattern_id_fkey
  foreign key (source_pattern_id) references shift_weekly_templates(id);

create table shift_exceptions (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id),
  work_date date not null,
  is_day_off boolean not null default false,
  office_id uuid references offices(id),
  start_time time,
  end_time time,
  break_minutes int,
  note text,
  created_by uuid references employees(id),
  updated_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (employee_id, work_date),
  check (is_day_off or (start_time is not null and end_time is not null))
);

alter table shift_weekly_templates enable row level security;
create policy shift_weekly_templates_select on shift_weekly_templates
  for select using (employee_id = my_employee_id() or manages_office(office_id));

alter table shift_exceptions enable row level security;
create policy shift_exceptions_select on shift_exceptions
  for select using (
    employee_id = my_employee_id()
    or (office_id is not null and manages_office(office_id))
    or exists (select 1 from employees e where e.id = shift_exceptions.employee_id and manages_office(e.home_office_id))
  );

create trigger trg_audit_shift_weekly_templates
  after insert or update or delete on shift_weekly_templates
  for each row execute function log_event_change();
create trigger trg_audit_shift_exceptions
  after insert or update or delete on shift_exceptions
  for each row execute function log_event_change();

-- 書き込みはRPC経由のみ(直接テーブル書き込みのRLS write policyは設けない、
-- 既存のfeature_flag_office_overrides等と同じ慣習)。

create or replace function upsert_shift_weekly_template(
  p_employee_id uuid, p_office_id uuid, p_weekday int,
  p_start_time time, p_end_time time, p_break_minutes int default 0
)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not manages_office(p_office_id) then
    raise exception 'not authorized';
  end if;
  insert into shift_weekly_templates (employee_id, office_id, weekday, start_time, end_time, break_minutes, created_by, updated_by)
  values (p_employee_id, p_office_id, p_weekday, p_start_time, p_end_time, p_break_minutes, my_employee_id(), my_employee_id())
  on conflict (employee_id, weekday) do update
    set office_id = excluded.office_id, start_time = excluded.start_time, end_time = excluded.end_time,
        break_minutes = excluded.break_minutes, updated_by = my_employee_id(), updated_at = now();
end;
$$;

create or replace function delete_shift_weekly_template(p_employee_id uuid, p_weekday int)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
begin
  select office_id into v_office_id from shift_weekly_templates where employee_id = p_employee_id and weekday = p_weekday;
  if v_office_id is null or not manages_office(v_office_id) then
    raise exception 'not authorized';
  end if;
  delete from shift_weekly_templates where employee_id = p_employee_id and weekday = p_weekday;
end;
$$;

create or replace function upsert_shift_exception(
  p_employee_id uuid, p_work_date date, p_is_day_off boolean, p_office_id uuid default null,
  p_start_time time default null, p_end_time time default null, p_break_minutes int default null,
  p_note text default null
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_home_office_id uuid;
begin
  select home_office_id into v_home_office_id from employees where id = p_employee_id;
  if v_home_office_id is null or not manages_office(coalesce(p_office_id, v_home_office_id)) then
    raise exception 'not authorized';
  end if;
  if not p_is_day_off and (p_start_time is null or p_end_time is null) then
    raise exception 'start_time/end_time are required unless is_day_off';
  end if;

  insert into shift_exceptions (employee_id, work_date, is_day_off, office_id, start_time, end_time, break_minutes, note, created_by, updated_by)
  values (p_employee_id, p_work_date, p_is_day_off, p_office_id, p_start_time, p_end_time, p_break_minutes, p_note, my_employee_id(), my_employee_id())
  on conflict (employee_id, work_date) do update
    set is_day_off = excluded.is_day_off, office_id = excluded.office_id, start_time = excluded.start_time,
        end_time = excluded.end_time, break_minutes = excluded.break_minutes, note = excluded.note,
        updated_by = my_employee_id(), updated_at = now();
end;
$$;

create or replace function delete_shift_exception(p_employee_id uuid, p_work_date date)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_home_office_id uuid;
begin
  select home_office_id into v_home_office_id from employees where id = p_employee_id;
  if v_home_office_id is null or not manages_office(v_home_office_id) then
    raise exception 'not authorized';
  end if;
  delete from shift_exceptions where employee_id = p_employee_id and work_date = p_work_date;
end;
$$;

create or replace function fetch_shift_weekly_template(p_employee_id uuid)
returns setof shift_weekly_templates
language sql stable security definer set search_path = public
as $$
  select * from shift_weekly_templates
  where employee_id = p_employee_id
    and (employee_id = my_employee_id() or exists (
      select 1 from employees e where e.id = p_employee_id and manages_office(e.home_office_id)
    ))
  order by weekday;
$$;

create or replace function fetch_shift_exceptions(p_employee_id uuid, p_month_start date, p_month_end date)
returns setof shift_exceptions
language sql stable security definer set search_path = public
as $$
  select * from shift_exceptions
  where employee_id = p_employee_id
    and work_date between p_month_start and p_month_end
    and (employee_id = my_employee_id() or exists (
      select 1 from employees e where e.id = p_employee_id and manages_office(e.home_office_id)
    ))
  order by work_date;
$$;

-- 週次テンプレート+例外から、指定期間のshiftsを生成(確定状態で書き込む)。
-- 例外(休み)→その日はスキップ(既存shifts行があれば削除)。
-- 例外(時刻あり)→その内容でupsert。例外なし→曜日テンプレートがあればupsert、無ければスキップ。
create or replace function generate_shifts_from_template(p_employee_id uuid, p_month_start date, p_month_end date)
returns int
language plpgsql security definer set search_path = public
as $$
declare
  v_home_office_id uuid;
  v_date date;
  v_weekday int;
  v_exception shift_exceptions%rowtype;
  v_template shift_weekly_templates%rowtype;
  v_generated_count int := 0;
begin
  select home_office_id into v_home_office_id from employees where id = p_employee_id;
  if v_home_office_id is null or not manages_office(v_home_office_id) then
    raise exception 'not authorized';
  end if;

  v_date := p_month_start;
  while v_date <= p_month_end loop
    -- PostgreSQLのextract(dow)は0=日曜〜6=土曜のため、0=月曜〜6=日曜に変換する
    v_weekday := (extract(dow from v_date)::int + 6) % 7;

    select * into v_exception from shift_exceptions
      where employee_id = p_employee_id and work_date = v_date;

    if found and v_exception.is_day_off then
      delete from shifts where employee_id = p_employee_id and work_date = v_date;
    elsif found then
      insert into shifts (employee_id, work_date, office_id, start_time, end_time, break_minutes, status)
      values (p_employee_id, v_date, coalesce(v_exception.office_id, v_home_office_id),
              v_exception.start_time, v_exception.end_time, coalesce(v_exception.break_minutes, 0), 'confirmed')
      on conflict (employee_id, work_date) do update
        set office_id = excluded.office_id, start_time = excluded.start_time, end_time = excluded.end_time,
            break_minutes = excluded.break_minutes, status = 'confirmed', source_pattern_id = null, updated_at = now();
      v_generated_count := v_generated_count + 1;
    else
      select * into v_template from shift_weekly_templates
        where employee_id = p_employee_id and weekday = v_weekday;
      if found then
        insert into shifts (employee_id, work_date, office_id, start_time, end_time, break_minutes, status, source_pattern_id)
        values (p_employee_id, v_date, v_template.office_id, v_template.start_time, v_template.end_time,
                v_template.break_minutes, 'confirmed', v_template.id)
        on conflict (employee_id, work_date) do update
          set office_id = excluded.office_id, start_time = excluded.start_time, end_time = excluded.end_time,
              break_minutes = excluded.break_minutes, status = 'confirmed', source_pattern_id = excluded.source_pattern_id,
              updated_at = now();
        v_generated_count := v_generated_count + 1;
      end if;
    end if;

    v_date := v_date + 1;
  end loop;

  return v_generated_count;
end;
$$;
