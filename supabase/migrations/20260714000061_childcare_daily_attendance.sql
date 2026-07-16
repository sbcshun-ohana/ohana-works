-- 保育業務 Phase1: 当日の欠席選択
-- 在籍園児一覧から欠席チェック。複数端末への即時反映は
-- 20260714000069(Realtime publication)で対応する。

create table child_daily_attendance (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  business_date date not null,
  is_absent boolean not null default false,
  absence_reason text,
  changed_by uuid references employees(id),
  changed_at timestamptz not null default now(),
  unique (child_id, business_date)
);
create index idx_child_daily_attendance_business_date on child_daily_attendance(business_date);

alter table child_daily_attendance enable row level security;
create policy child_daily_attendance_select_scoped on child_daily_attendance
  for select using (
    exists (
      select 1 from children c
      where c.id = child_daily_attendance.child_id and has_childcare_office_access(c.office_id)
    )
  );
create policy child_daily_attendance_write_scoped on child_daily_attendance
  for all using (
    exists (
      select 1 from children c
      where c.id = child_daily_attendance.child_id and has_childcare_office_access(c.office_id)
    )
  ) with check (
    exists (
      select 1 from children c
      where c.id = child_daily_attendance.child_id and has_childcare_office_access(c.office_id)
    )
  );

-- 欠席チェックのトグル。担当施設の職員であれば誰でも操作可。変更者・時刻を記録し、
-- 出席へ戻すと当日の連絡帳作成対象へ復帰する(child_daily_contacts等はis_absentを都度参照する)。
create or replace function set_child_daily_attendance(
  p_child_id uuid,
  p_business_date date,
  p_is_absent boolean,
  p_absence_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_office_id uuid;
begin
  select office_id into v_office_id from children where id = p_child_id;
  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  insert into child_daily_attendance (child_id, business_date, is_absent, absence_reason, changed_by, changed_at)
  values (
    p_child_id, p_business_date, p_is_absent,
    case when p_is_absent then p_absence_reason else null end,
    my_employee_id(), now()
  )
  on conflict (child_id, business_date)
  do update set
    is_absent = excluded.is_absent,
    absence_reason = excluded.absence_reason,
    changed_by = excluded.changed_by,
    changed_at = excluded.changed_at;
end;
$$;

do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'child_daily_attendance'
  );
end $$;
