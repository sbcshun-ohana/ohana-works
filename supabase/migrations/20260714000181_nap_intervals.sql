-- 午睡の複数回対応(案B): nap_intervals 子テーブル。1セッション=1児1日、複数の睡眠区間を持つ。
-- 既存 nap_sessions.sleep_start_at/wake_up_at は「区間1」へバックフィルし、以降も
-- 「最初の入眠/全区間終了時の起床」を表す overall として維持。15時漏れは区間ごとに判定(覚醒中の隙間は対象外)。

create table nap_intervals (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references nap_sessions(id) on delete cascade,
  seq int not null,                        -- 1-based 午睡回数
  sleep_start_at timestamptz not null,
  wake_up_at timestamptz,                   -- null=就寝中(未起床)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (session_id, seq)
);
create trigger trg_nap_intervals_updated_at before update on nap_intervals
  for each row execute function set_updated_at();
alter table nap_intervals enable row level security;
create policy nap_intervals_select on nap_intervals
  for select using (exists (select 1 from nap_sessions s where s.id = session_id and has_childcare_office_access(s.office_id)));
do $$ begin
  execute format('create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();','nap_intervals');
end $$;

-- 既存セッションを区間1へバックフィル(入眠済のもの)
insert into nap_intervals (session_id, seq, sleep_start_at, wake_up_at)
select id, 1, sleep_start_at, wake_up_at from nap_sessions where sleep_start_at is not null;

