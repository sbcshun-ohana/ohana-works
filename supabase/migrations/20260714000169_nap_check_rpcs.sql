-- Phase 3 §3: 午睡チェックのRPC群。書き込みは security definer + 明示authz。
-- 権限(§3.5 確定): 当日かつ now-slot_at ≤ 30分 は施設/クラスアクセス保持者(一般職員可)、
-- 30分超・過去日は manages_childcare(主任以上)。source は timing から導出。

-- 共通: 記録authz。許可なら source を返す(realtime/late_entry/admin_edit)、不許可は raise。
create or replace function nap_check_authz(p_office uuid, p_class uuid, p_session_date date, p_slot_at timestamptz)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
  v_age_min numeric := extract(epoch from (now() - p_slot_at)) / 60;
begin
  if p_session_date < v_today or v_age_min > 30 then
    if not manages_childcare(p_office) then
      raise exception 'not authorized';
    end if;
    return 'admin_edit';
  end if;
  if not has_childcare_class_access(p_class) then
    raise exception 'not authorized';
  end if;
  return case when v_age_min < 5 then 'realtime' else 'late_entry' end;
end;
$$;

-- 入眠(個別)。園児の当日クラスからセッションを upsert。is_required はクラスの nap_check_required。
create or replace function start_nap_session(p_child_id uuid, p_sleep_start_at timestamptz)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_date date := (p_sleep_start_at at time zone 'Asia/Tokyo')::date;
  v_office uuid;
  v_class uuid;
  v_required boolean;
  v_id uuid;
begin
  select c.office_id, cce.class_id, cc.nap_check_required
    into v_office, v_class, v_required
  from children c
  join child_class_enrollments cce on cce.child_id = c.id
    and cce.effective_start_date <= v_date
    and (cce.effective_end_date is null or cce.effective_end_date >= v_date)
  join childcare_classes cc on cc.id = cce.class_id
  where c.id = p_child_id
  order by cce.effective_start_date desc
  limit 1;

  if v_office is null then
    raise exception 'child/class not found';
  end if;
  if not has_childcare_class_access(v_class) then
    raise exception 'not authorized';
  end if;

  insert into nap_sessions (child_id, office_id, class_id, session_date, sleep_start_at, is_required, added_by)
  values (p_child_id, v_office, v_class, v_date, p_sleep_start_at, v_required,
          case when v_required then null else my_employee_id() end)
  on conflict (child_id, session_date) do update set
    sleep_start_at = excluded.sleep_start_at,
    class_id = excluded.class_id,
    office_id = excluded.office_id
  returning id into v_id;
  return v_id;
end;
$$;

-- 入眠(クラス一括)。在籍園児全員のセッションを upsert(is_required=クラスの nap_check_required)。
create or replace function start_nap_sessions_for_class(p_class_id uuid, p_sleep_start_at timestamptz)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_date date := (p_sleep_start_at at time zone 'Asia/Tokyo')::date;
  v_office uuid;
  v_required boolean;
  v_count int;
begin
  if not has_childcare_class_access(p_class_id) then
    raise exception 'not authorized';
  end if;
  select office_id, nap_check_required into v_office, v_required
  from childcare_classes where id = p_class_id;
  if v_office is null then
    raise exception 'class not found';
  end if;

  insert into nap_sessions (child_id, office_id, class_id, session_date, sleep_start_at, is_required, added_by)
  select c.id, v_office, p_class_id, v_date, p_sleep_start_at, v_required,
         case when v_required then null else my_employee_id() end
  from children c
  join child_class_enrollments cce on cce.child_id = c.id
    and cce.effective_start_date <= v_date
    and (cce.effective_end_date is null or cce.effective_end_date >= v_date)
  where cce.class_id = p_class_id and c.enrollment_status <> '退園済み'
  on conflict (child_id, session_date) do update set sleep_start_at = excluded.sleep_start_at;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- 起床(個別)。
create or replace function end_nap_session(p_session_id uuid, p_wake_up_at timestamptz)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_office uuid; v_class uuid; v_date date;
begin
  select office_id, class_id, session_date into v_office, v_class, v_date
  from nap_sessions where id = p_session_id;
  if v_office is null then
    raise exception 'session not found';
  end if;
  if v_date < (now() at time zone 'Asia/Tokyo')::date then
    if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  elsif not has_childcare_class_access(v_class) then
    raise exception 'not authorized';
  end if;

  update nap_sessions set wake_up_at = p_wake_up_at where id = p_session_id;
end;
$$;

-- 起床(クラス一括)。当日の未起床セッションに起床時刻を設定。
create or replace function end_nap_sessions_for_class(p_class_id uuid, p_session_date date, p_wake_up_at timestamptz)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_count int;
begin
  if not has_childcare_class_access(p_class_id) then
    raise exception 'not authorized';
  end if;
  update nap_sessions set wake_up_at = p_wake_up_at
  where class_id = p_class_id and session_date = p_session_date and wake_up_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- 記録(4項目)。30分ルールで authz、source を導出して upsert。
