-- グループ連絡: グループ管理RPC、および お知らせ全カテゴリ共通の作成RPC(create_notice)。
-- notices/notice_recipientsには従来「作成」用のRPCが存在せず(閲覧・既読・返信のみ)、
-- 個別連絡・グループ連絡のいずれも本ファイルで初めて作成手段を用意する。

create or replace function create_staff_group(
  p_office_id uuid,
  p_group_type staff_group_type,
  p_name text,
  p_related_class_id uuid default null,
  p_member_employee_ids uuid[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group_id uuid;
  v_employee_id uuid;
begin
  if not manages_office(p_office_id) then
    raise exception 'not authorized to create a staff group for this office';
  end if;

  insert into staff_groups (office_id, group_type, name, related_class_id, created_by)
  values (p_office_id, p_group_type, p_name, p_related_class_id, my_employee_id())
  returning id into v_group_id;

  foreach v_employee_id in array coalesce(p_member_employee_ids, '{}') loop
    insert into staff_group_members (group_id, employee_id) values (v_group_id, v_employee_id);
  end loop;

  return v_group_id;
end;
$$;

comment on function create_staff_group(uuid, staff_group_type, text, uuid, uuid[]) is
  'admin_web向け。グループ作成+初期メンバー登録。権限は施設管理者(manages_office)。';

create or replace function update_staff_group_members(
  p_group_id uuid,
  p_add_employee_ids uuid[] default '{}',
  p_remove_employee_ids uuid[] default '{}'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_employee_id uuid;
begin
  if not manages_staff_group(p_group_id) then
    raise exception 'not authorized to manage members of this staff group';
  end if;

  foreach v_employee_id in array coalesce(p_add_employee_ids, '{}') loop
    insert into staff_group_members (group_id, employee_id)
    values (p_group_id, v_employee_id)
    on conflict (group_id, employee_id)
      do update set removed_at = null, added_at = now();
  end loop;

  if p_remove_employee_ids is not null and array_length(p_remove_employee_ids, 1) is not null then
    update staff_group_members
    set removed_at = now()
    where group_id = p_group_id
      and employee_id = any(p_remove_employee_ids)
      and removed_at is null;
  end if;
end;
$$;

comment on function update_staff_group_members(uuid, uuid[], uuid[]) is
  'admin_web向け。グループメンバーの追加/除外(除外は論理削除、履歴を保持)。';

create or replace function archive_staff_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not manages_staff_group(p_group_id) then
    raise exception 'not authorized to archive this staff group';
  end if;

  update staff_groups
  set is_active = false, archived_at = now()
  where id = p_group_id;
end;
$$;

comment on function archive_staff_group(uuid) is
  'admin_web向け。グループを終了(is_active=false)。送信済みお知らせの宛先(notice_recipients)は
   送信時点でスナップショット済みのため、アーカイブ後も過去の既読・返信状況は変化しない。';

-- お知らせ作成(全カテゴリ共通)。カテゴリごとに権限チェックし、個別/グループの場合は
-- notice_recipients を送信時点で展開する(会社一斉/園単位/役職別は既存どおりRLS+開封時自己申告)。
create or replace function create_notice(
  p_category notice_category,
  p_title text,
  p_body text,
  p_target_office_id uuid default null,
  p_target_position_id uuid default null,
  p_target_group_id uuid default null,
  p_individual_employee_ids uuid[] default null,
  p_requires_read_confirmation boolean default false,
  p_standard_reply_options text[] default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_notice_id uuid;
  v_employee_id uuid;
begin
  case p_category
    when '会社一斉' then
      if not is_labor_manager_plus() then
        raise exception 'not authorized to send a company-wide notice';
      end if;
    when '園単位' then
      if p_target_office_id is null or not manages_office(p_target_office_id) then
        raise exception 'not authorized to send an office notice';
      end if;
    when '役職別' then
      if p_target_position_id is null or not is_labor_manager_plus() then
        raise exception 'not authorized to send a position notice';
      end if;
    when '個別' then
      if p_individual_employee_ids is null or array_length(p_individual_employee_ids, 1) is null then
        raise exception 'individual notice requires at least one recipient';
      end if;
      if exists (
        select 1 from employees e
        where e.id = any(p_individual_employee_ids) and not manages_office(e.home_office_id)
      ) then
        raise exception 'not authorized to send an individual notice to one or more recipients';
      end if;
    when 'グループ' then
      if p_target_group_id is null or not manages_staff_group(p_target_group_id) then
        raise exception 'not authorized to send a notice to this group';
      end if;
    else
      raise exception '勤務交代関連・災害モードは専用フローから作成してください';
  end case;

  insert into notices (
    category, title, body, target_office_id, target_position_id, target_group_id,
    requires_read_confirmation, standard_reply_options, created_by
  ) values (
    p_category, p_title, p_body, p_target_office_id, p_target_position_id, p_target_group_id,
    p_requires_read_confirmation, p_standard_reply_options, my_employee_id()
  )
  returning id into v_notice_id;

  if p_category = '個別' then
    foreach v_employee_id in array p_individual_employee_ids loop
      insert into notice_recipients (notice_id, employee_id) values (v_notice_id, v_employee_id);
    end loop;
  elsif p_category = 'グループ' then
    insert into notice_recipients (notice_id, employee_id)
    select v_notice_id, sgm.employee_id
    from staff_group_members sgm
    where sgm.group_id = p_target_group_id and sgm.removed_at is null;
  end if;

  return v_notice_id;
end;
$$;

comment on function create_notice(notice_category, text, text, uuid, uuid, uuid, uuid[], boolean, text[]) is
  'admin_web向け。お知らせ作成の共通RPC(会社一斉/園単位/役職別/個別/グループ)。
   勤務交代関連・災害モードは既存の専用フロー(shift_change_requests/disaster_events)経由のため対象外。
   Push通知配信は本タスクのスコープ外(P0のイベント駆動通知基盤に後日統合予定)。既読管理はアプリ内(notice_recipients.read_at)のみ。';
