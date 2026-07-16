-- 保育業務 Phase1: クラス活動入力・申請・承認
-- クラスごとに1日1回。入力→申請→管理者確認→承認/差し戻し。
-- 担当者は「職員が自分を設定」「管理者が指定」の両方に対応する(claim_class_activity/reassign_class_activity)。

create table class_daily_activities (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references childcare_classes(id),
  business_date date not null,
  assignee_employee_id uuid references employees(id),
  today_theme text,
  activity_content text,
  class_overview text,
  class_announcement text,
  other_notes text,
  status text not null default 'draft' check (status in ('draft', 'submitted', 'approved', 'rejected')),
  submitted_at timestamptz,
  approved_by uuid references employees(id),
  approved_at timestamptz,
  rejected_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (class_id, business_date)
);
create trigger trg_class_daily_activities_updated_at before update on class_daily_activities
  for each row execute function set_updated_at();
create index idx_class_daily_activities_business_date on class_daily_activities(business_date);

alter table class_daily_activities enable row level security;
create policy class_daily_activities_select_scoped on class_daily_activities
  for select using (has_childcare_class_access(class_id));
create policy class_daily_activities_insert_scoped on class_daily_activities
  for insert with check (has_childcare_class_access(class_id));
-- 入力担当者本人は下書き・差し戻し中のみ内容を編集可(状態遷移(submit等)は下記RPC経由に限定)。
create policy class_daily_activities_update_assignee_content on class_daily_activities
  for update using (
    assignee_employee_id = my_employee_id() and status in ('draft', 'rejected')
  ) with check (
    assignee_employee_id = my_employee_id() and status in ('draft', 'rejected')
  );
-- 管理者は担当者不在時の変更(担当者差し替え含む)のため直接更新も許可する。
create policy class_daily_activities_update_managers on class_daily_activities
  for update using (
    exists (
      select 1 from childcare_classes cc
      where cc.id = class_daily_activities.class_id and manages_childcare(cc.office_id)
    )
  ) with check (
    exists (
      select 1 from childcare_classes cc
      where cc.id = class_daily_activities.class_id and manages_childcare(cc.office_id)
    )
  );

do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'class_daily_activities'
  );
end $$;