-- overall(session の sleep_start_at/wake_up_at)を区間から再計算するヘルパー
create or replace function refresh_nap_session_overall(p_session_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update nap_sessions s set
    sleep_start_at = (select min(sleep_start_at) from nap_intervals where session_id = p_session_id),
    wake_up_at = case when exists (select 1 from nap_intervals where session_id = p_session_id and wake_up_at is null)
                      then null
                      else (select max(wake_up_at) from nap_intervals where session_id = p_session_id) end
  where s.id = p_session_id;
end; $$;

-- 入眠(個別)= セッション upsert + 区間追加(seq=最大+1)。1回目も再入眠も同じ(押すたびに区間追加)。
create or replace function start_nap_session(p_child_id uuid, p_sleep_start_at timestamptz)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_date date := (p_sleep_start_at at time zone 'Asia/Tokyo')::date;
  v_office uuid; v_class uuid; v_required boolean; v_sid uuid;
begin
  select c.office_id, cce.class_id, cc.nap_check_required into v_office, v_class, v_required
  from children c join child_class_enrollments cce on cce.child_id=c.id
    and cce.effective_start_date<=v_date and (cce.effective_end_date is null or cce.effective_end_date>=v_date)
  join childcare_classes cc on cc.id=cce.class_id where c.id=p_child_id
  order by cce.effective_start_date desc limit 1;
  if v_office is null then raise exception 'child/class not found'; end if;
  if not has_childcare_class_access(v_class) then raise exception 'not authorized'; end if;

  insert into nap_sessions (child_id, office_id, class_id, session_date, sleep_start_at, is_required, added_by)
  values (p_child_id, v_office, v_class, v_date, p_sleep_start_at, v_required, case when v_required then null else my_employee_id() end)
  on conflict (child_id, session_date) do update set class_id=excluded.class_id, office_id=excluded.office_id
  returning id into v_sid;

  insert into nap_intervals (session_id, seq, sleep_start_at)
  values (v_sid, coalesce((select max(seq) from nap_intervals where session_id=v_sid),0)+1, p_sleep_start_at);
  perform refresh_nap_session_overall(v_sid);
  return v_sid;
end; $$;

-- 入眠(クラス一括)= 在籍児全員に区間追加
create or replace function start_nap_sessions_for_class(p_class_id uuid, p_sleep_start_at timestamptz)
returns int language plpgsql security definer set search_path = public as $$
declare v_date date := (p_sleep_start_at at time zone 'Asia/Tokyo')::date; v_office uuid; v_n int:=0; r record;
begin
  if not has_childcare_class_access(p_class_id) then raise exception 'not authorized'; end if;
  select office_id into v_office from childcare_classes where id=p_class_id;
  if v_office is null then raise exception 'class not found'; end if;
  for r in
    select c.id from children c join child_class_enrollments cce on cce.child_id=c.id
      and cce.effective_start_date<=v_date and (cce.effective_end_date is null or cce.effective_end_date>=v_date)
    where cce.class_id=p_class_id and c.enrollment_status<>'退園済み'
  loop
    perform start_nap_session(r.id, p_sleep_start_at);
    v_n := v_n + 1;
  end loop;
  return v_n;
end; $$;

-- 起床(個別)= 最後の未起床区間を閉じる
create or replace function end_nap_session(p_session_id uuid, p_wake_up_at timestamptz)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_class uuid; v_date date; v_iv uuid;
begin
  select office_id, class_id, session_date into v_office, v_class, v_date from nap_sessions where id=p_session_id;
  if v_office is null then raise exception 'session not found'; end if;
  if v_date < (now() at time zone 'Asia/Tokyo')::date then
    if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  elsif not has_childcare_class_access(v_class) then raise exception 'not authorized'; end if;

  select id into v_iv from nap_intervals where session_id=p_session_id and wake_up_at is null order by seq desc limit 1;
  if v_iv is not null then update nap_intervals set wake_up_at=p_wake_up_at where id=v_iv; end if;
  perform refresh_nap_session_overall(p_session_id);
end; $$;

-- 起床(クラス一括)= 各セッションの最後の未起床区間を閉じる
create or replace function end_nap_sessions_for_class(p_class_id uuid, p_session_date date, p_wake_up_at timestamptz)
returns int language plpgsql security definer set search_path = public as $$
declare v_n int:=0; r record;
begin
  if not has_childcare_class_access(p_class_id) then raise exception 'not authorized'; end if;
  for r in select id from nap_sessions where class_id=p_class_id and session_date=p_session_date loop
    if exists (select 1 from nap_intervals where session_id=r.id and wake_up_at is null) then
      perform end_nap_session(r.id, p_wake_up_at);
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end; $$;

-- 参照(グリッド): 区間配列を追加(既存 checks はそのまま)
drop function if exists fetch_nap_board(uuid, uuid, date);
create function fetch_nap_board(p_office_id uuid, p_class_id uuid, p_session_date date)
returns table (session_id uuid, child_id uuid, display_name text, honorific_suffix text, class_id uuid, class_name text,
  is_required boolean, sleep_start_at timestamptz, wake_up_at timestamptz, intervals jsonb, checks jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  return query
  select s.id, c.id, c.display_name, c.honorific_suffix_resolved, cc.id, cc.class_name, s.is_required, s.sleep_start_at, s.wake_up_at,
    coalesce((select jsonb_agg(jsonb_build_object('seq',iv.seq,'sleep_start_at',iv.sleep_start_at,'wake_up_at',iv.wake_up_at) order by iv.seq)
              from nap_intervals iv where iv.session_id=s.id), '[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object('slot_at',nc.slot_at,'body_position',nc.body_position,'breathing',nc.breathing_checked,
              'complexion',nc.complexion_checked,'bedding',nc.bedding_checked,'source',nc.source) order by nc.slot_at)
              from nap_checks nc where nc.session_id=s.id), '[]'::jsonb)
  from nap_sessions s join children c on c.id=s.child_id join childcare_classes cc on cc.id=s.class_id
  where s.office_id=p_office_id and s.session_date=p_session_date and (p_class_id is null or s.class_id=p_class_id)
  order by cc.age_group, cc.class_name, c.display_name;
end; $$;

