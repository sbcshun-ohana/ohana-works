-- 184: 出欠状況の格上げ + 週次標準保育時間(予定の二層・標準側)
-- デイリーボード刷新 Phase B の第1弾。追加列は全て nullable(後方互換)。
-- is_absent は引き続き権威(サマリー163が参照)。attendance_kind は追加情報で、
-- 種別なしの既存欠席は kind=NULL のまま(表示は「欠席」フォールバック・バックフィルしない)。
-- 既存 set_child_daily_attendance(簡易トグル)は変更しない。RPC/board改修は 185 で行う。

-- 出欠状況カラム
alter table child_daily_attendance
  add column attendance_kind text
    check (attendance_kind in ('none','late','early_leave','sick_absence','personal_absence')),
  add column scheduled_start_at time,   -- 当日の登園予定(週次標準の上書き)
  add column scheduled_end_at time,     -- 当日の降園予定
  add column scheduled_slot text,       -- 予定枠(標準/短時間/延長 等・自由記述)
  add column attendance_note text;      -- 出欠メモ(absence_reason=欠席理由 とは別)

comment on column child_daily_attendance.attendance_kind is
  '出欠種別: none(-)/late(遅刻)/early_leave(早退)/sick_absence(病欠)/personal_absence(都合欠)。'
  'NULL=種別未設定(既存欠席は欠席フォールバック表示)。遅刻/早退は出席側、is_absent同期は sick/personal のみ';

-- 週次標準保育時間(予定の標準側)。園児マスタ画面で職員が設定。
-- 曜日は ISO-8601(1=月..7=日, Dart DateTime.weekday と一致)。
create table child_weekly_schedule (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  weekday int not null check (weekday between 1 and 7),
  scheduled_start_at time,
  scheduled_end_at time,
  updated_by uuid references employees(id),
  updated_at timestamptz not null default now(),
  unique (child_id, weekday)
);
create index idx_child_weekly_schedule_child on child_weekly_schedule(child_id);

comment on column child_weekly_schedule.weekday is
  '曜日: ISO 8601 = 1:月曜 … 7:日曜(Dart DateTime.weekday と一致。admin_web(JS)は getDay()の0(日)を7に変換)';
comment on table child_weekly_schedule is
  '園児ごとの週次標準保育時間(予定の標準側)。設定=主任以上(manages_childcare)、閲覧=担当施設の職員。日別overrideは child_daily_attendance.scheduled_* が優先。';

alter table child_weekly_schedule enable row level security;
create policy child_weekly_schedule_select_scoped on child_weekly_schedule
  for select using (
    exists (select 1 from children c
            where c.id = child_weekly_schedule.child_id and has_childcare_office_access(c.office_id))
  );
create policy child_weekly_schedule_write_scoped on child_weekly_schedule
  for all using (
    exists (select 1 from children c
            where c.id = child_weekly_schedule.child_id and has_childcare_office_access(c.office_id))
  ) with check (
    exists (select 1 from children c
            where c.id = child_weekly_schedule.child_id and has_childcare_office_access(c.office_id))
  );

-- 週次標準の upsert(1曜日ずつ)。契約に基づく園児マスタ系設定のため設定変更は主任以上に限定。
create or replace function set_child_weekly_schedule(
  p_child_id uuid, p_weekday int, p_start time, p_end time
) returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid;
begin
  if p_weekday < 1 or p_weekday > 7 then raise exception 'invalid weekday'; end if;
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  insert into child_weekly_schedule (child_id, weekday, scheduled_start_at, scheduled_end_at, updated_by, updated_at)
  values (p_child_id, p_weekday, p_start, p_end, my_employee_id(), now())
  on conflict (child_id, weekday) do update set
    scheduled_start_at = excluded.scheduled_start_at,
    scheduled_end_at   = excluded.scheduled_end_at,
    updated_by         = excluded.updated_by,
    updated_at         = excluded.updated_at;
end; $$;

-- 週次標準の削除(その曜日は通わない)。設定変更のため主任以上。監査はテーブルの trg_audit で記録。
create or replace function delete_child_weekly_schedule(p_child_id uuid, p_weekday int)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  delete from child_weekly_schedule where child_id = p_child_id and weekday = p_weekday;
end; $$;

-- 週次標準の取得(1園児分・最大7曜日)。閲覧は担当施設の職員。
create or replace function fetch_child_weekly_schedule(p_child_id uuid)
returns table (weekday int, scheduled_start_at time, scheduled_end_at time)
language plpgsql stable security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  return query
    select s.weekday, s.scheduled_start_at, s.scheduled_end_at
    from child_weekly_schedule s where s.child_id = p_child_id order by s.weekday;
end; $$;

-- 監査トリガ(他テーブルと同様)。
do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'child_weekly_schedule'
  );
end $$;
