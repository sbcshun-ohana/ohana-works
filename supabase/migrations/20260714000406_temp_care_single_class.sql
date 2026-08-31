-- 406: 一時預かりを「1クラス」化+児ごとの年齢自動判定(俊要望 2026-08-31)。
--   クラス名は「一時預かり」1つ(何歳児の括弧書き廃止)。年齢区分は生年月日から児ごとに
--   自動算出し、連絡帳(family_daily_report_required_override=100)と午睡(本migrationで
--   children に nap_check_required_override を新設)を児単位で出し分ける。
--   → 既存の連絡帳overrideと同型。午睡は169の入眠RPCを coalesce(児override, クラス) に変更。

-- (1) 児ごとのoverride(連絡帳=100由来だがstaging未適用の環境があるため if not exists で保険。午睡=本406で新設)
alter table children add column if not exists family_daily_report_required_override boolean;
alter table children add column if not exists nap_check_required_override boolean;
comment on column children.nap_check_required_override is
  '午睡チェック必須の児単位override。null=クラスの nap_check_required に従う。一時預かり(1クラス)で年齢別に出し分ける等。';

-- (2) start_nap_session — is_required を児override優先に(169を踏襲・SELECTのみ変更)
create or replace function start_nap_session(p_child_id uuid, p_sleep_start_at timestamptz)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_date date := (p_sleep_start_at at time zone 'Asia/Tokyo')::date;
  v_office uuid;
  v_class uuid;
  v_required boolean;
  v_id uuid;
begin
  select c.office_id, cce.class_id, coalesce(c.nap_check_required_override, cc.nap_check_required)
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

-- (3) start_nap_sessions_for_class — 児ごとに is_required を coalesce(児override, クラス)
create or replace function start_nap_sessions_for_class(p_class_id uuid, p_sleep_start_at timestamptz)
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_date date := (p_sleep_start_at at time zone 'Asia/Tokyo')::date;
  v_office uuid;
  v_class_required boolean;
  v_count int;
begin
  if not has_childcare_class_access(p_class_id) then
    raise exception 'not authorized';
  end if;
  select office_id, nap_check_required into v_office, v_class_required
  from childcare_classes where id = p_class_id;
  if v_office is null then
    raise exception 'class not found';
  end if;

  insert into nap_sessions (child_id, office_id, class_id, session_date, sleep_start_at, is_required, added_by)
  select c.id, v_office, p_class_id, v_date, p_sleep_start_at,
         coalesce(c.nap_check_required_override, v_class_required),
         case when coalesce(c.nap_check_required_override, v_class_required) then null else my_employee_id() end
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

-- (4) ensure_temp_care_class — 施設ごとに「一時預かり」1クラス(年齢なし)。
--     クラス自体の連絡帳/午睡フラグは false(児ごとoverrideで判定するため)。
create or replace function ensure_temp_care_class(p_office_id uuid, p_fiscal int)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_class uuid;
begin
  select id into v_class from childcare_classes
  where office_id = p_office_id and school_year = p_fiscal and class_name = '一時預かり';
  if v_class is null then
    insert into childcare_classes
      (office_id, school_year, class_name, age_group, is_active,
       family_daily_report_required, nap_check_required)
    values
      (p_office_id, p_fiscal, '一時預かり', '一時預かり', true, false, false)
    returning id into v_class;
  end if;
  return v_class;
end;
$$;
revoke execute on function ensure_temp_care_class(uuid, int) from public, anon, authenticated;

-- 旧シグネチャ(年齢あり)の関数は破棄
drop function if exists ensure_temp_care_class(uuid, int, int);

-- (5) enroll_temp_care_child — 「一時預かり」1クラスへ在籍+児ごとに連絡帳/午睡overrideを年齢で設定
create or replace function enroll_temp_care_child(
  p_office_id uuid,
  p_full_name text,
  p_birth_date date,
  p_gender text default null,
  p_name_kana text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
  v_fiscal int := case when extract(month from v_today) >= 4
                       then extract(year from v_today)::int
                       else extract(year from v_today)::int - 1 end;
  v_age int;
  v_class uuid;
  v_child uuid;
  v_needs_full boolean;   -- 0-2歳=連絡帳・午睡あり
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  if p_full_name is null or btrim(p_full_name) = '' then raise exception '氏名を入力してください'; end if;
  if p_birth_date is null then raise exception '生年月日を入力してください'; end if;
  if p_birth_date > v_today then raise exception '生年月日が未来日です'; end if;
  if p_gender is not null and p_gender not in ('男','女','その他') then
    raise exception '性別が不正です';
  end if;

  v_age := nursery_age_for_date(p_birth_date, v_today);
  v_needs_full := (v_age <= 2);
  v_class := ensure_temp_care_class(p_office_id, v_fiscal);

  insert into children
    (office_id, full_name, display_name, name_kana, gender, birth_date,
     enrollment_date, enrollment_status, child_kind,
     family_daily_report_required_override, nap_check_required_override)
  values
    (p_office_id, btrim(p_full_name), btrim(p_full_name), nullif(btrim(coalesce(p_name_kana,'')), ''),
     p_gender, p_birth_date, v_today, '在籍中', 'temporary',
     v_needs_full, v_needs_full)   -- 0-2歳=連絡帳・午睡あり / 3-5歳=なし(年齢で自動)
  returning id into v_child;

  insert into child_class_enrollments (child_id, class_id, effective_start_date, assigned_by)
  values (v_child, v_class, v_today, my_employee_id());

  return v_child;
end;
$$;
grant execute on function enroll_temp_care_child(uuid, text, date, text, text) to authenticated, service_role;
revoke execute on function enroll_temp_care_child(uuid, text, date, text, text) from public, anon;

-- (6) fetch_temp_care_children — 連絡帳/午睡は児ごとの effective 値(override優先)で返す
create or replace function fetch_temp_care_children(p_office_id uuid)
returns table (
  child_id uuid, display_name text, name_kana text, birth_date date, gender text,
  nursery_age int, class_name text, contact_required boolean, nap_required boolean,
  enrollment_date date
)
language plpgsql stable security definer set search_path = public as $$
declare v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  return query
  select c.id, c.display_name, c.name_kana, c.birth_date, c.gender,
         nursery_age_for_date(c.birth_date, v_today),
         cl.class_name,
         coalesce(c.family_daily_report_required_override, cl.family_daily_report_required, false),
         coalesce(c.nap_check_required_override, cl.nap_check_required, false),
         c.enrollment_date
  from children c
  left join lateral (
    select cl.class_name, cl.family_daily_report_required, cl.nap_check_required
    from child_class_enrollments cce
    join childcare_classes cl on cl.id = cce.class_id
    where cce.child_id = c.id
      and (cce.effective_end_date is null or cce.effective_end_date >= v_today)
    order by cce.effective_start_date desc limit 1
  ) cl on true
  where c.office_id = p_office_id
    and c.child_kind = 'temporary'
    and c.enrollment_status <> '退園済み'
  order by c.enrollment_date desc, c.display_name;
end;
$$;
grant execute on function fetch_temp_care_children(uuid) to authenticated, service_role;
revoke execute on function fetch_temp_care_children(uuid) from public, anon;
