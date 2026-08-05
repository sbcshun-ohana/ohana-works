-- 188: 園側検温(職員が日中に複数回記録) + K8一覧の最新値
-- デイリーボード刷新 Phase C の第1弾(健康チェック・検温)。
-- 家庭連絡帳の朝検温(family_daily_reports.temperature・保護者記入)は不変・別系統。
-- 園側で職員が日中に複数回記録できる child_temperature_records を新設(記録時刻+体温)。
-- K8(家庭での様子一覧)へは園側検温の「最新値」を表示できるよう fetch を用意。
-- 権限: 記録/削除は 164(天気)と同パターン=当日は担当施設の職員 / 過去日(・未来日)は主任以上。JST基準。
--       閲覧(fetch)は担当施設の職員。
-- 体温レンジ: 園側 34.0〜42.0℃(低体温の臨床記録を許容。家庭連絡帳 35.0〜との非対称は許容)。
-- 重複キー: unique(child,date,measured_at)。同一時刻はupsert(体温更新)、異なる時刻は複数可。

create table child_temperature_records (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  business_date date not null,
  measured_at time not null,                         -- 記録時刻(JST壁時計・時刻のみ)
  temperature numeric(3,1) not null check (temperature between 34.0 and 42.0),
  recorded_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (child_id, business_date, measured_at)
);
create index idx_child_temperature_records_child_date on child_temperature_records(child_id, business_date);

create trigger trg_child_temperature_records_updated_at before update on child_temperature_records
  for each row execute function set_updated_at();

comment on table child_temperature_records is
  '園側検温(職員が日中に複数回記録)。家庭連絡帳の朝検温(family_daily_reports.temperature)とは別系統。';

alter table child_temperature_records enable row level security;
create policy child_temperature_records_select_scoped on child_temperature_records
  for select using (exists (select 1 from children c
    where c.id = child_temperature_records.child_id and has_childcare_office_access(c.office_id)));
create policy child_temperature_records_write_scoped on child_temperature_records
  for all using (exists (select 1 from children c
    where c.id = child_temperature_records.child_id and has_childcare_office_access(c.office_id)))
  with check (exists (select 1 from children c
    where c.id = child_temperature_records.child_id and has_childcare_office_access(c.office_id)));

-- 記録(upsert: 同一時刻は体温を更新)。164(天気)と同パターン: 当日=施設職員 / 過去日=主任以上。
create or replace function record_child_temperature(
  p_child_id uuid, p_business_date date, p_measured_at time, p_temperature numeric
) returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  if p_temperature is null or p_temperature < 34.0 or p_temperature > 42.0 then
    raise exception 'temperature out of range';
  end if;
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  -- 過去日(・未来日)の編集は主任以上(天気164と対称)。JST基準で当日判定。
  if p_business_date <> v_today and not manages_childcare(v_office) then
    raise exception 'not authorized to edit temperature for non-current date';
  end if;
  insert into child_temperature_records (child_id, business_date, measured_at, temperature, recorded_by)
  values (p_child_id, p_business_date, p_measured_at, p_temperature, my_employee_id())
  on conflict (child_id, business_date, measured_at) do update set
    temperature = excluded.temperature, recorded_by = excluded.recorded_by, updated_at = now();
end; $$;

-- 削除(記録時刻を指定)。record と同じ権限(当日=施設職員 / 過去日=主任以上)。
create or replace function delete_child_temperature(
  p_child_id uuid, p_business_date date, p_measured_at time
) returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  if p_business_date <> v_today and not manages_childcare(v_office) then
    raise exception 'not authorized to edit temperature for non-current date';
  end if;
  delete from child_temperature_records
    where child_id = p_child_id and business_date = p_business_date and measured_at = p_measured_at;
end; $$;

-- 健康チェック(検温)一覧: 施設×日の園側検温を全園児分(園児名・時刻順)。閲覧=担当施設の職員。
create or replace function fetch_child_temperatures_for_office(p_office_id uuid, p_business_date date)
returns table (child_id uuid, display_name text, honorific_suffix text, class_name text, measured_at time, temperature numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  return query
    select c.id, c.display_name, c.honorific_suffix_resolved, cc.class_name, t.measured_at, t.temperature
    from child_temperature_records t
    join children c on c.id = t.child_id
    left join child_class_enrollments cce on cce.child_id = c.id
      and cce.effective_start_date <= p_business_date
      and (cce.effective_end_date is null or cce.effective_end_date >= p_business_date)
    left join childcare_classes cc on cc.id = cce.class_id
    where c.office_id = p_office_id and t.business_date = p_business_date
    order by c.display_name, t.measured_at;
end; $$;

-- K8(家庭での様子一覧)用: 園側検温の「最新値」を1園児1行で。
create or replace function fetch_child_latest_temperatures_for_office(p_office_id uuid, p_business_date date)
returns table (child_id uuid, latest_temperature numeric, latest_measured_at time)
language plpgsql stable security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  return query
    select distinct on (t.child_id) t.child_id, t.temperature, t.measured_at
    from child_temperature_records t
    join children c on c.id = t.child_id
    where c.office_id = p_office_id and t.business_date = p_business_date
    order by t.child_id, t.measured_at desc;
end; $$;

-- 監査トリガ(他テーブルと同様)
do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'child_temperature_records'
  );
end $$;

-- 新規関数の実行権限を明示付与(認証セッションのみ。関数内で権限を判定)。
grant execute on function record_child_temperature(uuid, date, time, numeric) to authenticated;
grant execute on function delete_child_temperature(uuid, date, time) to authenticated;
grant execute on function fetch_child_temperatures_for_office(uuid, date) to authenticated;
grant execute on function fetch_child_latest_temperatures_for_office(uuid, date) to authenticated;
