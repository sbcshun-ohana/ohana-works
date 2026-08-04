-- A2: admin_web(監査)で午睡区間を追加/編集/削除。権限は nap_check_authz を流用(当日30分以内=施設/クラス
-- アクセス、30分超・過去日=manages_childcare)。判定は「今回書き込む編集後の値」基準(編集前の保存値は含めない)。
-- G4: import は区間が無ければ連絡帳を作らず 0 を返す。公開済み連絡帳への取込は主任以上のみ。
-- fetch_nap_board の intervals に id を追加。

create or replace function add_nap_interval(p_child_id uuid, p_sleep_start_at timestamptz, p_wake_up_at timestamptz default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_date date := (p_sleep_start_at at time zone 'Asia/Tokyo')::date;
  v_office uuid; v_class uuid; v_required boolean; v_sid uuid;
begin
  select c.office_id, cce.class_id, cc.nap_check_required into v_office, v_class, v_required
  from children c join child_class_enrollments cce on cce.child_id=c.id
    and cce.effective_start_date<=v_date and (cce.effective_end_date is null or cce.effective_end_date>=v_date)
  join childcare_classes cc on cc.id=cce.class_id where c.id=p_child_id order by cce.effective_start_date desc limit 1;
  if v_office is null then raise exception 'child/class not found'; end if;
  if p_wake_up_at is not null and p_wake_up_at < p_sleep_start_at then raise exception 'wake before sleep'; end if;
  -- 新値基準(起床があれば起床、無ければ入眠)
  perform nap_check_authz(v_office, v_class, v_date, coalesce(p_wake_up_at, p_sleep_start_at));

  insert into nap_sessions (child_id, office_id, class_id, session_date, sleep_start_at, is_required, added_by)
  values (p_child_id, v_office, v_class, v_date, p_sleep_start_at, v_required, case when v_required then null else my_employee_id() end)
  on conflict (child_id, session_date) do update set class_id=excluded.class_id, office_id=excluded.office_id
  returning id into v_sid;

  insert into nap_intervals (session_id, seq, sleep_start_at, wake_up_at)
  values (v_sid, coalesce((select max(seq) from nap_intervals where session_id=v_sid),0)+1, p_sleep_start_at, p_wake_up_at);
  perform refresh_nap_session_overall(v_sid);
  return v_sid;
end; $$;

-- 区間編集: 判定は「今回書き込む編集後の値」のみ(編集前の保存値は含めない)。
-- 起床を書く操作は coalesce(新起床, 新入眠)=新起床 で判定 → 入眠が何時間前でも起床がnow付近なら一般職員可。
create or replace function set_nap_interval(p_interval_id uuid, p_sleep_start_at timestamptz, p_wake_up_at timestamptz)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_class uuid; v_date date; v_sid uuid;
begin
  select s.office_id, s.class_id, s.session_date, s.id
    into v_office, v_class, v_date, v_sid
  from nap_intervals iv join nap_sessions s on s.id=iv.session_id where iv.id=p_interval_id;
  if v_office is null then raise exception 'interval not found'; end if;
  if p_wake_up_at is not null and p_wake_up_at < p_sleep_start_at then raise exception 'wake before sleep'; end if;
  perform nap_check_authz(v_office, v_class, v_date, coalesce(p_wake_up_at, p_sleep_start_at));
  update nap_intervals set sleep_start_at=p_sleep_start_at, wake_up_at=p_wake_up_at where id=p_interval_id;
  perform refresh_nap_session_overall(v_sid);
end; $$;

-- 区間削除: 区間内の最も遅い保存時刻を基準(30分超なら主任以上)。
create or replace function delete_nap_interval(p_interval_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_class uuid; v_date date; v_sid uuid; v_ref timestamptz;
begin
  select s.office_id, s.class_id, s.session_date, s.id, coalesce(iv.wake_up_at, iv.sleep_start_at)
    into v_office, v_class, v_date, v_sid, v_ref
  from nap_intervals iv join nap_sessions s on s.id=iv.session_id where iv.id=p_interval_id;
  if v_office is null then raise exception 'interval not found'; end if;
  perform nap_check_authz(v_office, v_class, v_date, v_ref);
  delete from nap_intervals where id=p_interval_id;
  delete from nap_sessions s where s.id=v_sid
    and not exists (select 1 from nap_intervals where session_id=v_sid)
    and not exists (select 1 from nap_checks where session_id=v_sid);
  if exists (select 1 from nap_sessions where id=v_sid) then perform refresh_nap_session_overall(v_sid); end if;
end; $$;

-- fetch_nap_board の intervals に id を追加(戻り列は不変)
create or replace function fetch_nap_board(p_office_id uuid, p_class_id uuid, p_session_date date)
returns table (session_id uuid, child_id uuid, display_name text, honorific_suffix text, class_id uuid, class_name text,
  is_required boolean, sleep_start_at timestamptz, wake_up_at timestamptz, intervals jsonb, checks jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  return query
  select s.id, c.id, c.display_name, c.honorific_suffix_resolved, cc.id, cc.class_name, s.is_required, s.sleep_start_at, s.wake_up_at,
    coalesce((select jsonb_agg(jsonb_build_object('id',iv.id,'seq',iv.seq,'sleep_start_at',iv.sleep_start_at,'wake_up_at',iv.wake_up_at) order by iv.seq)
              from nap_intervals iv where iv.session_id=s.id), '[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object('slot_at',nc.slot_at,'body_position',nc.body_position,'breathing',nc.breathing_checked,
              'complexion',nc.complexion_checked,'bedding',nc.bedding_checked,'source',nc.source) order by nc.slot_at)
              from nap_checks nc where nc.session_id=s.id), '[]'::jsonb)
  from nap_sessions s join children c on c.id=s.child_id join childcare_classes cc on cc.id=s.class_id
  where s.office_id=p_office_id and s.session_date=p_session_date and (p_class_id is null or s.class_id=p_class_id)
  order by cc.age_group, cc.class_name, c.display_name;
end; $$;

-- G4: 午睡区間が無ければ連絡帳を作らず 0 を返す。公開済み連絡帳への取込は主任以上のみ(承認フロー外書換の防止)。
create or replace function import_nap_times_to_contact(p_child_id uuid, p_business_date date)
returns int language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_periods jsonb; v_n int;
begin
  select office_id into v_office from children where id=p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;

  -- 公開済みの連絡帳を承認フロー外で書き換える経路を塞ぐ:
  -- 既に公開済み(保護者に見えている)の場合は主任以上のみ取込可。未公開(下書き・公開予約中)は施設職員で可。
  if exists (
    select 1 from child_daily_contacts
    where child_id = p_child_id and business_date = p_business_date and published_at is not null
  ) and not manages_childcare(v_office) then
    raise exception 'not authorized to import into a published contact';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'start', to_char(iv.sleep_start_at at time zone 'Asia/Tokyo','HH24:MI'),
           'end', case when iv.wake_up_at is not null then to_char(iv.wake_up_at at time zone 'Asia/Tokyo','HH24:MI') else '' end
         ) order by iv.seq), '[]'::jsonb), count(*)
    into v_periods, v_n
  from nap_intervals iv join nap_sessions s on s.id=iv.session_id
  where s.child_id=p_child_id and s.session_date=p_business_date;

  if v_n = 0 then return 0; end if;

  insert into child_daily_contacts (child_id, business_date, nap_periods)
  values (p_child_id, p_business_date, v_periods)
  on conflict (child_id, business_date) do update set nap_periods = excluded.nap_periods;
  return v_n;
end; $$;
