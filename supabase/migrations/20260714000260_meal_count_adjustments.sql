-- 260: 給食管理。食数の事前調整(加算/減算)。俊確定2026-08-19。
-- 前日までに分かる「出欠に紐づかない食数の増減」(行事・来客・特別対応・スポット等)を事前登録し、
-- その日の自動算出に上乗せする。=当日の自動算出(出欠反映)+ 事前調整delta。当日再算出でも消えない。
-- 過去日の変更や当日の実測ズレは change_meal_row(期限内)を使う。事前調整は主に未来日で使う。

create table meal_count_adjustments (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id),
  business_date date not null,
  row_key text not null,
  meal_slot text not null check (meal_slot in ('am_snack', 'lunch', 'pm_snack')),
  field text not null check (field in ('child', 'staff')),
  delta int not null,          -- 加算(+) / 減算(-)
  note text,
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (office_id, business_date, row_key, meal_slot, field)
);
create index idx_meal_count_adjustments_office_date on meal_count_adjustments(office_id, business_date);
create trigger trg_meal_count_adjustments_updated_at
  before update on meal_count_adjustments for each row execute function set_updated_at();
alter table meal_count_adjustments enable row level security;
create policy meal_count_adjustments_select on meal_count_adjustments
  for select using (is_childcare_staff());
comment on table meal_count_adjustments is
  '食数の事前調整(260)。自動算出に上乗せする加算/減算。主に未来日の事前登録。算出エンジンが加算する。';

-- 算出エンジンを再定義: 事前調整deltaを加算(0未満はクランプ)。257からの差分は最終insertの左結合のみ。
create or replace function meal_compute_internal(p_office uuid, p_date date)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_staff int;
begin
  insert into meal_count_days (office_id, business_date, computed_at)
  values (p_office, p_date, now())
  on conflict (office_id, business_date) do update set computed_at = now();

  select count(*) into v_staff from (
    select sh.employee_id as emp
    from shifts sh
    where sh.office_id = p_office and sh.work_date = p_date and sh.status = 'confirmed'
      and sh.start_time <= time '11:00' and sh.end_time >= time '13:00'
      and not exists (
        select 1 from staff_meal_entries sme
        where sme.employee_id = sh.employee_id and sme.business_date = p_date and sme.will_eat = false
      )
    union
    select sme.employee_id
    from staff_meal_entries sme
    where sme.office_id = p_office and sme.business_date = p_date and sme.will_eat = true
  ) t;

  with attending as (
    select cce.class_id, s.meal_status, s.current_stage
    from children c
    join child_class_enrollments cce on cce.child_id = c.id and cce.effective_end_date is null
    cross join lateral fetch_child_meal_status_internal(c.id) s
    where c.office_id = p_office and c.enrollment_status = '在籍中'
      and not exists (
        select 1 from child_daily_attendance a
        where a.child_id = c.id and a.business_date = p_date and a.is_absent
      )
  ),
  row_counts as (
    select rd.row_key, rd.row_type, rd.am_snack, rd.lunch, rd.pm_snack,
      count(at.class_id) filter (where at.meal_status in ('通常食', '共通除去食')) as child_cnt
    from meal_row_definitions rd
    left join attending at
      on rd.row_type = 'children' and at.class_id = rd.class_id
         and (rd.meal_stage is null or rd.meal_stage = at.current_stage)
    where rd.office_id = p_office and rd.is_active
    group by rd.row_key, rd.row_type, rd.am_snack, rd.lunch, rd.pm_snack
  ),
  slots as (
    select rc.row_key, rc.row_type, rc.child_cnt, sl.slot
    from row_counts rc
    cross join lateral (values ('am_snack', rc.am_snack), ('lunch', rc.lunch), ('pm_snack', rc.pm_snack)) as sl(slot, enabled)
    where sl.enabled
  )
  insert into meal_count_rows (office_id, business_date, row_key, meal_slot, child_count, staff_count)
  select p_office, p_date, sl.row_key, sl.slot,
    greatest(0, (case when sl.row_type = 'children' then sl.child_cnt else 0 end) + coalesce(adj_c.delta, 0)),
    greatest(0, (case when sl.row_type = 'staff' and sl.slot = 'lunch' then v_staff else 0 end) + coalesce(adj_s.delta, 0))
  from slots sl
  left join meal_count_adjustments adj_c
    on adj_c.office_id = p_office and adj_c.business_date = p_date
       and adj_c.row_key = sl.row_key and adj_c.meal_slot = sl.slot and adj_c.field = 'child'
  left join meal_count_adjustments adj_s
    on adj_s.office_id = p_office and adj_s.business_date = p_date
       and adj_s.row_key = sl.row_key and adj_s.meal_slot = sl.slot and adj_s.field = 'staff'
  on conflict (office_id, business_date, row_key, meal_slot) do update
    set child_count = excluded.child_count, staff_count = excluded.staff_count, updated_at = now()
    where meal_count_rows.is_confirmed = false;
end;
$$;

-- 事前調整の登録/更新(delta=0で削除)。職員以上。登録後にその日の食数を再算出して即反映。
create or replace function set_meal_adjustment(
  p_office_id uuid, p_business_date date, p_row_key text, p_meal_slot text, p_field text, p_delta int, p_note text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  if p_field not in ('child', 'staff') then raise exception 'invalid field'; end if;
  if p_meal_slot not in ('am_snack', 'lunch', 'pm_snack') then raise exception 'invalid meal_slot'; end if;
  if not exists (select 1 from meal_row_definitions where office_id = p_office_id and row_key = p_row_key and is_active) then
    raise exception 'row not found';
  end if;

  if p_delta = 0 then
    delete from meal_count_adjustments
    where office_id = p_office_id and business_date = p_business_date
      and row_key = p_row_key and meal_slot = p_meal_slot and field = p_field;
  else
    insert into meal_count_adjustments
      (office_id, business_date, row_key, meal_slot, field, delta, note, created_by)
    values (p_office_id, p_business_date, p_row_key, p_meal_slot, p_field, p_delta, p_note, my_employee_id())
    on conflict (office_id, business_date, row_key, meal_slot, field) do update
      set delta = excluded.delta, note = excluded.note, created_by = excluded.created_by, updated_at = now();
  end if;

  -- 未確定の行に即反映(確定済みの行は保持)。
  perform meal_compute_internal(p_office_id, p_business_date);
end;
$$;
grant execute on function set_meal_adjustment(uuid, date, text, text, text, int, text) to authenticated, service_role;

-- 事前調整の一覧(行ラベル・登録者名付き)。
create or replace function fetch_meal_adjustments(p_office_id uuid, p_business_date date)
returns table (
  id uuid, row_key text, row_label text, meal_slot text, field text, delta int, note text,
  created_by_name text, updated_at timestamptz
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not is_childcare_staff() then raise exception 'not authorized'; end if;
  return query
  select a.id, a.row_key, rd.row_label, a.meal_slot, a.field, a.delta, a.note, e.name, a.updated_at
  from meal_count_adjustments a
  left join meal_row_definitions rd on rd.office_id = a.office_id and rd.row_key = a.row_key
  left join employees e on e.id = a.created_by
  where a.office_id = p_office_id and a.business_date = p_business_date
  order by rd.sort_order, a.meal_slot;
end;
$$;
grant execute on function fetch_meal_adjustments(uuid, date) to authenticated, service_role;
