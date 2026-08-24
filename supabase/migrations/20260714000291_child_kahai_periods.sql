-- 291: 加配(個人案対象)を期間指定+履歴で管理。俊指示(2026-08-24)。
-- 加配になる期間・外れる期間が生じるため、期間(start/end)を履歴として複数残す。
-- 個人案の対象判定は「その月案の月に加配期間が重なるか」で行う(290の boolean 判定を置換)。

create table child_kahai_periods (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  office_id uuid not null references offices(id) on delete cascade,
  start_date date not null,
  end_date date,                    -- null = 継続中(無期限)
  note text,
  created_by uuid references employees(id),
  created_at timestamptz not null default now()
);
create index idx_child_kahai_child on child_kahai_periods(child_id, start_date desc);
alter table child_kahai_periods enable row level security;
comment on table child_kahai_periods is '加配(個人案対象)の適用期間・履歴(291)。end_date null=継続中。個人案対象は月と期間の重なりで判定。';

create or replace function add_child_kahai_period(p_child_id uuid, p_start date, p_end date, p_note text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_id uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  if p_start is null then raise exception '開始日を入力してください'; end if;
  if p_end is not null and p_end < p_start then raise exception '終了日は開始日以降にしてください'; end if;
  insert into child_kahai_periods (child_id, office_id, start_date, end_date, note, created_by)
  values (p_child_id, v_office, p_start, p_end, p_note, my_employee_id()) returning id into v_id;
  return v_id;
end $$;
grant execute on function add_child_kahai_period(uuid, date, date, text) to authenticated, service_role;

create or replace function update_child_kahai_period(p_id uuid, p_start date, p_end date, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from child_kahai_periods where id = p_id;
  if v_office is null then raise exception 'not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  if p_start is null then raise exception '開始日を入力してください'; end if;
  if p_end is not null and p_end < p_start then raise exception '終了日は開始日以降にしてください'; end if;
  update child_kahai_periods set start_date = p_start, end_date = p_end, note = p_note where id = p_id;
end $$;
grant execute on function update_child_kahai_period(uuid, date, date, text) to authenticated, service_role;

create or replace function delete_child_kahai_period(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from child_kahai_periods where id = p_id;
  if v_office is null then raise exception 'not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  delete from child_kahai_periods where id = p_id;
end $$;
grant execute on function delete_child_kahai_period(uuid) to authenticated, service_role;

create or replace function fetch_child_kahai_periods(p_child_id uuid)
returns table (id uuid, start_date date, end_date date, note text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  return query select k.id, k.start_date, k.end_date, k.note, k.created_at
    from child_kahai_periods k where k.child_id = p_child_id order by k.start_date desc;
end $$;
grant execute on function fetch_child_kahai_periods(uuid) to authenticated, service_role;

-- 基準日に加配が有効な園児(園児マスタのバッジ用)。
create or replace function fetch_children_kahai_active(p_office_id uuid, p_ref_date date)
returns table (child_id uuid)
language plpgsql stable security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  return query select distinct k.child_id from child_kahai_periods k
    where k.office_id = p_office_id and k.start_date <= p_ref_date
      and (k.end_date is null or k.end_date >= p_ref_date);
end $$;
grant execute on function fetch_children_kahai_active(uuid, date) to authenticated, service_role;

-- 個人案の対象児(月案): クラス0-2歳=全員、3-5歳=その月に加配期間が重なる児のみ。
create or replace function fetch_guidance_individual_targets(p_plan_id uuid)
returns table (child_id uuid, display_name text, is_kahai boolean)
language plpgsql stable security definer set search_path = public as $$
declare v_office uuid; v_class uuid; v_type text; v_age int; v_year int; v_month int; v_ms date; v_me date;
begin
  select gp.office_id, gp.class_id, gp.plan_type, gp.fiscal_year, gp.month
    into v_office, v_class, v_type, v_year, v_month from guidance_plans gp where gp.id = p_plan_id;
  if v_office is null then raise exception 'not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  if v_type <> 'monthly' or v_class is null then return; end if;
  select substring(cc.age_group from '(\d)歳')::int into v_age from childcare_classes cc where cc.id = v_class;
  -- 年度(4月始まり)からその月の暦上の年月範囲を求める。
  v_ms := make_date(case when coalesce(v_month,4) >= 4 then v_year else v_year + 1 end, coalesce(v_month,4), 1);
  v_me := (v_ms + interval '1 month - 1 day')::date;
  return query
    select c.id, c.display_name,
      exists (select 1 from child_kahai_periods k where k.child_id = c.id
              and k.start_date <= v_me and (k.end_date is null or k.end_date >= v_ms))
    from children c
    join child_class_enrollments cce on cce.child_id = c.id and cce.effective_end_date is null and cce.class_id = v_class
    where c.office_id = v_office and c.enrollment_status = '在籍中'
      and ( coalesce(v_age, 9) <= 2
            or exists (select 1 from child_kahai_periods k where k.child_id = c.id
                       and k.start_date <= v_me and (k.end_date is null or k.end_date >= v_ms)) )
    order by c.display_name;
end $$;
grant execute on function fetch_guidance_individual_targets(uuid) to authenticated, service_role;
