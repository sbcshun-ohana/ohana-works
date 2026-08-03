-- お知らせ Phase E 修正: 160 の approve_guardian_notice が recipients 挿入で
-- `on conflict on constraint uq_gnr_unique` を使っていたが、uq_gnr_unique は unique INDEX
-- (制約ではない)。153 と同じ列推論 `on conflict (notice_id, guardian_id, child_id)` に修正する。
-- outbox 生成ロジック(§6.4: 園児名タイトル・20字省略・opt-out尊重・payload)は 160 と同一。

create or replace function approve_guardian_notice(p_notice_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare v_status text; v_title text; v_body text;
begin
  select status, title, body into v_status, v_title, v_body from guardian_notices where id = p_notice_id;
  if v_status is null then raise exception 'not found'; end if;
  if v_status not in ('draft', 'in_review') then raise exception 'invalid state'; end if;
  if not is_guardian_notice_approver(p_notice_id) then
    raise exception 'not authorized to approve';
  end if;

  -- 配信時スナップショットを確定(153と同じ列推論の on conflict)。
  insert into guardian_notice_recipients (notice_id, guardian_id, child_id)
  select p_notice_id, r.guardian_id, r.child_id
  from resolve_guardian_notice_recipients(p_notice_id) r
  on conflict (notice_id, guardian_id, child_id) do nothing;

  -- Phase E: recipients から outbox(notifications)を生成。1 recipient 行=1プッシュ。
  insert into notifications (notification_type, title, body, channels, target_guardian_id, payload, status)
  select
    'guardian_notice',
    case when char_length(t.full_title) > 20 then left(t.full_title, 20) || '…' else t.full_title end,
    v_body,
    array['push'],
    t.guardian_id,
    jsonb_build_object('notice_id', p_notice_id::text, 'child_id', t.child_id),
    'pending'
  from (
    select
      r.guardian_id,
      r.child_id,
      case
        when r.child_id is not null then
          '【' || c.display_name || coalesce(c.honorific_suffix, '') || '】' || v_title
        else v_title
      end as full_title
    from guardian_notice_recipients r
    left join children c on c.id = r.child_id
    where r.notice_id = p_notice_id
      and not exists (
        select 1 from guardian_notification_settings s
        where s.guardian_id = r.guardian_id and s.category = 'guardian_notice' and s.enabled = false
      )
  ) t;

  update guardian_notices
  set status = 'approved', approver_id = my_employee_id(), approved_at = now(), sent_at = now()
  where id = p_notice_id;
end;
$$;
