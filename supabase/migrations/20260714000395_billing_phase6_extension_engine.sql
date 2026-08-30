-- 395: 請求決済 Phase6 — 延長料金計算エンジン(詳細設計§6・2026-08-31俊承認)。
--   実打刻(秒単位)×契約から延長料金を決定論的に計算し、日次スナップショットとして保存する。
--   確定ルール:
--     ・秒判定: 契約時刻ちょうどまで=課金なし、1秒超過で課金(俊確定⑤)
--     ・units = ceil(超過秒 / 単位秒)。朝(契約開始前)・夕(終了後)は別切上げ合算(AC-07)
--     ・単価=契約プランの時間外料金項目×利用日時点の版(AC-14)
--     ・月極延長加入者は coverage_end 超過分のみ kind='monthly_ext_overrun'(AC-09)
--     ・土曜は saturday_usage_end があればそちら(大和短時間等)
--     ・閉園超過(BABY)=office_pickup_deadlines の曜日別お迎え締切超を10分単位(AC-10)
--     ・打刻無し日・休園日=実打刻ベースのため自然にゼロ。契約なし園児=計算対象外
--   請求は園児個別方式(2026-08-28決定)。一時預かり計算はPhase9・company_paid免除の
--   請求0円化はPhase7請求生成側で扱う(本エンジンは純粋な発生額を出す)。

-- ============================================================
-- (1) billable_usage_days — 日次の課金実績(計算結果のスナップショット)
-- ============================================================
create table billable_usage_days (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id),
  office_id uuid not null references offices(id),
  usage_date date not null,
  kind text not null check (kind in
    ('extension_am','extension_pm','monthly_ext_overrun','closing_overrun','temp_care_time')),
  over_seconds int not null check (over_seconds > 0),
  units int not null check (units > 0),
  unit_amount int not null check (unit_amount >= 0),
  amount int not null check (amount >= 0),
  fee_rate_version_id uuid references fee_rate_versions(id),
  basis jsonb not null,                    -- 打刻・契約範囲・計算式のスナップショット(金額の証跡)
  calculated_at timestamptz not null default now(),
  invoice_item_id uuid,                    -- 請求取込済みマーク(Phase7でFK追加・二重計上防止)
  waived_amount int not null default 0 check (waived_amount >= 0 and waived_amount <= amount),
  unique (child_id, usage_date, kind)
);
create index idx_billable_usage_days_office_month on billable_usage_days(office_id, usage_date);
create index idx_billable_usage_days_child on billable_usage_days(child_id);
alter table billable_usage_days enable row level security;

-- ============================================================
-- (2) fee_waivers — 園側事情の免除(§9.5・管理者以上・理由必須・監査)
-- ============================================================
create table fee_waivers (
  id uuid primary key default gen_random_uuid(),
  usage_day_id uuid not null references billable_usage_days(id),
  original_amount int not null,
  waived_amount int not null check (waived_amount >= 0),
  reason text not null,
  operator uuid references employees(id),
  operated_at timestamptz not null default now()
);
alter table fee_waivers enable row level security;