-- 漏れスロット: 区間ごとに算出(覚醒中の隙間は対象外)
create or replace function fetch_nap_missing_slots(p_office_id uuid, p_session_date date)
returns table (session_id uuid, child_id uuid, display_name text, class_id uuid, class_name text, missing_count int, missing_slots timestamptz[])
language plpgsql stable security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  return query
  with expected as (
    select s.id as session_id, gs as slot_at
    from nap_sessions s
    join nap_intervals iv on iv.session_id = s.id
    cross join lateral generate_series(
      date_bin('5 minutes', iv.sleep_start_at, timestamptz 'epoch')
        + case when iv.sleep_start_at > date_bin('5 minutes', iv.sleep_start_at, timestamptz 'epoch') then interval '5 minutes' else interval '0' end,
      least(coalesce(iv.wake_up_at, now()), now()),
      interval '5 minutes') gs
    where s.office_id=p_office_id and s.session_date=p_session_date
  ),
  miss as (
    select e.session_id, array_agg(distinct e.slot_at order by e.slot_at) slots, count(distinct e.slot_at) cnt
    from expected e left join nap_checks nc on nc.session_id=e.session_id and nc.slot_at=e.slot_at
    where nc.id is null group by e.session_id
  )
  select s.id, c.id, c.display_name, cc.id, cc.class_name, m.cnt::int, m.slots
  from miss m join nap_sessions s on s.id=m.session_id join children c on c.id=s.child_id join childcare_classes cc on cc.id=s.class_id
  order by cc.age_group, cc.class_name, c.display_name;
end; $$;

-- 15時cron: 同じ区間ロジックをインライン化(覚醒中の隙間は数えない)
create or replace function cron_detect_nap_check_gaps()
returns void language plpgsql security definer set search_path = public as $$
declare v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  insert into notifications (notification_type, title, body, channels, target_employee_id, payload, status)
  select distinct 'nap_check_gap', '午睡チェックの記入漏れ',
    o.name || ' で本日の午睡チェックに未記入があります。ご確認ください。', array['push'], mgr.employee_id,
    jsonb_build_object('office_id', g.office_id::text, 'date', v_today::text), 'pending'
  from (
    select distinct e.office_id from (
      select s.id session_id, s.office_id, gs slot_at
      from nap_sessions s join nap_intervals iv on iv.session_id=s.id
      cross join lateral generate_series(
        date_bin('5 minutes', iv.sleep_start_at, timestamptz 'epoch')
          + case when iv.sleep_start_at > date_bin('5 minutes', iv.sleep_start_at, timestamptz 'epoch') then interval '5 minutes' else interval '0' end,
        least(coalesce(iv.wake_up_at, now()), now()), interval '5 minutes') gs
      where s.session_date=v_today
    ) e left join nap_checks nc on nc.session_id=e.session_id and nc.slot_at=e.slot_at
    where nc.id is null
  ) g
  join offices o on o.id=g.office_id
  cross join lateral (
    select er.employee_id from employee_roles er join roles r on r.id=er.role_id
    where r.code in ('system_admin','executive_director') or (r.code in ('director','chief','office_manager') and (er.office_id is null or er.office_id=g.office_id))
    union select gr.grantee_employee_id from multi_office_authority_grants gr where gr.office_id=g.office_id and gr.revoked_at is null
  ) mgr(employee_id)
  where not exists (select 1 from notifications n where n.notification_type='nap_check_gap'
    and n.target_employee_id=mgr.employee_id and n.payload->>'office_id'=g.office_id::text and n.payload->>'date'=v_today::text);
end; $$;

-- 取込: 午睡区間を child_daily_contacts.nap_periods({start,end}[]・分単位)へ上書き(テキスト欄は不可侵)
-- 連絡帳行が無ければ作成(status は既定 'draft'=承認・公開に自動で乗らない)。
create or replace function import_nap_times_to_contact(p_child_id uuid, p_business_date date)
returns int language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_periods jsonb; v_n int;
begin
  select office_id into v_office from children where id=p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'start', to_char(iv.sleep_start_at at time zone 'Asia/Tokyo','HH24:MI'),
           'end', case when iv.wake_up_at is not null then to_char(iv.wake_up_at at time zone 'Asia/Tokyo','HH24:MI') else '' end
         ) order by iv.seq), '[]'::jsonb), count(*)
    into v_periods, v_n
  from nap_intervals iv join nap_sessions s on s.id=iv.session_id
  where s.child_id=p_child_id and s.session_date=p_business_date;

  insert into child_daily_contacts (child_id, business_date, nap_periods)
  values (p_child_id, p_business_date, v_periods)
  on conflict (child_id, business_date) do update set nap_periods = excluded.nap_periods;
  return v_n;
end; $$;