create or replace function record_nap_check(
  p_session_id uuid,
  p_slot_at timestamptz,
  p_body_position text,
  p_breathing boolean,
  p_complexion boolean,
  p_bedding boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_office uuid; v_class uuid; v_date date; v_source text; v_id uuid;
begin
  select office_id, class_id, session_date into v_office, v_class, v_date
  from nap_sessions where id = p_session_id;
  if v_office is null then
    raise exception 'session not found';
  end if;
  v_source := nap_check_authz(v_office, v_class, v_date, p_slot_at);

  insert into nap_checks (session_id, slot_at, body_position, breathing_checked, complexion_checked,
                          bedding_checked, checked_by, checked_at, source)
  values (p_session_id, p_slot_at, p_body_position, p_breathing, p_complexion, p_bedding,
          my_employee_id(), now(), v_source)
  on conflict (session_id, slot_at) do update set
    body_position = excluded.body_position,
    breathing_checked = excluded.breathing_checked,
    complexion_checked = excluded.complexion_checked,
    bedding_checked = excluded.bedding_checked,
    checked_by = excluded.checked_by,
    checked_at = excluded.checked_at,
    source = excluded.source
  returning id into v_id;
  return v_id;
end;
$$;

-- 変化なし(個別): 5分前スロットと同内容を当該スロットへ複製。
create or replace function copy_previous_nap_check(p_session_id uuid, p_slot_at timestamptz)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_prev nap_checks%rowtype;
begin
  select * into v_prev from nap_checks
  where session_id = p_session_id and slot_at = p_slot_at - interval '5 minutes';
  if v_prev.id is null then
    raise exception 'no previous check to copy';
  end if;
  return record_nap_check(p_session_id, p_slot_at, v_prev.body_position,
                          v_prev.breathing_checked, v_prev.complexion_checked, v_prev.bedding_checked);
end;
$$;

-- 変化なし(クラス一括): 5分前にチェックがあり当該スロットが未記入のセッションをまとめて複製。
create or replace function copy_previous_nap_checks_for_class(p_class_id uuid, p_session_date date, p_slot_at timestamptz)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_office uuid; v_count int := 0; v_rec record;
begin
  select office_id into v_office from childcare_classes where id = p_class_id;
  if v_office is null then
    raise exception 'class not found';
  end if;
  perform nap_check_authz(v_office, p_class_id, p_session_date, p_slot_at);

  for v_rec in
    select prev.session_id
    from nap_checks prev
    join nap_sessions s on s.id = prev.session_id
    where s.class_id = p_class_id and s.session_date = p_session_date
      and prev.slot_at = p_slot_at - interval '5 minutes'
      and not exists (select 1 from nap_checks cur where cur.session_id = prev.session_id and cur.slot_at = p_slot_at)
  loop
    perform copy_previous_nap_check(v_rec.session_id, p_slot_at);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- 参照(グリッド用): セッション + チェック(jsonb配列)。
create or replace function fetch_nap_board(p_office_id uuid, p_class_id uuid, p_session_date date)
returns table (
  session_id uuid,
  child_id uuid,
  display_name text,
  honorific_suffix text,
  class_id uuid,
  class_name text,
  is_required boolean,
  sleep_start_at timestamptz,
  wake_up_at timestamptz,
  checks jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not has_childcare_office_access(p_office_id) then
    raise exception 'not authorized';
  end if;

  return query
  select
    s.id, c.id, c.display_name, c.honorific_suffix_resolved, cc.id, cc.class_name,
    s.is_required, s.sleep_start_at, s.wake_up_at,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'slot_at', nc.slot_at, 'body_position', nc.body_position,
        'breathing', nc.breathing_checked, 'complexion', nc.complexion_checked,
        'bedding', nc.bedding_checked, 'source', nc.source) order by nc.slot_at)
      from nap_checks nc where nc.session_id = s.id
    ), '[]'::jsonb)
  from nap_sessions s
  join children c on c.id = s.child_id
  join childcare_classes cc on cc.id = s.class_id
  where s.office_id = p_office_id and s.session_date = p_session_date
    and (p_class_id is null or s.class_id = p_class_id)
  order by cc.age_group, cc.class_name, c.display_name;
end;
$$;

-- 参照(漏れスロット): 入眠〜min(起床, now) の未チェック5分スロットを算出(バナー・15:00cron共通)。
create or replace function fetch_nap_missing_slots(p_office_id uuid, p_session_date date)
returns table (
  session_id uuid,
  child_id uuid,
  display_name text,
  class_id uuid,
  class_name text,
  missing_count int,
  missing_slots timestamptz[]
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not has_childcare_office_access(p_office_id) then
    raise exception 'not authorized';
  end if;

  return query
  with expected as (
    select s.id as session_id, gs as slot_at
    from nap_sessions s
    cross join lateral generate_series(
      date_bin('5 minutes', s.sleep_start_at, timestamptz 'epoch')
        + case when s.sleep_start_at > date_bin('5 minutes', s.sleep_start_at, timestamptz 'epoch')
               then interval '5 minutes' else interval '0' end,
      least(coalesce(s.wake_up_at, now()), now()),
      interval '5 minutes'
    ) gs
    where s.office_id = p_office_id and s.session_date = p_session_date and s.sleep_start_at is not null
  ),
  miss as (
    select e.session_id, array_agg(e.slot_at order by e.slot_at) as slots, count(*) as cnt
    from expected e
    left join nap_checks nc on nc.session_id = e.session_id and nc.slot_at = e.slot_at
    where nc.id is null
    group by e.session_id
  )
  select s.id, c.id, c.display_name, cc.id, cc.class_name, m.cnt::int, m.slots
  from miss m
  join nap_sessions s on s.id = m.session_id
  join children c on c.id = s.child_id
  join childcare_classes cc on cc.id = s.class_id
  order by cc.age_group, cc.class_name, c.display_name;
end;
$$;
