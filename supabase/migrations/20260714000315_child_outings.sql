-- 315: 登降園 Phase C。一時外出の一般化(療育/健診/その他)。療育外出(therapy_outing_events)は既存のまま、
-- 健診・その他を含む汎用の一時外出を child_outings で管理。5ガード(§4)対応。ゲート=is_therapy_outing_enabled_for_office(既存流用)。
create table child_outings (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  office_id uuid not null references offices(id),
  business_date date not null,
  reason text not null check (reason in ('therapy', 'checkup', 'other')),  -- 療育/健診/その他
  reason_note text,
  out_at timestamptz not null default now(),
  return_planned_at timestamptz,          -- 戻り予定(ガード②必須)
  return_at timestamptz,                   -- 実際の戻り(null=外出中)
  converted_to_departure boolean not null default false,  -- 外出→降園変換(ガード⑤)
  started_by uuid references employees(id),
  ended_by uuid references employees(id),
  created_at timestamptz not null default now()
);
create index idx_child_outings_office_date on child_outings(office_id, business_date);
create index idx_child_outings_active on child_outings(child_id, business_date) where return_at is null;
alter table child_outings enable row level security;
create policy child_outings_select_staff on child_outings
  for select using (has_childcare_office_access(office_id));

do $$ begin
  execute format('create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();', 'child_outings');
end $$;

-- 外出開始(ガード①職員明示操作・②理由+戻り予定必須)。同日外出中が既にあれば拒否。
create or replace function start_child_outing(p_child_id uuid, p_reason text, p_reason_note text, p_return_planned_at timestamptz)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_id uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  if not is_therapy_outing_enabled_for_office(v_office) then raise exception 'outing disabled'; end if;
  if p_reason not in ('therapy','checkup','other') then raise exception 'invalid reason'; end if;
  if p_return_planned_at is null then raise exception '戻り予定時刻は必須です'; end if;
  if exists (select 1 from child_outings where child_id = p_child_id and business_date = current_date and return_at is null and not converted_to_departure) then
    raise exception '既に外出中です';
  end if;
  insert into child_outings (child_id, office_id, business_date, reason, reason_note, return_planned_at, started_by)
    values (p_child_id, v_office, current_date, p_reason, nullif(trim(coalesce(p_reason_note,'')),''), p_return_planned_at, my_employee_id())
    returning id into v_id;
  return v_id;
end $$;
grant execute on function start_child_outing(uuid, text, text, timestamptz) to authenticated, service_role;

-- 戻り(再入室)。外出を終了。
create or replace function end_child_outing(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from child_outings where id = p_id;
  if v_office is null then raise exception 'outing not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  update child_outings set return_at = now(), ended_by = my_employee_id()
    where id = p_id and return_at is null and not converted_to_departure;
end $$;
grant execute on function end_child_outing(uuid) to authenticated, service_role;

-- 外出→降園変換(ガード⑤・主任以上1操作)。外出を終了し、降園(pick_up)を記録。
create or replace function convert_outing_to_departure(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_child uuid;
begin
  select office_id, child_id into v_office, v_child from child_outings where id = p_id;
  if v_office is null then raise exception 'outing not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  update child_outings set return_at = now(), converted_to_departure = true, ended_by = my_employee_id()
    where id = p_id and return_at is null;
  -- 降園として記録(登降園実績に反映)。
  insert into child_attendance_events (child_id, event_type, occurred_at, recorded_by_employee_id, admin_override_reason)
    values (v_child, 'pick_up', now(), my_employee_id(), '一時外出→降園変換');
  perform refresh_daily_child_status(v_child, current_date);  -- デイリーボードの在園/降園表示を更新
end $$;
grant execute on function convert_outing_to_departure(uuid) to authenticated, service_role;

-- 外出一覧(指定日・施設)。外出中/戻り済、戻り予定超過(overdue)判定つき。デイリーボード・閉園時確認用。
create or replace function fetch_child_outings_for_office(p_office_id uuid, p_business_date date)
returns table (id uuid, child_id uuid, child_name text, class_name text, reason text, reason_note text,
               out_at timestamptz, return_planned_at timestamptz, return_at timestamptz,
               converted_to_departure boolean, is_active boolean, is_overdue boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  return query
    select o.id, o.child_id, c.display_name, cc.class_name, o.reason, o.reason_note,
           o.out_at, o.return_planned_at, o.return_at, o.converted_to_departure,
           (o.return_at is null and not o.converted_to_departure),
           (o.return_at is null and not o.converted_to_departure and o.return_planned_at is not null and o.return_planned_at < now())
    from child_outings o
    join children c on c.id = o.child_id
    left join child_class_enrollments cce on cce.child_id = c.id and cce.effective_end_date is null
    left join childcare_classes cc on cc.id = cce.class_id
    where o.office_id = p_office_id and o.business_date = p_business_date
    order by (o.return_at is null) desc, o.out_at;
end $$;
grant execute on function fetch_child_outings_for_office(uuid, date) to authenticated, service_role;
