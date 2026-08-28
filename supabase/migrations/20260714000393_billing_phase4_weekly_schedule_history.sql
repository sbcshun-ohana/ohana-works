-- 393: 請求決済 Phase4 — 週次予定(child_weekly_schedule)の期間履歴化(詳細設計§5・2026-08-28俊承認)。
--   「上書き」から「履歴」へ: 過去月の予定を当時の値で再現(請求の月次再現)+変更の履歴保全。
--   AC-23互換が最重要: 既存RPCのシグネチャ・返却形は不変。既存データは effective_from='2026-04-01'
--   で全行有効のまま=適用直後の動作は完全に同一。
--   AC-04入力制限: 契約がある園児のみ契約時間の範囲でチェック(契約が無い園児は従来どおり無制限=回帰防止)。
--   消費者はRPC経由のみ(Kids/adminとも)。直接テーブルRLSは既存のまま(直接書き込みは現状どこにも無い)。

-- ============================================================
-- (1) 期間列の追加+一意制約→期間重複exclusionへ変更
-- ============================================================
alter table child_weekly_schedule
  add column if not exists effective_from date not null default '2026-04-01',
  add column if not exists effective_to date;

-- 既存データのバックフィル完了後はdefault不要(直接insertの黙った2026-04-01起点を防ぐ=fail loud)
alter table child_weekly_schedule alter column effective_from drop default;

-- 旧unique制約の削除はfail loud(名前不一致で黙って残ると、後日のset変更時にunique violationで爆発する)
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'child_weekly_schedule_child_id_weekday_key'
      and conrelid = 'child_weekly_schedule'::regclass
  ) then
    raise exception '旧unique制約 child_weekly_schedule_child_id_weekday_key が見つかりません(名前を確認して393を修正すること)';
  end if;
end $$;
alter table child_weekly_schedule
  drop constraint child_weekly_schedule_child_id_weekday_key;

alter table child_weekly_schedule
  add constraint child_weekly_schedule_period_valid
    check (effective_to is null or effective_to >= effective_from);

alter table child_weekly_schedule
  add constraint child_weekly_schedule_no_overlap exclude using gist (
    child_id with =,
    weekday with =,
    daterange(effective_from, coalesce(effective_to, 'infinity'::date), '[]') with &&
  );

comment on table child_weekly_schedule is
  '園児ごとの週次標準保育時間(期間履歴・393で履歴化)。対象日に有効な行=effective_from<=日<=effective_to(null=継続)。'
  '設定=主任以上(RPC経由・今日から閉じて作る)、閲覧=担当施設の職員。日別overrideは child_daily_attendance.scheduled_* が優先。';

-- ============================================================
-- (2) fetch_child_weekly_schedule — 今日(JST)時点で有効な行を返す(シグネチャ不変=AC-23)
-- ============================================================
create or replace function fetch_child_weekly_schedule(p_child_id uuid)
returns table (weekday int, scheduled_start_at time, scheduled_end_at time)
language plpgsql stable security definer set search_path = public as $$
declare
  v_office uuid;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  return query
    select s.weekday, s.scheduled_start_at, s.scheduled_end_at
    from child_weekly_schedule s
    where s.child_id = p_child_id
      and s.effective_from <= v_today
      and (s.effective_to is null or s.effective_to >= v_today)
    order by s.weekday;
end; $$;

-- ============================================================
-- (3) fetch_child_weekly_schedule_asof — 任意日時点の照会(履歴・未来の参照用・新規)
-- ============================================================
create or replace function fetch_child_weekly_schedule_asof(p_child_id uuid, p_ref_date date)
returns table (weekday int, scheduled_start_at time, scheduled_end_at time)
language plpgsql stable security definer set search_path = public as $$
declare
  v_office uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  return query
    select s.weekday, s.scheduled_start_at, s.scheduled_end_at
    from child_weekly_schedule s
    where s.child_id = p_child_id
      and s.effective_from <= p_ref_date
      and (s.effective_to is null or s.effective_to >= p_ref_date)
    order by s.weekday;
end; $$;
grant execute on function fetch_child_weekly_schedule_asof(uuid, date) to authenticated, service_role;

