-- 保護者アプリ Phase A: 登園制御(家庭連絡帳必須クラス/園児・変更1)
--
-- 対象は家庭連絡帳必須クラス(初期0〜2歳児相当。クラス・園児ごとに必須設定可能)。
-- 「この必須設定は機能フラグではなくクラス/園児側の運用設定として実装する」(指示書§5.3)。
-- 園児側のoverrideが優先され、無指定ならクラス側の設定を使う。

alter table childcare_classes add column family_daily_report_required boolean not null default true;
alter table children add column family_daily_report_required_override boolean;

create or replace function is_family_daily_report_required(p_child_id uuid, p_business_date date)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select family_daily_report_required_override from children where id = p_child_id),
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
  );
$$;

create or replace function has_family_daily_report_submitted(p_child_id uuid, p_business_date date)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from family_daily_reports
    where child_id = p_child_id and business_date = p_business_date and status = 'submitted'
  );
$$;

-- 例外処理(災害・通信障害等)。管理者権限のみ。理由必須、事由をchild_attendance_eventsに記録する。
create or replace function admin_override_attendance_check_in(p_child_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_office_id uuid;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason is required';
  end if;
  select office_id into v_office_id from children where id = p_child_id;
  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not manages_childcare(v_office_id) then
    raise exception 'not authorized';
  end if;

  insert into child_attendance_events (
    child_id, event_type, occurred_at, recorded_by_employee_id, admin_override_by, admin_override_reason
  ) values (
    p_child_id, 'drop_off', now(), my_employee_id(), my_employee_id(), p_reason
  );

  perform refresh_daily_child_status(p_child_id, (now() at time zone 'Asia/Tokyo')::date);
end;
$$;
