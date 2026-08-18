-- 234: 兄弟一括登降園(family check-in)DB層(俊確定5点 2026-08-18・staging適用済)。
-- 半自動(スキャン→確認画面→確定)。方向自動推定+手動トグル。family=保護者に紐づく同一施設の全園児。
-- 欠席連絡があっても実登園を優先(当日分のみ自動解除)。全施設共通で使用可(フラグは既定OFF・施設別ON)。
-- キオスク(保護者向け・サービスロール)からのみ呼ばれる。感染症/連絡帳ゲートは各児個別に適用。
-- 冪等: テーブル=素create・関数=create or replace。

insert into feature_flags (feature_key, name, description, default_enabled)
select 'family_checkin_enabled', '兄弟一括登降園',
       'QRスキャン1回で保護者に紐づく兄弟を確認画面で一括登降園(M6別件)', false
where not exists (select 1 from feature_flags where feature_key = 'family_checkin_enabled');

create or replace function is_family_checkin_enabled_for_office(p_office_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select is_feature_enabled_for_office('family_checkin_enabled', p_office_id);
$$;

create table family_checkin_sessions (
  id uuid primary key default gen_random_uuid(),
  guardian_id uuid not null references guardians(id) on delete cascade,
  office_id uuid not null references offices(id),
  device_id uuid,
  direction text not null check (direction in ('arrival', 'departure')),
  consumed boolean not null default false,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index idx_family_checkin_sessions_guardian on family_checkin_sessions(guardian_id);
alter table family_checkin_sessions enable row level security;

create or replace function fetch_family_checkin_candidates(
  p_guardian_id uuid, p_office_id uuid, p_scanned_child_id uuid, p_business_date date
)
returns table (
  child_id uuid,
  child_name text,
  class_name text,
  today_status text,
  is_absent_today boolean,
  absence_kind text,
  direction text,
  default_selected boolean,
  note text
)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_scanned_status text;
  v_direction text;
begin
  select coalesce(s.status, 'not_arrived') into v_scanned_status
  from daily_child_status s
  where s.child_id = p_scanned_child_id and s.business_date = p_business_date;
  v_scanned_status := coalesce(v_scanned_status, 'not_arrived');
  v_direction := case when v_scanned_status = 'present' then 'departure' else 'arrival' end;

  return query
  select c.id, c.display_name, cc.class_name,
    coalesce(ds.status, 'not_arrived') as st,
    coalesce(a.is_absent, false) as absent_today,
    a.attendance_kind,
    v_direction,
    case
      when v_direction = 'arrival' then
        (coalesce(ds.status, 'not_arrived') = 'not_arrived' and not coalesce(a.is_absent, false))
      else
        (coalesce(ds.status, 'not_arrived') = 'present')
    end as default_sel,
    case
      when coalesce(a.is_absent, false) then '欠席連絡あり(登園する場合は当日分の欠席を解除します)'
      when coalesce(ds.status, 'not_arrived') = 'picked_up' then '降園済み'
      when coalesce(ds.status, 'not_arrived') = 'present' and v_direction = 'arrival' then '登園済み'
      when coalesce(ds.status, 'not_arrived') = 'not_arrived' and v_direction = 'departure' then '未登園'
      else null
    end as row_note
  from guardian_child_links gcl
  join children c on c.id = gcl.child_id
  left join child_class_enrollments cce on cce.child_id = c.id and cce.effective_end_date is null
  left join childcare_classes cc on cc.id = cce.class_id
  left join daily_child_status ds on ds.child_id = c.id and ds.business_date = p_business_date
  left join child_daily_attendance a on a.child_id = c.id and a.business_date = p_business_date
  where gcl.guardian_id = p_guardian_id
    and c.office_id = p_office_id
    and c.enrollment_status = '在籍中'
  order by cc.class_name, c.display_name;
end;
$$;

create or replace function cancel_child_absence_for_day(p_child_id uuid, p_business_date date)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  update child_daily_attendance
  set is_absent = false,
      absence_reason = '登園により本日分の欠席連絡を自動解除(元: ' || coalesce(attendance_kind, '欠席') || ')',
      attendance_kind = null,
      changed_at = now()
  where child_id = p_child_id and business_date = p_business_date and is_absent;
end;
$$;

create or replace function apply_family_checkin(
  p_session_id uuid, p_selections jsonb, p_business_date date
)
returns table (child_id uuid, result text, reason text)
language plpgsql security definer set search_path = public
as $$
declare
  v_session family_checkin_sessions%rowtype;
  v_sel jsonb;
  v_child uuid;
  v_action text;
  v_office uuid;
  v_status text;
  v_gate_blocked boolean;
  v_gate_reason text;
begin
  select * into v_session from family_checkin_sessions where id = p_session_id;
  if v_session.id is null then raise exception 'session not found'; end if;
  if v_session.consumed then raise exception 'session already used'; end if;
  if v_session.expires_at < now() then raise exception 'session expired'; end if;

  update family_checkin_sessions set consumed = true where id = p_session_id;

  for v_sel in select * from jsonb_array_elements(p_selections) loop
    v_child := (v_sel->>'child_id')::uuid;
    v_action := v_sel->>'action';

    select office_id into v_office from children where id = v_child and enrollment_status = '在籍中';
    if v_office is null or v_office <> v_session.office_id
       or not exists (select 1 from guardian_child_links where guardian_id = v_session.guardian_id and child_id = v_child) then
      child_id := v_child; result := 'skipped'; reason := '対象外の園児'; return next; continue;
    end if;

    if v_action = 'checkin' then
      v_gate_blocked := false; v_gate_reason := null;
      begin
        perform assert_infection_gate_for_checkin(v_child);
      exception when others then
        v_gate_blocked := true; v_gate_reason := sqlerrm;
      end;
      if v_gate_blocked then
        child_id := v_child; result := 'blocked'; reason := coalesce(v_gate_reason, '感染症ゲート'); return next; continue;
      end if;
      if coalesce((select is_family_daily_report_required(v_child, p_business_date)), false)
         and not coalesce((select has_family_daily_report_submitted(v_child, p_business_date)), false) then
        child_id := v_child; result := 'blocked'; reason := '家庭連絡帳が未提出です'; return next; continue;
      end if;
      perform cancel_child_absence_for_day(v_child, p_business_date);
      select coalesce(status, 'not_arrived') into v_status from daily_child_status where child_id = v_child and business_date = p_business_date;
      if coalesce(v_status, 'not_arrived') = 'present' then
        child_id := v_child; result := 'skipped'; reason := '既に登園済み'; return next; continue;
      end if;
      insert into child_attendance_events (child_id, event_type, occurred_at, recorded_by_guardian_id)
      values (v_child, 'drop_off', now(), v_session.guardian_id);
      perform refresh_daily_child_status(v_child, p_business_date);
      child_id := v_child; result := 'checked_in'; reason := null; return next;

    elsif v_action = 'checkout' then
      select coalesce(status, 'not_arrived') into v_status from daily_child_status where child_id = v_child and business_date = p_business_date;
      if coalesce(v_status, 'not_arrived') <> 'present' then
        child_id := v_child; result := 'skipped'; reason := '在園中ではありません'; return next; continue;
      end if;
      insert into child_attendance_events (child_id, event_type, occurred_at, recorded_by_guardian_id)
      values (v_child, 'pick_up', now(), v_session.guardian_id);
      perform refresh_daily_child_status(v_child, p_business_date);
      child_id := v_child; result := 'checked_out'; reason := null; return next;
    else
      child_id := v_child; result := 'skipped'; reason := '不明なアクション'; return next;
    end if;
  end loop;
end;
$$;

revoke execute on function fetch_family_checkin_candidates(uuid, uuid, uuid, date) from public;
revoke execute on function apply_family_checkin(uuid, jsonb, date) from public;
grant execute on function fetch_family_checkin_candidates(uuid, uuid, uuid, date) to service_role;
grant execute on function apply_family_checkin(uuid, jsonb, date) to service_role;
