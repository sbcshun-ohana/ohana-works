-- 324: 登降園管理の追加(俊指示 2026-08-25)。
--   ① 日別に備考欄(child_daily_attendance.note)+保存RPC。管理者/園長(主任以上)が自由記入。
--   ② 時刻付き月間・園児単位月間ビューのため、実績マトリクスに note を追加(drop→create・323のロジック+note)。
alter table child_daily_attendance add column if not exists note text;
comment on column child_daily_attendance.note is '登降園管理の備考(主任以上が記入・園児×日)。';

-- 備考の保存(主任以上)。is_absent 等は保持し note のみ upsert。空文字は NULL 化。
create or replace function set_child_attendance_note(p_child_id uuid, p_business_date date, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  insert into child_daily_attendance (child_id, business_date, is_absent, note, changed_by, changed_at)
    values (p_child_id, p_business_date, false, nullif(btrim(coalesce(p_note, '')), ''), my_employee_id(), now())
  on conflict (child_id, business_date) do update
    set note = nullif(btrim(coalesce(excluded.note, '')), ''), changed_by = my_employee_id(), changed_at = now();
end $$;
grant execute on function set_child_attendance_note(uuid, date, text) to authenticated, service_role;

-- マトリクスに note を追加(323と同一ロジック+note)。#variable_conflict use_column で child_id 曖昧回避。
drop function if exists fetch_attendance_matrix_for_office(uuid, date, date);
create function fetch_attendance_matrix_for_office(p_office_id uuid, p_start date, p_end date)
returns table (
  child_id uuid, child_name text, class_name text, business_date date,
  in_time time, out_time time, return_time time, depart_time time,
  is_absent boolean, absence_reason text, absence_kind text, note text
)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  return query
  with ev as (
    select e.child_id, (e.occurred_at at time zone 'Asia/Tokyo')::date as bd,
      min(e.occurred_at) filter (where e.event_type in ('drop_off','proxy_drop_off')) as in_ts,
      max(e.occurred_at) filter (where e.event_type in ('pick_up','proxy_pick_up'))   as depart_ts,
      max(e.occurred_at) filter (where e.event_type = 'out')    as out_ts,
      max(e.occurred_at) filter (where e.event_type = 'return') as ret_ts
    from child_attendance_events e
    join children c on c.id = e.child_id
    where c.office_id = p_office_id
      and (e.occurred_at at time zone 'Asia/Tokyo')::date between p_start and p_end
    group by e.child_id, (e.occurred_at at time zone 'Asia/Tokyo')::date
  ),
  ab as (
    select a.child_id, a.business_date as bd, a.is_absent, a.absence_reason, a.attendance_kind, a.note
    from child_daily_attendance a
    join children c on c.id = a.child_id
    where c.office_id = p_office_id and a.business_date between p_start and p_end
  ),
  days as (
    select ev.child_id, ev.bd from ev
    union
    select ab.child_id, ab.bd from ab
    union
    select c.id, p_start from children c
    where p_start = p_end and c.office_id = p_office_id and c.enrollment_status = '在籍中'
  )
  select c.id, c.display_name, cc.class_name, d.bd,
    (ev.in_ts     at time zone 'Asia/Tokyo')::time,
    (ev.out_ts    at time zone 'Asia/Tokyo')::time,
    (ev.ret_ts    at time zone 'Asia/Tokyo')::time,
    (ev.depart_ts at time zone 'Asia/Tokyo')::time,
    coalesce(ab.is_absent, false), ab.absence_reason, ab.attendance_kind, ab.note
  from days d
  join children c on c.id = d.child_id
  left join child_class_enrollments cce on cce.child_id = c.id and cce.effective_end_date is null
  left join childcare_classes cc on cc.id = cce.class_id
  left join ev on ev.child_id = d.child_id and ev.bd = d.bd
  left join ab on ab.child_id = d.child_id and ab.bd = d.bd
  where c.enrollment_status = '在籍中'
  -- クラスは年齢順(はな0歳→にじ5歳)、同クラス内は氏名順(display_name=かな部分はあいうえお順)。俊指示2026-08-25。
  order by substring(cc.age_group from '(\d)歳')::int nulls last, cc.class_name, c.display_name, d.bd;
end $$;
grant execute on function fetch_attendance_matrix_for_office(uuid, date, date) to authenticated, service_role;
