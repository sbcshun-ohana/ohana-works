-- Phase 2 §2.5: 天気・気温・湿度の記録(施設×日で1回・手入力)。
-- 当日は施設アクセス保持者なら誰でも上書き可、過去日(および未来日)の修正は主任以上
-- (manages_childcare。2026-08-04確定で「管理者以上(主任除外)」区分は廃止し主任以上に統一)。
-- 日付判定は JST(Asia/Tokyo)基準。書き込みは security definer の upsert RPC 経由に限定し、
-- クライアント直INSERT/UPDATEは許可しない(SELECT のみ RLS で施設アクセス保持者に開放)。

create table daily_weather_records (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id),
  record_date date not null,
  weather text not null check (weather in ('晴れ', '曇り', '雨', '雪', 'その他')),
  temperature numeric,
  humidity numeric,
  recorded_by uuid references employees(id),
  recorded_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (office_id, record_date)
);

create trigger trg_daily_weather_records_updated_at before update on daily_weather_records
  for each row execute function set_updated_at();

alter table daily_weather_records enable row level security;

-- SELECT: 施設アクセス保持者(保育業務が有効な施設に属す職員)は閲覧可。
create policy daily_weather_records_select on daily_weather_records
  for select using (has_childcare_office_access(office_id));

do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'daily_weather_records'
  );
end $$;

-- 天気の記録(施設×日で1行・upsert)。当日は誰でも、過去日/未来日は主任以上。
create or replace function upsert_daily_weather_record(
  p_office_id uuid,
  p_record_date date,
  p_weather text,
  p_temperature numeric default null,
  p_humidity numeric default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
  v_id uuid;
begin
  if not has_childcare_office_access(p_office_id) then
    raise exception 'not authorized';
  end if;
  -- 当日以外(過去日・未来日)の修正は主任以上に限定する。
  if p_record_date <> v_today and not manages_childcare(p_office_id) then
    raise exception 'not authorized to edit weather for non-current date';
  end if;

  insert into daily_weather_records (
    office_id, record_date, weather, temperature, humidity, recorded_by, recorded_at
  ) values (
    p_office_id, p_record_date, p_weather, p_temperature, p_humidity, my_employee_id(), now()
  )
  on conflict (office_id, record_date) do update set
    weather = excluded.weather,
    temperature = excluded.temperature,
    humidity = excluded.humidity,
    recorded_by = excluded.recorded_by,
    recorded_at = excluded.recorded_at
  returning id into v_id;

  return v_id;
end;
$$;
