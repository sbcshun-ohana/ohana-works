-- 196: 連絡帳で保護者に知らせる検温を「その日の全件」にする(俊確定 2026-08-12)。
-- 195は temperature 欄へ最新1件をセット(=代表値として維持)。本196は追加で、公開時に園側検温の
-- 当日全件を時刻昇順で本文末尾へスナップショット追記する(189のお知らせ取込と同型)。
--   ・追記形式: 「【検温】HH:MM XX.X℃ / HH:MM XX.X℃ …」(measured_at 昇順・" / " 区切り)
--   ・契機: 公開共有フック(即時 publish_child_daily_contacts_now / 17時cron cron_publish_due_daily_contacts)
--   ・二重追記防止マーカー(189同様)。公開後の再反映なし。園側検温が0件なら追記しない。
--   ・195の temperature 欄(代表値=最新1件)セットは維持。
--
-- 冪等: create or replace / 列追加は if not exists。

-- 二重追記防止マーカー(この連絡帳へ検温全件を追記済みか)
alter table child_daily_contacts
  add column if not exists temperature_records_applied_at timestamptz;

-- 公開した連絡帳の本文末尾へ、当日の園側検温全件を昇順で追記(未追記時のみ)。
create or replace function apply_temperature_records_snapshot_to_contact(p_contact_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_child uuid; v_date date; v_applied timestamptz; v_line text;
begin
  select child_id, business_date, temperature_records_applied_at
    into v_child, v_date, v_applied
  from child_daily_contacts where id = p_contact_id;
  if v_child is null then return; end if;
  if v_applied is not null then return; end if;  -- 二重防止: 追記済みなら何もしない

  -- 当日の園側検温を時刻昇順で "HH:MM XX.X℃" に整形し " / " 連結。
  select string_agg(
           to_char(measured_at, 'HH24:MI') || ' ' || (temperature::text) || '℃',
           ' / ' order by measured_at)
    into v_line
  from child_temperature_records
  where child_id = v_child and business_date = v_date;

  if v_line is null then return; end if;  -- 検温0件なら追記しない(マーカーも立てない)

  update child_daily_contacts
  set current_text = coalesce(current_text, '')
        || case when coalesce(btrim(current_text), '') = '' then '' else E'\n\n' end
        || '【検温】' || v_line,
      temperature_records_applied_at = now()
  where id = p_contact_id;
end; $$;

-- 即時公開: 195の定義に検温全件追記フックを1行追加(他は不変)。
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

  foreach r in array v_published loop
    perform apply_class_announcement_to_contact(r);          -- 189: クラスお知らせ取込
    perform apply_latest_temperature_to_contact(r);          -- K8: 園側最新検温を未入力時のみ反映
    perform apply_temperature_records_snapshot_to_contact(r); -- 196: 本文末尾へ当日検温全件
  end loop;

  perform generate_daily_contact_pushes(v_published);
  return coalesce(array_length(v_published, 1), 0);
end; $$;

-- 17時cron公開: 同様に検温全件追記フックを1行追加。
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

  foreach r in array v_published loop
    perform apply_class_announcement_to_contact(r);          -- 189: クラスお知らせ取込
    perform apply_latest_temperature_to_contact(r);          -- K8: 園側最新検温を未入力時のみ反映
    perform apply_temperature_records_snapshot_to_contact(r); -- 196: 本文末尾へ当日検温全件
  end loop;

  perform generate_daily_contact_pushes(v_published);
end; $$;