-- ============================================================
-- (3) calculate_billable_usage — 計算の心臓部(保存しない純粋導出・内部専用)
--     打刻が無い/契約が無い園児は0行。basisに再現用の全証跡を残す。
-- ============================================================
create or replace function calculate_billable_usage(p_child_id uuid, p_usage_date date)
returns table (
  kind text,
  over_seconds int,
  units int,
  unit_amount int,
  amount int,
  fee_rate_version_id uuid,
  basis jsonb
)
language plpgsql stable security definer set search_path = public as $$
declare
  v_month date := date_trunc('month', p_usage_date)::date;
  v_fiscal int := case when extract(month from p_usage_date) >= 4
                       then extract(year from p_usage_date)::int
                       else extract(year from p_usage_date)::int - 1 end;
  v_arrival timestamptz;
  v_departure timestamptz;
  v_plan record;
  v_rate record;
  v_office uuid;
  v_limit_start timestamptz;
  v_limit_end timestamptz;
  v_end_time time;
  v_pm_kind text := 'extension_pm';
  v_ext_cov time;
  v_unit_secs int;
  v_over int;
  v_units int;
  v_deadline time;
  v_cor record;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then return; end if;

  -- 休園日は計上しない(375)。迷い打刻があってもゼロ(Fableレビュー中6)
  if is_office_closed(v_office, p_usage_date) then return; end if;

  -- 実打刻(代理打刻含む・rejectedは対象外)。営業日窓=JST 6:00〜翌6:00:
  -- 深夜0時台のお迎え(閉園超過の本丸)を前日に正しく帰属させる+範囲比較でインデックス有効
  -- (Fableレビュー中3/軽13)
  select
    min(e.occurred_at) filter (where e.event_type in ('drop_off','proxy_drop_off')),
    max(e.occurred_at) filter (where e.event_type in ('pick_up','proxy_pick_up'))
  into v_arrival, v_departure
  from child_attendance_events e
  where e.child_id = p_child_id
    and e.occurred_at >= (p_usage_date + time '06:00') at time zone 'Asia/Tokyo'
    and e.occurred_at <  (p_usage_date + 1 + time '06:00') at time zone 'Asia/Tokyo';
  if v_arrival is null and v_departure is null then return; end if;

  -- 利用月の契約プラン(月初日規約・exclusionにより高々1行)
  select p.id as plan_id, p.name, p.usage_start, p.usage_end, p.saturday_usage_end,
         p.overtime_fee_item_id
  into v_plan
  from child_contracts cc
  join contract_plans p on p.id = cc.contract_plan_id
  where cc.child_id = p_child_id
    and cc.start_month <= v_month
    and (cc.end_month is null or cc.end_month >= v_month)
  order by cc.start_month desc
  limit 1;
  if v_plan.plan_id is null then return; end if;   -- 契約なし=計算対象外(Phase7チェックで検出)

  -- 契約時間帯(土曜特例)。JSTのその日の時刻としてtimestamptz化
  v_end_time := case when extract(isodow from p_usage_date) = 6 and v_plan.saturday_usage_end is not null
                     then v_plan.saturday_usage_end else v_plan.usage_end end;
  v_limit_start := (p_usage_date + v_plan.usage_start) at time zone 'Asia/Tokyo';
  v_limit_end   := (p_usage_date + v_end_time) at time zone 'Asia/Tokyo';

  -- 月極延長加入中はカバー時刻まで無償→超過分のみ monthly_ext_overrun(AC-09)
  select max(m.coverage_end) into v_ext_cov
  from child_extension_contracts ec
  join monthly_extension_plans m on m.id = ec.monthly_extension_plan_id
  where ec.child_id = p_child_id
    and ec.start_month <= v_month
    and (ec.end_month is null or ec.end_month >= v_month);
  if v_ext_cov is not null and v_ext_cov > v_end_time then
    v_limit_end := (p_usage_date + v_ext_cov) at time zone 'Asia/Tokyo';
    v_pm_kind := 'monthly_ext_overrun';
  end if;

  -- 閉園超過ルール(BABY)と締切時刻を先に解決(pmキャップに使うため)
  select r.id as rule_id, r.fee_item_id, f.calc_unit, f.name as item_name
  into v_cor
  from closing_overrun_rules r
  join fee_items f on f.id = r.fee_item_id and f.is_active
  where r.office_id = v_office
    and r.is_active
    and (r.enabled_from_fiscal_year is null or r.enabled_from_fiscal_year <= v_fiscal)
  order by f.name
  limit 1;
  if v_cor.rule_id is not null then
    select d.pickup_deadline_time into v_deadline
    from office_pickup_deadlines d
    where d.office_id = v_office
      and d.day_of_week = extract(dow from p_usage_date)::int   -- 81は 0=日..6=土
      and d.is_operating_day;
  end if;

  -- 時間外料金の単価(利用日時点の版)。時間外料金なしプラン(最長)は朝夕延長なし
  if v_plan.overtime_fee_item_id is not null then
    select v.id as version_id, v.amount, f.calc_unit, f.name as item_name, v.effective_from
    into v_rate
    from fee_rate_versions v
    join fee_items f on f.id = v.fee_item_id
    where v.fee_item_id = v_plan.overtime_fee_item_id
      and v.effective_from <= p_usage_date
      and (v.effective_to is null or v.effective_to >= p_usage_date)
    limit 1;
    -- 設定欠落は黙って0円にせずfail loud(金額の中核・Fableレビュー中4)
    if v_rate.version_id is null then
      raise exception '時間外料金の単価が未登録です(プラン: %)', v_plan.name;
    end if;
    v_unit_secs := case v_rate.calc_unit when 'per_30min' then 1800
                                         when 'per_10min' then 600 end;
    if v_unit_secs is null then
      raise exception '時間外料金の単位(%)が延長計算に対応していません', v_rate.calc_unit;
    end if;

    -- 朝: 契約開始前。実在園分のみ(降園が開始前ならそこまで=Fableレビュー中5のclamp)
    if v_arrival is not null and v_arrival < v_limit_start then
      v_over := ceil(extract(epoch from least(coalesce(v_departure, v_limit_start), v_limit_start) - v_arrival))::int;
      if v_over > 0 then
        v_units := ceil(v_over::numeric / v_unit_secs)::int;
        kind := 'extension_am'; over_seconds := v_over; units := v_units;
        unit_amount := v_rate.amount; amount := v_units * v_rate.amount;
        fee_rate_version_id := v_rate.version_id;
        basis := jsonb_build_object(
          'arrival', v_arrival, 'limit_start', v_limit_start,
          'plan', v_plan.name, 'item', v_rate.item_name,
          'unit_seconds', v_unit_secs, 'rate_effective_from', v_rate.effective_from,
          'formula', 'ceil(over_seconds/unit_seconds)*unit_amount');
        return next;
      end if;
    end if;

    -- 夕: 契約終了(または月極延長カバー)後。ちょうど=課金なし・1秒超過で課金(俊確定⑤)。
    -- 実在園分のみ(登園が終了後ならそこから=clamp)。閉園締切以降は閉園超過の料金体系に
    -- 切り替わるため締切でキャップ(草案§5.2「通常利用を認める料金ではなく運営実費」・
    -- 二重課金防止=Fableレビュー重大2。※重畳方式に変える場合はこのleastを外す)
    if v_departure is not null and v_departure > v_limit_end then
      v_over := ceil(extract(epoch from
        least(v_departure,
              case when v_cor.rule_id is not null and v_deadline is not null
                   then greatest((p_usage_date + v_deadline) at time zone 'Asia/Tokyo', v_limit_end)
                   else v_departure end)
        - greatest(coalesce(v_arrival, v_limit_end), v_limit_end)))::int;
      if v_over > 0 then
        v_units := ceil(v_over::numeric / v_unit_secs)::int;
        kind := v_pm_kind; over_seconds := v_over; units := v_units;
        unit_amount := v_rate.amount; amount := v_units * v_rate.amount;
        fee_rate_version_id := v_rate.version_id;
        basis := jsonb_build_object(
          'departure', v_departure, 'limit_end', v_limit_end,
          'plan', v_plan.name, 'item', v_rate.item_name,
          'monthly_ext_coverage', v_ext_cov,
          'closing_cap', v_deadline,
          'unit_seconds', v_unit_secs, 'rate_effective_from', v_rate.effective_from,
          'formula', 'ceil(over_seconds/unit_seconds)*unit_amount');
        return next;
      end if;
    end if;
  end if;

  -- 閉園超過(BABY・AC-10): 曜日別お迎え締切(81)超過を10分単位
  if v_cor.rule_id is not null and v_departure is not null and v_deadline is not null
     and v_departure > (p_usage_date + v_deadline) at time zone 'Asia/Tokyo' then
    select v.id as version_id, v.amount, v.effective_from
    into v_rate
    from fee_rate_versions v
    where v.fee_item_id = v_cor.fee_item_id
      and v.effective_from <= p_usage_date
      and (v.effective_to is null or v.effective_to >= p_usage_date)
    limit 1;
    if v_rate.version_id is null then
      raise exception '閉園超過の単価が未登録です(項目: %)', v_cor.item_name;
    end if;
    v_unit_secs := case v_cor.calc_unit when 'per_10min' then 600
                                        when 'per_30min' then 1800 end;
    if v_unit_secs is null then
      raise exception '閉園超過の単位(%)が延長計算に対応していません', v_cor.calc_unit;
    end if;
    v_over := ceil(extract(epoch from
      v_departure - ((p_usage_date + v_deadline) at time zone 'Asia/Tokyo')))::int;
    v_units := ceil(v_over::numeric / v_unit_secs)::int;
    kind := 'closing_overrun'; over_seconds := v_over; units := v_units;
    unit_amount := v_rate.amount; amount := v_units * v_rate.amount;
    fee_rate_version_id := v_rate.version_id;
    basis := jsonb_build_object(
      'departure', v_departure, 'closing_deadline', v_deadline,
      'item', v_cor.item_name,
      'unit_seconds', v_unit_secs, 'rate_effective_from', v_rate.effective_from,
      'formula', 'ceil(over_seconds/unit_seconds)*unit_amount');
    return next;
  end if;

  return;