-- ============================================================
-- (4) set_child_weekly_schedule — 「今日から変更」(閉じて作る・同日再編集は上書き)。
--     AC-04: 本日有効な契約がある場合のみ、契約時間(土曜特例+月極延長の延長分を含む)の
--     範囲外を日本語エラーで拒否。契約が無い園児は従来どおり制限なし。
-- ============================================================
create or replace function set_child_weekly_schedule(
  p_child_id uuid, p_weekday int, p_start time, p_end time
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_office uuid;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
  v_month date := date_trunc('month', (now() at time zone 'Asia/Tokyo')::date)::date;
  v_cur record;
  v_plan record;
  v_limit_start time;
  v_limit_end time;
  v_ext_end time;
begin
  if p_weekday < 1 or p_weekday > 7 then raise exception 'invalid weekday'; end if;
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;

  -- no-opガード(AC-04より先に判定): 値が現行と同一なら何もしない。
  -- adminモーダルは保存時に6曜日全てを再送するため、これが無いと未変更曜日の履歴が
  -- 保存のたびに増殖し、既存値が契約範囲外の場合に保存全体が途中失敗する(Fableレビュー中-2/中-3)。
  select * into v_cur from child_weekly_schedule
  where child_id = p_child_id and weekday = p_weekday
    and effective_from <= v_today
    and (effective_to is null or effective_to >= v_today);
  if v_cur.id is not null
     and v_cur.scheduled_start_at is not distinct from p_start
     and v_cur.scheduled_end_at   is not distinct from p_end then
    return;
  end if;

  -- AC-04: 本日有効な契約プランの範囲チェック(開始・終了とも入力されている場合のみ)
  if p_start is not null and p_end is not null then
    select p.usage_start, p.usage_end, p.saturday_usage_end, p.name
      into v_plan
    from child_contracts cc
    join contract_plans p on p.id = cc.contract_plan_id
    where cc.child_id = p_child_id
      and cc.start_month <= v_month
      and (cc.end_month is null or cc.end_month >= v_month)
    order by cc.start_month desc
    limit 1;
    if v_plan.usage_start is not null then
      v_limit_start := v_plan.usage_start;
      v_limit_end := case when p_weekday = 6 and v_plan.saturday_usage_end is not null
                          then v_plan.saturday_usage_end else v_plan.usage_end end;
      -- 月極延長(大和)加入中は延長カバー時刻まで許容(土曜にも適用=入力を誤って弾かない安全側。
      -- 土曜の延長上限の厳密な扱いはPhase6延長計算エンジンで確定する)
      select max(m.coverage_end) into v_ext_end
      from child_extension_contracts ec
      join monthly_extension_plans m on m.id = ec.monthly_extension_plan_id
      where ec.child_id = p_child_id
        and ec.start_month <= v_month
        and (ec.end_month is null or ec.end_month >= v_month);
      if v_ext_end is not null and v_ext_end > v_limit_end then
        v_limit_end := v_ext_end;
      end if;
      if p_start < v_limit_start or p_end > v_limit_end then
        raise exception '契約時間(%〜%)の範囲外です(契約プラン: %)',
          to_char(v_limit_start, 'HH24:MI'), to_char(v_limit_end, 'HH24:MI'), v_plan.name;
      end if;
    end if;
  end if;

  -- 園児単位で直列化
  perform 1 from children where id = p_child_id for update;

  select * into v_cur from child_weekly_schedule
  where child_id = p_child_id and weekday = p_weekday
    and effective_from <= v_today
    and (effective_to is null or effective_to >= v_today);

  if v_cur.id is not null and v_cur.effective_from = v_today then
    -- 同日の再編集は上書き(行を増殖させない)
    update child_weekly_schedule
       set scheduled_start_at = p_start, scheduled_end_at = p_end,
           updated_by = my_employee_id(), updated_at = now()
     where id = v_cur.id;
  else
    if v_cur.id is not null then
      update child_weekly_schedule
         set effective_to = v_today - 1,
             updated_by = my_employee_id(), updated_at = now()
       where id = v_cur.id;
    end if;
    insert into child_weekly_schedule
      (child_id, weekday, scheduled_start_at, scheduled_end_at, effective_from, updated_by, updated_at)
    values
      (p_child_id, p_weekday, p_start, p_end, v_today, my_employee_id(), now());
  end if;
end; $$;

-- ============================================================
-- (5) delete_child_weekly_schedule — 「今日から通わない」(履歴は残す)
-- ============================================================
create or replace function delete_child_weekly_schedule(p_child_id uuid, p_weekday int)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_office uuid;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
  v_cur record;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;

  perform 1 from children where id = p_child_id for update;

  select * into v_cur from child_weekly_schedule
  where child_id = p_child_id and weekday = p_weekday
    and effective_from <= v_today
    and (effective_to is null or effective_to >= v_today);
  if v_cur.id is null then return; end if;   -- 従来のdelete同様、無ければ何もしない

  if v_cur.effective_from = v_today then
    -- 今日作った行はそのまま削除(過去の履歴には影響しない)
    delete from child_weekly_schedule where id = v_cur.id;
  else
    update child_weekly_schedule
       set effective_to = v_today - 1,
           updated_by = my_employee_id(), updated_at = now()
     where id = v_cur.id;
  end if;
end; $$;

-- ============================================================
-- (6) fetch_daily_board_for_office — 186の定義を踏襲し、週次joinのみ「対象日に有効な行」へ変更。
--     変更点は ws join の期間条件2行のみ(それ以外は186と一字一句同一)。
-- ============================================================
drop function if exists fetch_daily_board_for_office(uuid, date);

create function fetch_daily_board_for_office(p_office_id uuid, p_business_date date)
returns table (
  child_id uuid,
  display_name text,
  honorific_suffix text,
  class_id uuid,
  class_name text,
  status text,
  last_event_type text,
  last_event_at timestamptz,
  family_daily_report_status text,
  temperature numeric,
  has_pickup_change boolean,
  pickup_person_name text,
  pickup_person_relationship text,
  pickup_time_from time,
  pickup_time_to time,
  contact_id uuid,
  contact_status text,
  contact_scheduled_publish_at timestamptz,
  contact_published_at timestamptz,
  on_therapy_outing boolean,
  therapy_out_at timestamptz,
  therapy_provider_name text,
  arrival_at timestamptz,
  departure_at timestamptz,
  out_at timestamptz,
  return_at timestamptz,
  scheduled_start_at time,
  scheduled_end_at time,
  attendance_kind text,
  attendance_note text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not has_childcare_office_access(p_office_id) then
    raise exception 'not authorized';
  end if;

  return query
  select
    c.id, c.display_name, c.honorific_suffix_resolved, cc.id, cc.class_name,
    coalesce(dcs.status, 'not_arrived'),
    cae.event_type, cae.occurred_at,
    fdr.status,
    fdr.temperature,
    (fdr.pickup_person_name is not null),
    fdr.pickup_person_name,
    fdr.pickup_person_relationship,
    fdr.pickup_time_from,
    fdr.pickup_time_to,
    cdc.id, cdc.status, cdc.scheduled_publish_at, cdc.published_at,
    (te.event_type = 'out'),
    case when te.event_type = 'out' then te.occurred_at end,
    case when te.event_type = 'out' then te.provider_name end,
    ev.arrival_at,
    ev.departure_at,
    ev.out_at,
    ev.return_at,
    coalesce(cda.scheduled_start_at, ws.scheduled_start_at),
    coalesce(cda.scheduled_end_at,   ws.scheduled_end_at),
    cda.attendance_kind,
    cda.attendance_note
  from children c
  join child_class_enrollments cce on cce.child_id = c.id
    and cce.effective_start_date <= p_business_date
    and (cce.effective_end_date is null or cce.effective_end_date >= p_business_date)
  join childcare_classes cc on cc.id = cce.class_id
  left join daily_child_status dcs on dcs.child_id = c.id and dcs.business_date = p_business_date
  left join child_attendance_events cae on cae.id = dcs.last_event_id
  left join family_daily_reports fdr on fdr.child_id = c.id and fdr.business_date = p_business_date
  left join child_daily_contacts cdc on cdc.child_id = c.id and cdc.business_date = p_business_date
  left join child_daily_attendance cda on cda.child_id = c.id and cda.business_date = p_business_date
  left join child_weekly_schedule ws on ws.child_id = c.id
    and ws.weekday = extract(isodow from p_business_date)::int
    and ws.effective_from <= p_business_date
    and (ws.effective_to is null or ws.effective_to >= p_business_date)
  left join lateral (
    select e.event_type, e.occurred_at, tp.name as provider_name
    from therapy_outing_events e
    join therapy_providers tp on tp.id = e.provider_id
    where e.child_id = c.id and (e.occurred_at at time zone 'Asia/Tokyo')::date = p_business_date
    order by e.occurred_at desc
    limit 1
  ) te on true
  left join lateral (
    select
      min(e2.occurred_at) filter (where e2.event_type in ('drop_off','proxy_drop_off')) as arrival_at,
      max(e2.occurred_at) filter (where e2.event_type in ('pick_up','proxy_pick_up'))   as departure_at,
      max(e2.occurred_at) filter (where e2.event_type = 'out')    as out_at,
      max(e2.occurred_at) filter (where e2.event_type = 'return') as return_at
    from child_attendance_events e2
    where e2.child_id = c.id
      and (e2.occurred_at at time zone 'Asia/Tokyo')::date = p_business_date
  ) ev on true
  where c.office_id = p_office_id and c.enrollment_status <> '退園済み'
  order by cc.age_group, cc.class_name, c.display_name;
end;
$$;

grant execute on function fetch_daily_board_for_office(uuid, date) to authenticated;

-- 防御多層(388以降の慣行。既存3RPCのACLは維持しつつ新規のみ明示)
revoke execute on function fetch_child_weekly_schedule_asof(uuid, date) from public, anon;
