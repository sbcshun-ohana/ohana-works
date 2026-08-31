-- 409: 一時預かり(1クラス・年齢混在)で3歳以上児に連絡帳・午睡が出る問題の修正(俊報告 2026-08-31)。
--   原因:
--     (A) 295で is_family_daily_report_required が児override(100)を見なくなっていた
--         → 一時預かり児に設定した連絡帳overrideが無視されていた。override を最優先で復活
--         (加配判定は維持・通常児は override=null で従来動作のまま)。
--     (B) fetch_daily_contacts_for_office が児ごとの連絡帳要否で絞っていなかった(クラス全員表示)
--         → 連絡帳一覧を「連絡帳が必須の児のみ」に絞る(3-5歳・非加配は出さない)。
--     (C) 午睡のクラス一括入眠が非対象児(3-5歳)にもセッションを作っていた
--         → 午睡必須の児のみセッション作成(個別入眠は従来どおり任意で可)。

-- (A) 連絡帳必須判定: 児override(family_daily_report_required_override)を最優先に復活
create or replace function is_family_daily_report_required(p_child_id uuid, p_business_date date)
returns boolean
language sql stable security definer set search_path = public
as $$
  select
    coalesce(
      (select c.family_daily_report_required_override from children c where c.id = p_child_id),
      (
        select cc.family_daily_report_required
        from child_class_enrollments cce
        join childcare_classes cc on cc.id = cce.class_id
        where cce.child_id = p_child_id
          and cce.effective_start_date <= p_business_date
          and (cce.effective_end_date is null or cce.effective_end_date >= p_business_date)
        order by cce.effective_start_date desc
        limit 1
      ),
      true
    )
    or exists (
      select 1 from child_kahai_periods k
      where k.child_id = p_child_id
        and k.start_date <= p_business_date
        and (k.end_date is null or k.end_date >= p_business_date)
    );
$$;

-- (B) 連絡帳一覧: 連絡帳が必須の児のみ(130の定義を踏襲し where に is_family_daily_report_required を追加)
create or replace function fetch_daily_contacts_for_office(p_office_id uuid, p_business_date date)
returns table (
  contact_id uuid,
  child_id uuid,
  child_display_name text,
  child_honorific_suffix text,
  class_name text,
  assignee_employee_id uuid,
  assignee_name text,
  status text,
  guardian_message text,
  child_today_notes text,
  free_notes text,
  ai_generated_text text,
  current_text text,
  admin_comment text,
  rejected_reason text,
  submitted_at timestamptz,
  approved_at timestamptz,
  copied_at timestamptz,
  is_absent boolean,
  nap_periods jsonb,
  toileting_records jsonb,
  meal_completion_pct int,
  meal_free_note text,
  temperature numeric,
  temperature_measured_at time,
  bath_taken boolean
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not has_childcare_office_access(p_office_id) then
    raise exception 'not authorized';
  end if;

  return query
  select
    cdc.id, c.id, c.display_name, c.honorific_suffix_resolved, cc.class_name,
    cdc.assignee_employee_id, e.name,
    cdc.status, cdc.guardian_message, cdc.child_today_notes, cdc.free_notes,
    cdc.ai_generated_text, cdc.current_text, cdc.admin_comment, cdc.rejected_reason,
    cdc.submitted_at, cdc.approved_at, cdc.copied_at,
    coalesce(cda.is_absent, false),
    cdc.nap_periods, cdc.toileting_records, cdc.meal_completion_pct, cdc.meal_free_note,
    cdc.temperature, cdc.temperature_measured_at, cdc.bath_taken
  from children c
  join child_class_enrollments cce on cce.child_id = c.id
    and cce.effective_start_date <= p_business_date
    and (cce.effective_end_date is null or cce.effective_end_date >= p_business_date)
  join childcare_classes cc on cc.id = cce.class_id
  left join child_daily_contacts cdc on cdc.child_id = c.id and cdc.business_date = p_business_date
  left join employees e on e.id = cdc.assignee_employee_id
  left join child_daily_attendance cda on cda.child_id = c.id and cda.business_date = p_business_date
  where c.office_id = p_office_id and c.enrollment_status <> '退園済み'
    and is_family_daily_report_required(c.id, p_business_date)   -- 連絡帳が必須の児のみ(3-5歳・非加配は出さない)
  order by cc.class_name, c.display_name;
end;
$$;

-- (C) 午睡クラス一括入眠: 午睡必須の児のみセッション作成(406を踏襲・where追加)
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
         null
  from children c
  join child_class_enrollments cce on cce.child_id = c.id
    and cce.effective_start_date <= v_date
    and (cce.effective_end_date is null or cce.effective_end_date >= v_date)
  where cce.class_id = p_class_id and c.enrollment_status <> '退園済み'
    and coalesce(c.nap_check_required_override, v_class_required)   -- 午睡必須の児のみ一括作成
  on conflict (child_id, session_date) do update set sleep_start_at = excluded.sleep_start_at;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
