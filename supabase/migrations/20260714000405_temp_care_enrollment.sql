-- 405: 一時預かり T1 — 簡易入園+年齢クラス自動振り分け(俊確定 2026-08-31)。
--   一時預かり児 = child_kind='temporary' を「一時預かり(N歳)」専用クラスに在籍させる。
--   生年月日から保育年齢(その年度の4/1時点)を自動算出し、対応年齢の一時預かりクラスを
--   find-or-create して在籍 → 既存の年齢別ロジックが自動で効く:
--     0-2歳=連絡帳(family_daily_report_required)・午睡(nap_check_required)あり
--     3-5歳=なし(登降園・給食・請求のみ)
--   専用クラスなので通常クラス(ほし組等)には混ざらない。給食の食数は在籍で自動カウント。
--   一時預かり児の月次請求サイクル除外・当日精算請求は T3(別migration)で扱う。

-- 保育年齢(その年度の4/1時点の満年齢)。0-5にクランプ。
create or replace function nursery_age_for_date(p_birth_date date, p_ref_date date)
returns int
language sql immutable as $$
  select greatest(0, least(5,
    extract(year from age(
      make_date(case when extract(month from p_ref_date) >= 4
                     then extract(year from p_ref_date)::int
                     else extract(year from p_ref_date)::int - 1 end, 4, 1),
      p_birth_date))::int
  ));
$$;

-- 一時預かりクラスの find-or-create(内部・(office, 年度, 年齢)で一意)
create or replace function ensure_temp_care_class(p_office_id uuid, p_fiscal int, p_age int)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_class uuid;
  v_name text := '一時預かり(' || p_age || '歳)';
begin
  select id into v_class from childcare_classes
  where office_id = p_office_id and school_year = p_fiscal and class_name = v_name;
  if v_class is null then
    insert into childcare_classes
      (office_id, school_year, class_name, age_group, is_active,
       family_daily_report_required, nap_check_required)
    values
      (p_office_id, p_fiscal, v_name, p_age || '歳', true,
       p_age <= 2, p_age <= 2)   -- 0-2歳=連絡帳・午睡あり / 3-5歳=なし
    returning id into v_class;
  end if;
  return v_class;
end;
$$;
revoke execute on function ensure_temp_care_class(uuid, int, int) from public, anon, authenticated;

-- ============================================================
-- enroll_temp_care_child — 簡易入園(氏名・生年月日・性別)+ 年齢クラス自動在籍
-- ============================================================
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
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  if p_full_name is null or btrim(p_full_name) = '' then raise exception '氏名を入力してください'; end if;
  if p_birth_date is null then raise exception '生年月日を入力してください'; end if;
  if p_birth_date > v_today then raise exception '生年月日が未来日です'; end if;
  if p_gender is not null and p_gender not in ('男','女','その他') then
    raise exception '性別が不正です';
  end if;

  v_age := nursery_age_for_date(p_birth_date, v_today);
  v_class := ensure_temp_care_class(p_office_id, v_fiscal, v_age);

  insert into children
    (office_id, full_name, display_name, name_kana, gender, birth_date,
     enrollment_date, enrollment_status, child_kind)
  values
    (p_office_id, btrim(p_full_name), btrim(p_full_name), nullif(btrim(coalesce(p_name_kana,'')), ''),
     p_gender, p_birth_date, v_today, '在籍中', 'temporary')
  returning id into v_child;

  insert into child_class_enrollments (child_id, class_id, effective_start_date, assigned_by)
  values (v_child, v_class, v_today, my_employee_id());

  return v_child;
end;
$$;
grant execute on function enroll_temp_care_child(uuid, text, date, text, text) to authenticated, service_role;
revoke execute on function enroll_temp_care_child(uuid, text, date, text, text) from public, anon;

-- ============================================================
-- fetch_temp_care_children — 一時預かり児の一覧(リピーター選択・管理用)
-- ============================================================
create or replace function fetch_temp_care_children(p_office_id uuid)
returns table (
  child_id uuid, display_name text, name_kana text, birth_date date, gender text,
  nursery_age int, class_name text, contact_required boolean, nap_required boolean,
  enrollment_date date
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  return query
  select c.id, c.display_name, c.name_kana, c.birth_date, c.gender,
         nursery_age_for_date(c.birth_date, (now() at time zone 'Asia/Tokyo')::date),
         cl.class_name, cl.family_daily_report_required, cl.nap_check_required,
         c.enrollment_date
  from children c
  left join lateral (
    select cl.class_name, cl.family_daily_report_required, cl.nap_check_required
    from child_class_enrollments cce
    join childcare_classes cl on cl.id = cce.class_id
    where cce.child_id = c.id
      and (cce.effective_end_date is null or cce.effective_end_date >= (now() at time zone 'Asia/Tokyo')::date)
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
