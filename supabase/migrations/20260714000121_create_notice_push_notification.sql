-- P0: イベント駆動プッシュ通知の自動化(4/4: 個別連絡・グループ連絡)。
--
-- create_notice(20260714000117)は「個別」「グループ」カテゴリで送信時点の受信者を
-- notice_recipientsへスナップショット展開済み。同じ対象者リストへ、1回のINSERT文で
-- notifications(outbox)行もまとめて積む(会社一斉/園単位/役職別はRLSベースの閲覧制御のみで
-- 受信者テーブルを持たないため、Push対応は対象者解決ロジックが別途必要になり本マイグレーションの
-- 対象外)。

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

    insert into notifications (
      notification_type, title, body, channels, target_employee_id, payload, status
    )
    select 'notice', p_title, p_body, array['fcm', 'in_app'], e_id, jsonb_build_object('notice_id', v_notice_id), 'pending'
    from unnest(p_individual_employee_ids) as e_id;
  elsif p_category = 'グループ' then
    insert into notice_recipients (notice_id, employee_id)
    select v_notice_id, sgm.employee_id
    from staff_group_members sgm
    where sgm.group_id = p_target_group_id and sgm.removed_at is null;

    insert into notifications (
      notification_type, title, body, channels, target_employee_id, payload, status
    )
    select 'notice', p_title, p_body, array['fcm', 'in_app'], sgm.employee_id, jsonb_build_object('notice_id', v_notice_id), 'pending'
    from staff_group_members sgm
    where sgm.group_id = p_target_group_id and sgm.removed_at is null;
  end if;

  return v_notice_id;
end;
$$;

comment on function create_notice(notice_category, text, text, uuid, uuid, uuid, uuid[], boolean, text[]) is
  'admin_web向け。お知らせ作成の共通RPC(会社一斉/園単位/役職別/個別/グループ)。
   勤務交代関連・災害モードは既存の専用フロー(shift_change_requests/disaster_events)経由のため対象外。
   個別/グループはnotice_recipientsと同時にnotifications(outbox)へも展開しPush配信対象とする
   (20260714000118〜。会社一斉/園単位/役職別は対象者解決ロジックが別途必要なため未対応)。
   既読管理はアプリ内(notice_recipients.read_at)のみ。';
