-- 連絡帳(child_daily_contacts)の申請まわり: バグ修正 + 仕様変更(俊確定 2026-08-12)
--
-- 【バグ】ensure_child_daily_contact は担任割当(child_contact_assignments)から assignee を
--   引くため、当該園児に有効な担任割当が無いと assignee_employee_id=NULL の下書きが作られる。
--   submit ゲートが「assignee 本人のみ」のため NULL 行は誰も申請できない
--   (staging実測: はな組テスト行 52dec37e-... が assignee=NULL)。admin_web/Ohana Kids とも
--   同一 RPC 経由(ensure_child_daily_contact)のため、割当の無い園児は両アプリで同症状。
--
-- 【仕様変更】主任以上(manages_childcare)は連絡帳の下書き・申請・承認をすべて行える。
--   1. 申請ゲートを「assignee 本人 または manages_childcare」に緩和
--      (一般職員は従来どおり assignee 本人のみ)。
--   2. 下書き作成時、有効な担任割当が無ければ作成者(my_employee_id())を assignee に設定し
--      NULL の下書きを作らない(admin_web/Ohana Kids 共通の ensure RPC で担保)。
--   3. 承認は現行どおり主任以上(approve_child_daily_contact は変更なし)。
--
-- 冪等: create or replace のみ。既存の NULL 行は本migrationでは書き換えない(緩和後は
--   主任以上が申請可能になり詰まらない。テスト行は俊が手動UPDATE予定)。

-- 1) 下書き作成: 担任割当が無ければ作成者を assignee にフォールバック(NULLで作らない)。
--    070(childcare_contact_assignment_lookup_fix)の担当解決ロジックはそのまま維持し、
--    insert の assignee_employee_id を coalesce(v_assignee, my_employee_id()) に変更。
create or replace function ensure_child_daily_contact(p_child_id uuid, p_business_date date)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_office_id uuid;
  v_assignee uuid;
  v_contact_id uuid;
begin
  select office_id into v_office_id from children where id = p_child_id;
  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  select assigned_employee_id into v_assignee
  from child_contact_assignments
  where child_id = p_child_id
    and effective_start_date <= p_business_date
    and (effective_end_date is null or effective_end_date >= p_business_date)
  order by effective_start_date desc
  limit 1;

  insert into child_daily_contacts (child_id, business_date, assignee_employee_id)
  values (p_child_id, p_business_date, coalesce(v_assignee, my_employee_id()))
  on conflict (child_id, business_date) do nothing;

  select id into v_contact_id from child_daily_contacts
  where child_id = p_child_id and business_date = p_business_date;

  return v_contact_id;
end;
$$;

-- 2) 申請ゲート緩和: assignee 本人 または 主任以上(manages_childcare)。
--    一般職員は assignee 本人のみ(is not distinct from = NULL安全比較。my_employee_id()は
--    childcare文脈で非NULLのため、assignee=NULL 行は manages_childcare 経由のみ申請可)。
--    office_id 参照をゲート前へ移動。それ以外(status判定・update・申請通知)は現行と同一。
create or replace function submit_child_daily_contact(p_contact_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_contact child_daily_contacts%rowtype;
  v_office_id uuid;
begin
  select * into v_contact from child_daily_contacts where id = p_contact_id for update;
  if v_contact.id is null then
    raise exception 'contact not found';
  end if;

  select office_id into v_office_id from children where id = v_contact.child_id;

  if not (
    v_contact.assignee_employee_id is not distinct from my_employee_id()
    or manages_childcare(v_office_id)
  ) then
    raise exception 'not authorized: only the assignee or a childcare manager can submit';
  end if;

  if v_contact.status not in ('draft', 'rejected') then
    raise exception 'contact is % and cannot be submitted', v_contact.status;
  end if;

  update child_daily_contacts
  set status = 'submitted', submitted_at = now(), rejected_reason = null
  where id = p_contact_id;

  insert into notifications (notification_type, title, body, channels, target_employee_id, payload)
  select
    'childcare_contact_submitted', '連絡帳の申請', null, array['in_app'], emp_id,
    jsonb_build_object('contact_id', p_contact_id, 'child_id', v_contact.child_id)
  from childcare_office_manager_employee_ids(v_office_id) as emp_id;
end;
$$;
