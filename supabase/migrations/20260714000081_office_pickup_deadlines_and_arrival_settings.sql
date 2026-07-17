-- 保護者アプリ Phase A: 施設×曜日別の降園アラート時刻(変更2)＋登園猶予設定
--
-- 未降園アラートは9:00固定ではなく、曜日別登園予定(Phase B)が登録されている園児は
-- 「登園予定時刻＋猶予分数」、未登録の園児は施設ごとのデフォルト時刻を使う。
-- 猶予分数・デフォルト時刻は既存childcare_office_settings(Phase0)に列追加する
-- (指示書の指示に基づく既存テーブル拡張。RLS・既存列には影響しない)。
--
-- 降園側(未降園アラート)は施設×曜日で時刻が異なるため、既存テーブルへの単純な列追加では
-- 表現できず新規テーブルとする。指示書§5.3の初期値をそのまま投入する。

create table office_pickup_deadlines (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id),
  day_of_week int not null check (day_of_week between 0 and 6), -- 0=日曜 … 6=土曜
  is_operating_day boolean not null default true,
  pickup_deadline_time time,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (office_id, day_of_week)
);
create trigger trg_office_pickup_deadlines_updated_at before update on office_pickup_deadlines
  for each row execute function set_updated_at();

alter table office_pickup_deadlines enable row level security;
create policy office_pickup_deadlines_select_scoped on office_pickup_deadlines
  for select using (has_childcare_office_access(office_id));
create policy office_pickup_deadlines_write_managers on office_pickup_deadlines
  for all using (manages_childcare(office_id)) with check (manages_childcare(office_id));

do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'office_pickup_deadlines'
  );
end $$;

alter table childcare_office_settings
  add column default_expected_arrival_time time not null default '09:00',
  add column expected_arrival_grace_minutes int not null default 30;

-- 初期値投入(指示書§5.3)。0=日曜…6=土曜。
-- 大和オハナ保育園(O): 平日19:00・土曜18:00・日曜休園
insert into office_pickup_deadlines (office_id, day_of_week, is_operating_day, pickup_deadline_time)
select o.id, d.day_of_week, d.is_operating_day, d.pickup_deadline_time
from offices o, (values
  (0, false, null::time), (1, true, '19:00'::time), (2, true, '19:00'::time),
  (3, true, '19:00'::time), (4, true, '19:00'::time), (5, true, '19:00'::time),
  (6, true, '18:00'::time)
) as d(day_of_week, is_operating_day, pickup_deadline_time)
where o.office_code = 'O';

-- Mahalo Station(S)・Halelea(H): 平日19:00・土日休園
insert into office_pickup_deadlines (office_id, day_of_week, is_operating_day, pickup_deadline_time)
select o.id, d.day_of_week, d.is_operating_day, d.pickup_deadline_time
from offices o, (values
  (0, false, null::time), (1, true, '19:00'::time), (2, true, '19:00'::time),
  (3, true, '19:00'::time), (4, true, '19:00'::time), (5, true, '19:00'::time),
  (6, false, null::time)
) as d(day_of_week, is_operating_day, pickup_deadline_time)
where o.office_code in ('S', 'H');

-- BABY MAHALO(M): 月〜土20:00・日曜休園
insert into office_pickup_deadlines (office_id, day_of_week, is_operating_day, pickup_deadline_time)
select o.id, d.day_of_week, d.is_operating_day, d.pickup_deadline_time
from offices o, (values
  (0, false, null::time), (1, true, '20:00'::time), (2, true, '20:00'::time),
  (3, true, '20:00'::time), (4, true, '20:00'::time), (5, true, '20:00'::time),
  (6, true, '20:00'::time)
) as d(day_of_week, is_operating_day, pickup_deadline_time)
where o.office_code = 'M';
