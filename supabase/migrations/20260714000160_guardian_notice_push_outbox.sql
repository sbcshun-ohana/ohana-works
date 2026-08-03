-- お知らせ(保護者向け一斉配信)Phase E: プッシュ配信。
-- 設計: docs/お知らせ_保護者向け一斉配信_調査設計_2026-07-30.md §6.4。
--   承認=送信時に recipients から notifications(target_guardian_id)を生成 →
--   dispatch-pending-notifications(pg_cron毎分)がFCM送信(guardian配信・payload伝搬は配線済)。
--   園児特定行(child_id あり)はタイトル冒頭に「【〇〇ちゃん】」(children.display_name+honorific)。
--   all/office(child_id null)は園児名なし。タイトルは全角20字目安・超過は「…」。
--   payload に notice_id/child_id を載せ、プッシュtap→詳細到達で既読(parent_app・Phase D)。
--
-- approve_guardian_notice(152)を差し替え、recipients確定の直後に outbox を生成する。
-- approve は status draft/in_review でのみ実行=1通につき1回のため二重生成なし。

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

  -- 配信時スナップショットを確定。
  insert into guardian_notice_recipients (notice_id, guardian_id, child_id)
  select p_notice_id, r.guardian_id, r.child_id
  from resolve_guardian_notice_recipients(p_notice_id) r
  on conflict on constraint uq_gnr_unique do nothing;

  -- Phase E: recipients から outbox(notifications)を生成。1 recipient 行=1プッシュ。
  --   園児特定行(child_id あり)はタイトル冒頭に「【園児名+敬称】」。all/office は園児名なし。
  --   タイトルは全角20字目安・超過は「…」(char_length で文字数計上)。
  insert into notifications (notification_type, title, body, channels, target_guardian_id, payload, status)
  select
    'guardian_notice',
    case
      when char_length(t.full_title) > 20 then left(t.full_title, 20) || '…'
      else t.full_title
    end,
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
      -- 配信可否(guardian_notification_settings): カテゴリ 'guardian_notice' を明示OFFにした
      -- 保護者にはプッシュ行を作らない(既定=行なし=ON)。in-app一覧の可視性(RLS)には影響しない。
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