end;
$$;
-- 内部専用(呼び出しは下のRPCから。definer間は所有者権限で成立)
revoke execute on function calculate_billable_usage(uuid, date) from public, anon, authenticated;

-- ============================================================
-- (4) fetch_extension_preview — デイリーボード用の当日プレビュー(保存しない)
--     主任以上+請求フラグON(金額を含むためadmin側のみ=AC-22)
-- ============================================================
create or replace function fetch_extension_preview(p_office_id uuid, p_date date)
returns table (
  child_id uuid,
  child_name text,
  total_amount bigint,
  details jsonb
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  if not is_billing_enabled_for_office(p_office_id) then raise exception 'feature disabled'; end if;
  return query
  select c.id, c.display_name,
         sum(calc.amount)::bigint,
         jsonb_agg(jsonb_build_object(
           'kind', calc.kind, 'over_seconds', calc.over_seconds, 'units', calc.units,
           'unit_amount', calc.unit_amount, 'amount', calc.amount, 'basis', calc.basis
         ) order by calc.kind)
  from children c
  cross join lateral calculate_billable_usage(c.id, p_date) calc
  where c.office_id = p_office_id and c.enrollment_status <> '退園済み'
  group by c.id, c.display_name
  order by c.display_name;
end;
$$;
grant execute on function fetch_extension_preview(uuid, date) to authenticated, service_role;
revoke execute on function fetch_extension_preview(uuid, date) from public, anon;

-- ============================================================
-- (5) generate_billable_usage_days — 月次一括生成(請求サイクルの前段・統括のみ)。
--     未請求分(invoice_item_id null)は削除→再計算=打刻修正後の再実行で自動反映。
--     請求取込済み行は不変(同一キーの再計算結果は on conflict do nothing で捨てる)。
-- ============================================================
create or replace function generate_billable_usage_days(p_office_id uuid, p_billing_month date)
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_month date;
  v_last date;
  v_count int;
begin
  if not is_executive_director_or_admin() then raise exception 'not authorized'; end if;
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  if not is_billing_enabled_for_office(p_office_id) then raise exception 'feature disabled'; end if;
  if p_billing_month is null then raise exception '対象月を指定してください'; end if;
  v_month := date_trunc('month', p_billing_month)::date;
  -- 対象月の末日まで(当月なら今日=JSTまで)
  v_last := least((v_month + interval '1 month' - interval '1 day')::date,
                  (now() at time zone 'Asia/Tokyo')::date);
  if v_last < v_month then raise exception '未来の月は生成できません'; end if;

  -- 未請求分を削除して再計算。免除記録つきの行はFK保護+監査保全のため温存
  -- (invoiced同様、insert側の on conflict do nothing が再計算結果を捨てる=Fableレビュー重大1)
  delete from billable_usage_days b
  where b.office_id = p_office_id
    and b.usage_date between v_month and (v_month + interval '1 month' - interval '1 day')::date
    and b.invoice_item_id is null
    and not exists (select 1 from fee_waivers w where w.usage_day_id = b.id);

  insert into billable_usage_days
    (child_id, office_id, usage_date, kind, over_seconds, units, unit_amount, amount,
     fee_rate_version_id, basis, calculated_at)
  select c.id, p_office_id, d.d::date, calc.kind, calc.over_seconds, calc.units,
         calc.unit_amount, calc.amount, calc.fee_rate_version_id, calc.basis, now()
  from children c
  cross join generate_series(v_month, v_last, interval '1 day') d(d)
  cross join lateral calculate_billable_usage(c.id, d.d::date) calc
  where c.office_id = p_office_id
  on conflict (child_id, usage_date, kind) do nothing;   -- 請求取込済み行を温存

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
grant execute on function generate_billable_usage_days(uuid, date) to authenticated, service_role;
revoke execute on function generate_billable_usage_days(uuid, date) from public, anon;

-- ============================================================
-- (6) waive_billable_usage — 園側事情の免除(§9.5)。管理者以上・理由必須・fee_waiversに監査
-- ============================================================
create or replace function waive_billable_usage(
  p_usage_day_id uuid,
  p_waived_amount int,
  p_reason text
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_row record;
begin
  select * into v_row from billable_usage_days where id = p_usage_day_id;
  if v_row.id is null then raise exception 'not found'; end if;
  if not is_childcare_admin(v_row.office_id) then raise exception 'not authorized'; end if;
  if not is_billing_enabled_for_office(v_row.office_id) then raise exception 'feature disabled'; end if;
  if p_reason is null or btrim(p_reason) = '' then raise exception '免除理由を入力してください'; end if;
  if p_waived_amount is null or p_waived_amount < 0 or p_waived_amount > v_row.amount then
    raise exception '免除額は0〜%円で指定してください', v_row.amount;
  end if;
  if v_row.invoice_item_id is not null then
    raise exception '請求取込済みのため免除できません(請求額調整で対応してください)';
  end if;

  update billable_usage_days set waived_amount = p_waived_amount where id = p_usage_day_id;
  insert into fee_waivers (usage_day_id, original_amount, waived_amount, reason, operator)
  values (p_usage_day_id, v_row.amount, p_waived_amount, btrim(p_reason), my_employee_id());
end;
$$;
grant execute on function waive_billable_usage(uuid, int, text) to authenticated, service_role;
revoke execute on function waive_billable_usage(uuid, int, text) from public, anon;
