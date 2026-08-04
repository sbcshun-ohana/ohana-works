-- Phase 2 §2.4: 連絡帳(child_daily_contacts)の17時公開予約。
-- 確定: 承認=内容確定ゲート維持、公開=保護者アプリ閲覧解禁タイミングの制御(分離)。
-- 公開/予約は status='approved' が前提。公開時の保護者プッシュは type/category='childcare_contact'
-- (guardian_notice/childcare_attendance と非混在)、opt-out尊重。範囲=staff側の公開/予約機構+outbox生成まで。
--
-- 不変条件(2026-08-04 俊):
--  (1) 承認〜公開予約設定の間に保護者可視のギャップを作らない → 可視は published_at 単独基準に統一し、
--      approve 時に既定で「当日17:00」予約をセット(published_at は NULL のまま=公開まで不可視)。
--  (2) 予約取消が即時公開にならない → 取消は scheduled_publish_at を NULL にするのみ(published_at 不変)。
-- 既存 approved 行は旧ルールで可視だったため published_at をバックフィルして可視を維持する。

-- 1) 列追加
alter table child_daily_contacts
  add column scheduled_publish_at timestamptz,
  add column published_at timestamptz;

-- 2) 既存 approved 行のバックフィル(旧ルールで可視だった行を可視のまま維持)
update child_daily_contacts
set published_at = coalesce(approved_at, updated_at, now())
where status = 'approved' and published_at is null;

-- 3) 保護者SELECTポリシーを published_at 単独基準へ差し替え
drop policy child_daily_contacts_select_guardian on child_daily_contacts;
create policy child_daily_contacts_select_guardian on child_daily_contacts
  for select using (
    status = 'approved'
    and published_at is not null
    and published_at <= now()
    and guardian_has_child_access(child_id)
  );

-- 4) 承認RPCを改修: 承認と同時に既定で「当日17:00(JST)」予約をセット(published_at は触らない)。
--    既に予約があればそれを尊重。承認が17時以降なら過去時刻となり毎分cronが直近で公開する(仕様上許容)。
create or replace function approve_child_daily_contact(
  p_contact_id uuid,
  p_final_text text default null,
  p_admin_comment text default null
)
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
  if not manages_childcare(v_office_id) then
    raise exception 'not authorized';
  end if;
  if v_contact.status <> 'submitted' then
    raise exception 'contact is % and cannot be approved', v_contact.status;
  end if;

  update child_daily_contacts
  set
    status = 'approved',
    approved_by = my_employee_id(),
    approved_at = now(),
    current_text = coalesce(p_final_text, current_text),
    admin_comment = p_admin_comment,
    scheduled_publish_at = coalesce(
      v_contact.scheduled_publish_at,
      ((v_contact.business_date::timestamp + time '17:00') at time zone 'Asia/Tokyo')
    )
  where id = p_contact_id;

  if v_contact.assignee_employee_id is not null then
    insert into notifications (notification_type, title, body, channels, target_employee_id, payload)
    values (
      'childcare_contact_approved', '連絡帳が承認されました', p_admin_comment, array['in_app'],
      v_contact.assignee_employee_id, jsonb_build_object('contact_id', p_contact_id)
    );
  end if;
end;
$$;

-- 5) 公開時の保護者プッシュ生成(共通ヘルパー)。opt-out(category='childcare_contact')尊重。
create or replace function generate_daily_contact_pushes(p_contact_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into notifications (notification_type, title, body, channels, target_guardian_id, payload, status)
  select
    'childcare_contact',
    c.display_name || coalesce(c.honorific_suffix_resolved, '') || 'の連絡帳が届きました',
    '本日の連絡帳が公開されました。',
    array['push'],
    gcl.guardian_id,
    jsonb_build_object('contact_id', cdc.id::text, 'child_id', c.id::text),
    'pending'
  from child_daily_contacts cdc
  join children c on c.id = cdc.child_id
  join guardian_child_links gcl on gcl.child_id = c.id
  where cdc.id = any(p_contact_ids)
    and not exists (
      select 1 from guardian_notification_settings s
      where s.guardian_id = gcl.guardian_id
        and s.category = 'childcare_contact' and s.enabled = false
    );
end;
$$;

-- 6) 公開予約(時刻設定/変更)。主任以上・approved・未公開のみ。個別/クラス/施設は呼出側が contact_ids で渡す。
create or replace function schedule_child_daily_contacts(p_contact_ids uuid[], p_scheduled_at timestamptz)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_count int;
begin
  if exists (
    select 1 from child_daily_contacts cdc join children c on c.id = cdc.child_id
    where cdc.id = any(p_contact_ids) and not manages_childcare(c.office_id)
  ) then
    raise exception 'not authorized';
  end if;

  update child_daily_contacts
  set scheduled_publish_at = p_scheduled_at
  where id = any(p_contact_ids) and status = 'approved' and published_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- 7) 即時公開。主任以上・approved・未公開のみ。published_at=now() を入れてプッシュ生成。
create or replace function publish_child_daily_contacts_now(p_contact_ids uuid[])
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_published uuid[];
begin
  if exists (
    select 1 from child_daily_contacts cdc join children c on c.id = cdc.child_id
    where cdc.id = any(p_contact_ids) and not manages_childcare(c.office_id)
  ) then
    raise exception 'not authorized';
  end if;

  with pub as (
    update child_daily_contacts
    set published_at = now()
    where id = any(p_contact_ids) and status = 'approved' and published_at is null
    returning id
  )
  select coalesce(array_agg(id), '{}') into v_published from pub;

  perform generate_daily_contact_pushes(v_published);
  return coalesce(array_length(v_published, 1), 0);
end;
$$;

-- 8) 予約取消。主任以上・未公開のみ。scheduled_publish_at のみ NULL 化(published_at 不変=不可視のまま保持)。
create or replace function cancel_child_daily_contacts_schedule(p_contact_ids uuid[])
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_count int;
begin
  if exists (
    select 1 from child_daily_contacts cdc join children c on c.id = cdc.child_id
    where cdc.id = any(p_contact_ids) and not manages_childcare(c.office_id)
  ) then
    raise exception 'not authorized';
  end if;

  update child_daily_contacts
  set scheduled_publish_at = null
  where id = any(p_contact_ids) and status = 'approved' and published_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- 9) pg_cron 毎分: 到来した予約を公開(published_at=now())→保護者プッシュ生成。
--    既存 dispatch-pending-notifications(毎分)が pending 行をFCM送信する。
create or replace function cron_publish_due_daily_contacts()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_published uuid[];
begin
  with due as (
    update child_daily_contacts
    set published_at = now()
    where status = 'approved'
      and published_at is null
      and scheduled_publish_at is not null
      and scheduled_publish_at <= now()
    returning id
  )
  select coalesce(array_agg(id), '{}') into v_published from due;

  perform generate_daily_contact_pushes(v_published);
end;
$$;

select cron.schedule(
  'publish_due_daily_contacts',
  '* * * * *',
  $$select cron_publish_due_daily_contacts();$$
);
