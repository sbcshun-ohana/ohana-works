-- K8方針変更(俊確定 2026-08-12): 家庭での様子一覧の「園側最新検温」列は廃止(フロント側で削除)。
-- 代わりに、園側で記録した検温(child_temperature_records・188)を、連絡帳の公開時に
-- child_daily_contacts.temperature / temperature_measured_at へ自動反映する。
--   ・反映契機 = 公開時(即時公開 publish_child_daily_contacts_now / 17時cron
--     cron_publish_due_daily_contacts の共有ループ。189のお知らせ取込と同じ場所)。
--   ・条件 = 連絡帳の temperature が未入力(null)の場合のみセット。手入力済みは上書きしない。
--   ・値 = 園側検温の最新1件(measured_at 最大)の 体温・測定時刻。
--
-- あわせて、child_daily_contacts.temperature の CHECK(35.0〜42.0)を、園側検温(34.0〜42.0・188)と
-- 整合させるため 34.0〜42.0 へ緩和(34.x台の園側値も反映できるようにする)。
--
-- 冪等: create or replace / 制約は存在確認して張り替え。

-- (1) temperature CHECK を 34.0〜42.0 へ緩和。既存のインライン列CHECK(自動命名)を確実に外して張り直す。
do $$
declare c text;
begin
  select conname into c
  from pg_constraint
  where conrelid = 'child_daily_contacts'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) ilike '%temperature%'
    and pg_get_constraintdef(oid) not ilike '%measured%';
  if c is not null then
    execute format('alter table child_daily_contacts drop constraint %I', c);
  end if;
end $$;

alter table child_daily_contacts
  add constraint child_daily_contacts_temperature_check
  check (temperature is null or temperature between 34.0 and 42.0);

-- (2) 公開した連絡帳へ園側最新検温を反映(temperature 未入力時のみ・最新1件)。
create or replace function apply_latest_temperature_to_contact(p_contact_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_child uuid; v_date date; v_temp numeric; v_measured_at time;
begin
  select child_id, business_date, temperature into v_child, v_date, v_temp
  from child_daily_contacts where id = p_contact_id;
  if v_child is null then return; end if;
  if v_temp is not null then return; end if;  -- 手入力済みは上書きしない

  select temperature, measured_at into v_temp, v_measured_at
  from child_temperature_records
  where child_id = v_child and business_date = v_date
  order by measured_at desc limit 1;               -- 最新1件
  if v_temp is null then return; end if;           -- 園側検温が無ければ何もしない

  update child_daily_contacts
  set temperature = v_temp, temperature_measured_at = v_measured_at
  where id = p_contact_id and temperature is null; -- 二重ガード(競合時も未入力のみ)
end; $$;

-- (3) 即時公開: 189の関数を再作成し、公開ループに検温取込を1行追加(既存挙動は不変)。
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
    perform apply_class_announcement_to_contact(r);   -- 189: クラスお知らせ取込
    perform apply_latest_temperature_to_contact(r);   -- K8: 園側最新検温を未入力時のみ反映
  end loop;

  perform generate_daily_contact_pushes(v_published);
  return coalesce(array_length(v_published, 1), 0);
end; $$;

-- (4) 17時cron公開: 同様に検温取込を追加。
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
    perform apply_class_announcement_to_contact(r);   -- 189: クラスお知らせ取込
    perform apply_latest_temperature_to_contact(r);   -- K8: 園側最新検温を未入力時のみ反映
  end loop;

  perform generate_daily_contact_pushes(v_published);
end; $$;
