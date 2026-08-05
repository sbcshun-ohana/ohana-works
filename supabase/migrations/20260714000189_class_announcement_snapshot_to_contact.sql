-- 189: クラス活動の「クラス全体へのお知らせ」を、公開時に対象児の連絡帳本文へスナップショット追記。
-- 俊確定: 方式=スナップショット本文取込 / 対象=当日登園児のみ / 連絡帳行の自動生成なし(承認済み連絡帳のみ) /
--   公開後の自動反映なし・事後修正は主任以上 / 全保護者へ確実に届ける内容は一斉配信の守備範囲。
-- ①取込条件=クラス活動 status='approved'(俊確定・承認まで毎日回す運用。公開=保護者可視のため承認済みに限定)。
-- ②class_announcement が空/空白のみはスキップ。 (e)適用済 activity_id マーカーで二重防止。

-- マーカー列(どのクラス活動お知らせを適用済みか)
alter table child_daily_contacts
  add column class_announcement_applied_activity_id uuid references class_daily_activities(id) on delete set null,
  add column class_announcement_applied_at timestamptz;

-- 取込関数: 対象児が当日登園 & クラスに承認済み非空お知らせあり & 未適用 の時のみ、current_text 末尾へ見出し付き追記。
-- security definer(公開処理から呼ぶ)。元お知らせのコピー=スナップショット(以降は通常本文として個別編集/削除可)。
create or replace function apply_class_announcement_to_contact(p_contact_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_child uuid; v_date date; v_applied uuid; v_class uuid;
  v_activity_id uuid; v_announcement text; v_attended boolean;
begin
  select child_id, business_date, class_announcement_applied_activity_id
    into v_child, v_date, v_applied
  from child_daily_contacts where id = p_contact_id;
  if v_child is null then return; end if;

  -- 当日登園判定(欠席=absent・未登園=not_arrived は対象外)
  select coalesce(dcs.status in ('present','picked_up'), false) into v_attended
  from daily_child_status dcs where dcs.child_id = v_child and dcs.business_date = v_date;
  if not coalesce(v_attended, false) then return; end if;

  -- 児の当日クラス(連絡帳の business_date 時点の実効在籍で class_id を解決。163=在籍判定は日付基準)
  select cce.class_id into v_class
  from child_class_enrollments cce
  where cce.child_id = v_child and cce.effective_start_date <= v_date
    and (cce.effective_end_date is null or cce.effective_end_date >= v_date)
  order by cce.effective_start_date desc limit 1;
  if v_class is null then return; end if;

  -- クラスの当日お知らせ(①承認済み)
  select cda.id, cda.class_announcement into v_activity_id, v_announcement
  from class_daily_activities cda
  where cda.class_id = v_class and cda.business_date = v_date and cda.status = 'approved';
  if v_activity_id is null then return; end if;
  if v_announcement is null or btrim(v_announcement) = '' then return; end if;  -- ②空スキップ

  -- (e)二重防止: 同一クラス活動を適用済みなら何もしない
  if v_applied is not null and v_applied = v_activity_id then return; end if;

  -- (c)current_text 末尾へ見出し付き追記 + マーカー記録
  update child_daily_contacts
  set current_text = coalesce(current_text, '')
        || case when coalesce(btrim(current_text), '') = '' then '' else E'\n\n' end
        || '【クラスからのお知らせ】' || E'\n' || v_announcement,
      class_announcement_applied_activity_id = v_activity_id,
      class_announcement_applied_at = now()
  where id = p_contact_id;
end; $$;

-- 公開(即時): 166の関数を再作成し、公開直後に取込フックを追加(既存挙動は不変)。
create or replace function publish_child_daily_contacts_now(p_contact_ids uuid[])
returns int language plpgsql security definer set search_path = public as $$
declare v_published uuid[]; r uuid;
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

  -- 189: 公開した連絡帳へクラスお知らせをスナップショット追記(登園児のみ・非空・二重防止)
  foreach r in array v_published loop
    perform apply_class_announcement_to_contact(r);
  end loop;

  perform generate_daily_contact_pushes(v_published);
  return coalesce(array_length(v_published, 1), 0);
end; $$;

-- 公開(17時cron): 166の関数を再作成し、同じ取込フックを追加。
create or replace function cron_publish_due_daily_contacts()
returns void language plpgsql security definer set search_path = public as $$
declare v_published uuid[]; r uuid;
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

  -- 189: 公開した連絡帳へクラスお知らせをスナップショット追記
  foreach r in array v_published loop
    perform apply_class_announcement_to_contact(r);
  end loop;

  perform generate_daily_contact_pushes(v_published);
end; $$;
