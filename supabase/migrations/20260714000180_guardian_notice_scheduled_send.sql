-- 一斉配信 D-1: 配信予定日。D-2: 配信履歴fetch。
-- 意味論: 配信は status='approved' AND sent_at IS NULL AND scheduled_send_at<=now() のみ(cron毎分)。
-- 取消は status='draft' へ戻して配信対象から外す(scheduled_send_at は触らない)。null=即時は approve時のみ。
-- 配信済み判定は sent_at 一貫。予定変更・取消・再承認を一巡しても未配信が意図せず飛ばない。

alter table guardian_notices add column scheduled_send_at timestamptz;

-- 配信本体(recipients確定+outbox生成+sent_at)。sent_at済みは何もしない(冪等)。161のロジックを踏襲。
create or replace function deliver_guardian_notice(p_notice_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_title text; v_body text; v_sent timestamptz;
begin
  select title, body, sent_at into v_title, v_body, v_sent from guardian_notices where id = p_notice_id;
  if v_title is null or v_sent is not null then return; end if;  -- 未存在 or 既配信

  insert into guardian_notice_recipients (notice_id, guardian_id, child_id)
  select p_notice_id, r.guardian_id, r.child_id
  from resolve_guardian_notice_recipients(p_notice_id) r
  on conflict (notice_id, guardian_id, child_id) do nothing;

  insert into notifications (notification_type, title, body, channels, target_guardian_id, payload, status)
  select 'guardian_notice',
    case when char_length(t.full_title) > 20 then left(t.full_title, 20) || '…' else t.full_title end,
    v_body, array['push'], t.guardian_id,
    jsonb_build_object('notice_id', p_notice_id::text, 'child_id', t.child_id), 'pending'
  from (
    select r.guardian_id, r.child_id,
      case when r.child_id is not null then '【' || c.display_name || coalesce(c.honorific_suffix,'') || '】' || v_title else v_title end as full_title
    from guardian_notice_recipients r left join children c on c.id = r.child_id
    where r.notice_id = p_notice_id
      and not exists (select 1 from guardian_notification_settings s
        where s.guardian_id = r.guardian_id and s.category = 'guardian_notice' and s.enabled = false)
  ) t;

  update guardian_notices set sent_at = now() where id = p_notice_id;
end; $$;

-- 承認(+配信予定日)。未来なら予約のみ・配信せず。null/過去なら即時配信。
create or replace function approve_guardian_notice(p_notice_id uuid, p_scheduled_send_at timestamptz default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_status text;
begin
  select status into v_status from guardian_notices where id = p_notice_id;
  if v_status is null then raise exception 'not found'; end if;
  if v_status not in ('draft', 'in_review') then raise exception 'invalid state'; end if;
  if not is_guardian_notice_approver(p_notice_id) then raise exception 'not authorized to approve'; end if;

  if p_scheduled_send_at is null or p_scheduled_send_at <= now() then
    update guardian_notices set status='approved', approver_id=my_employee_id(), approved_at=now(), scheduled_send_at=null where id=p_notice_id;
    perform deliver_guardian_notice(p_notice_id);   -- 即時配信(sent_at設定)
  else
    update guardian_notices set status='approved', approver_id=my_employee_id(), approved_at=now(), scheduled_send_at=p_scheduled_send_at where id=p_notice_id;
    -- 予約のみ。sent_at は NULL のまま。cron が到来時に配信。
  end if;
end; $$;

-- 予定変更(未配信のみ)。approver。
create or replace function reschedule_guardian_notice(p_notice_id uuid, p_scheduled_send_at timestamptz)
returns void language plpgsql security definer set search_path = public as $$
declare v_status text; v_sent timestamptz;
begin
  select status, sent_at into v_status, v_sent from guardian_notices where id = p_notice_id;
  if v_status is null then raise exception 'not found'; end if;
  if v_sent is not null then raise exception 'already sent'; end if;
  if v_status <> 'approved' then raise exception 'not scheduled'; end if;
  if not is_guardian_notice_approver(p_notice_id) then raise exception 'not authorized'; end if;
  update guardian_notices set scheduled_send_at = p_scheduled_send_at where id = p_notice_id;
end; $$;

-- 配信取消(未配信のみ)= 下書きへ戻す。scheduled_send_at は触らない(即時配信の罠回避)。approver。
create or replace function cancel_scheduled_guardian_notice(p_notice_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_status text; v_sent timestamptz;
begin
  select status, sent_at into v_status, v_sent from guardian_notices where id = p_notice_id;
  if v_status is null then raise exception 'not found'; end if;
  if v_sent is not null then raise exception 'already sent'; end if;
  if v_status <> 'approved' then raise exception 'not scheduled'; end if;
  if not is_guardian_notice_approver(p_notice_id) then raise exception 'not authorized'; end if;
  update guardian_notices set status = 'draft', approver_id = null, approved_at = null where id = p_notice_id;
end; $$;

-- cron 毎分: 到来した予約を配信。
create or replace function cron_dispatch_scheduled_guardian_notices()
returns void language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in
    select id from guardian_notices
    where status = 'approved' and sent_at is null and revoked_at is null
      and scheduled_send_at is not null and scheduled_send_at <= now()
  loop
    perform deliver_guardian_notice(r.id);
  end loop;
end; $$;

select cron.schedule('dispatch_scheduled_guardian_notices', '* * * * *',
  $$select cron_dispatch_scheduled_guardian_notices();$$);

-- D-2 配信履歴: いつ・何時に・誰に・何世帯。宛先は guardian_notice_targets を名称解決。
create or replace function fetch_guardian_notice_delivery_history(p_office_id uuid)
returns table (
  notice_id uuid, title text, status text, scheduled_send_at timestamptz, sent_at timestamptz,
  revoked_at timestamptz, target_summary text, recipient_household_count int
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  return query
  select gn.id, gn.title, gn.status, gn.scheduled_send_at, gn.sent_at, gn.revoked_at,
    coalesce((
      select string_agg(
        case t.target_type
          when 'all' then '全体'
          when 'office' then '施設:' || o.name
          when 'class' then 'クラス:' || cc.class_name
          when 'child' then '園児:' || ch.display_name
        end, ' / ')
      from guardian_notice_targets t
      left join offices o on o.id = t.office_id
      left join childcare_classes cc on cc.id = t.class_id
      left join children ch on ch.id = t.child_id
      where t.notice_id = gn.id
    ), '—'),
    (select count(distinct guardian_id)::int from guardian_notice_recipients where notice_id = gn.id)
  from guardian_notices gn
  where exists (
    select 1 from guardian_notice_targets t
    left join childcare_classes cc on cc.id = t.class_id
    left join children ch on ch.id = t.child_id
    where t.notice_id = gn.id and (
      t.target_type = 'all' or t.office_id = p_office_id
      or cc.office_id = p_office_id or ch.office_id = p_office_id
    )
  )
  order by coalesce(gn.sent_at, gn.scheduled_send_at, gn.updated_at) desc;
end; $$;