-- 保育業務における当該施設の管理者(システム最高管理者/園長/主任/園管理者)のemployee_id一覧。
-- 通知の宛先解決に用いる(notificationsテーブルにはoffice単位の宛先列が無いため、
-- 対象者を明示的に展開してtarget_employee_idごとに1行ずつ通知を作成する)。
create or replace function childcare_office_manager_employee_ids(target_office_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select distinct er.employee_id
  from employee_roles er
  join roles r on r.id = er.role_id
  where r.code = 'system_admin'
     or (
       r.code in ('director', 'chief', 'office_manager')
       and (er.office_id is null or er.office_id = target_office_id)
     );
$$;

-- 当日のクラス活動行が無ければ作成する(存在すればそのidを返す)。
create or replace function ensure_class_daily_activity(p_class_id uuid, p_business_date date)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_activity_id uuid;
begin
  if not has_childcare_class_access(p_class_id) then
    raise exception 'not authorized';
  end if;

  insert into class_daily_activities (class_id, business_date)
  values (p_class_id, p_business_date)
  on conflict (class_id, business_date) do nothing;

  select id into v_activity_id from class_daily_activities
  where class_id = p_class_id and business_date = p_business_date;

  return v_activity_id;
end;
$$;

-- 職員が自分を担当者に設定する(未割当、または既に自分が担当の場合のみ)。
create or replace function claim_class_activity(p_activity_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_activity class_daily_activities%rowtype;
begin
  select * into v_activity from class_daily_activities where id = p_activity_id for update;
  if v_activity.id is null then
    raise exception 'class activity not found';
  end if;
  if not has_childcare_class_access(v_activity.class_id) then
    raise exception 'not authorized';
  end if;
  if v_activity.assignee_employee_id is distinct from my_employee_id() and v_activity.assignee_employee_id is not null then
    raise exception 'already assigned to another employee';
  end if;

  update class_daily_activities set assignee_employee_id = my_employee_id() where id = p_activity_id;
end;
$$;

-- 管理者が担当者を指定・変更する(担当者不在時の差し替え含む。変更履歴はevent_logsに自動記録される)。
create or replace function reassign_class_activity(p_activity_id uuid, p_new_assignee_employee_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_office_id uuid;
  v_class_id uuid;
begin
  select class_id into v_class_id from class_daily_activities where id = p_activity_id;
  if v_class_id is null then
    raise exception 'class activity not found';
  end if;
  select office_id into v_office_id from childcare_classes where id = v_class_id;
  if not manages_childcare(v_office_id) then
    raise exception 'not authorized: only managers can reassign the assignee';
  end if;

  update class_daily_activities
  set assignee_employee_id = p_new_assignee_employee_id
  where id = p_activity_id;
end;
$$;

-- 申請(担当者本人のみ)。
create or replace function submit_class_activity(p_activity_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_activity class_daily_activities%rowtype;
  v_office_id uuid;
begin
  select * into v_activity from class_daily_activities where id = p_activity_id for update;
  if v_activity.id is null then
    raise exception 'class activity not found';
  end if;
  if v_activity.assignee_employee_id is distinct from my_employee_id() then
    raise exception 'not authorized: only the assignee can submit';
  end if;
  if v_activity.status not in ('draft', 'rejected') then
    raise exception 'class activity is % and cannot be submitted', v_activity.status;
  end if;

  update class_daily_activities
  set status = 'submitted', submitted_at = now(), rejected_reason = null
  where id = p_activity_id;

  select office_id into v_office_id from childcare_classes where id = v_activity.class_id;

  insert into notifications (notification_type, title, body, channels, target_employee_id, payload)
  select
    'childcare_class_activity_submitted', 'クラス活動の申請', null, array['in_app'], emp_id,
    jsonb_build_object('activity_id', p_activity_id, 'class_id', v_activity.class_id, 'business_date', v_activity.business_date)
  from childcare_office_manager_employee_ids(v_office_id) as emp_id;
end;
$$;

-- 承認(管理者のみ)。
create or replace function approve_class_activity(p_activity_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_activity class_daily_activities%rowtype;
  v_office_id uuid;
begin
  select * into v_activity from class_daily_activities where id = p_activity_id for update;
  if v_activity.id is null then
    raise exception 'class activity not found';
  end if;
  select office_id into v_office_id from childcare_classes where id = v_activity.class_id;
  if not manages_childcare(v_office_id) then
    raise exception 'not authorized';
  end if;
  if v_activity.status <> 'submitted' then
    raise exception 'class activity is % and cannot be approved', v_activity.status;
  end if;

  update class_daily_activities
  set status = 'approved', approved_by = my_employee_id(), approved_at = now()
  where id = p_activity_id;

  if v_activity.assignee_employee_id is not null then
    insert into notifications (notification_type, title, body, channels, target_employee_id, payload)
    values (
      'childcare_class_activity_approved', 'クラス活動が承認されました', null, array['in_app'],
      v_activity.assignee_employee_id, jsonb_build_object('activity_id', p_activity_id)
    );
  end if;
end;
$$;

-- 差し戻し(管理者のみ、理由必須)。
create or replace function reject_class_activity(p_activity_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_activity class_daily_activities%rowtype;
  v_office_id uuid;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason is required';
  end if;

  select * into v_activity from class_daily_activities where id = p_activity_id for update;
  if v_activity.id is null then
    raise exception 'class activity not found';
  end if;
  select office_id into v_office_id from childcare_classes where id = v_activity.class_id;
  if not manages_childcare(v_office_id) then
    raise exception 'not authorized';
  end if;
  if v_activity.status <> 'submitted' then
    raise exception 'class activity is % and cannot be rejected', v_activity.status;
  end if;

  update class_daily_activities
  set status = 'rejected', rejected_reason = p_reason, approved_by = null, approved_at = null
  where id = p_activity_id;

  if v_activity.assignee_employee_id is not null then
    insert into notifications (notification_type, title, body, channels, target_employee_id, payload)
    values (
      'childcare_class_activity_rejected', 'クラス活動が差し戻されました', p_reason, array['in_app'],
      v_activity.assignee_employee_id, jsonb_build_object('activity_id', p_activity_id)
    );
  end if;
end;
$$;
