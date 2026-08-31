-- 396: 請求決済 Phase7a — 請求サイクル+請求書発行(園児単位・詳細設計§7/草案§12/§19・2026-08-31俊承認)。
--   請求月Nの内容(AC-12): 企業主導型=当月(N)月極+前月(N-1)変動+調整
--                        / 大和=前月給食費(3歳以上クラス・登園0日でも・免除適用)+当月月極延長+前月変動+調整
--   会社負担(company_paid)の子は請求書を作らずチェック一覧に記録。合計0円は発行しない。
--   マイナス合計は発行せず警告(§12.5)。過去請求は不変・差額は調整で将来請求へ。
--   採番: {billing_code}-{YYYYMM}-{連番3桁}(施設×月の排他採番・発行しない子は subtransaction
--   ロールバックで番号を消費しない)。承認・公開・取消=統括のみ(AC-13)。サイクル実行=主任以上。

-- ============================================================
-- (0) 請求書番号用の施設コード(俊確定 2026-08-17: OHN/BMH/STA/HLA)
-- ============================================================
alter table offices add column if not exists billing_code text;
update offices set billing_code = case office_code
  when 'O' then 'OHN' when 'M' then 'BMH' when 'S' then 'STA' when 'H' then 'HLA' end
where office_code in ('O','M','S','H');

-- ============================================================
-- (1) テーブル群
-- ============================================================
create table billing_cycles (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id),
  billing_month date not null check (extract(day from billing_month) = 1),
  status text not null default 'draft'
    check (status in ('draft','review_required','approved','published','cancelled')),
  opened_by uuid references employees(id),
  opened_at timestamptz not null default now(),
  calculated_at timestamptz,
  approved_by uuid references employees(id),
  approved_at timestamptz,
  published_at timestamptz,
  cancelled_at timestamptz,
  note text
);
-- 取消済み以外は施設×月で1本
create unique index uq_billing_cycles_active on billing_cycles(office_id, billing_month)
  where status <> 'cancelled';
alter table billing_cycles enable row level security;

create table invoices (
  id uuid primary key default gen_random_uuid(),
  cycle_id uuid not null references billing_cycles(id),
  child_id uuid not null references children(id),
  office_id uuid not null references offices(id),
  billing_month date not null,
  invoice_no text not null unique,
  status text not null default 'draft' check (status in (
    'draft','calculating','review_required','pending_executive_approval','approved',
    'issued','payment_pending','partially_paid','paid','overdue','payment_failed',
    'cancelled','adjusted_in_future_invoice')),
  total_amount int not null default 0,
  paid_amount int not null default 0,
  due_date date,
  approved_by uuid references employees(id),
  approved_at timestamptz,
  published_at timestamptz,
  cancelled_at timestamptz,
  cancelled_by uuid references employees(id),
  cancel_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index uq_invoices_child_month_active on invoices(child_id, billing_month)
  where status <> 'cancelled';
create index idx_invoices_cycle on invoices(cycle_id);
create trigger trg_invoices_updated before update on invoices
  for each row execute function set_updated_at();
alter table invoices enable row level security;

create table invoice_items (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references invoices(id),
  category text not null check (category in (
    'monthly_base','monthly_extension','extension','closing_overrun',
    'meal_main','meal_side','temp_care','temp_care_meal','temp_care_snack',
    'diaper','supply','event','misc','adjustment_plus','adjustment_minus')),
  description text not null,
  target_period text,                       -- 例「2026年8月分」
  quantity numeric not null default 1,
  unit_amount int,
  amount int not null,                      -- adjustment_minus のみ負値可
  fee_rate_version_id uuid references fee_rate_versions(id),
  source_table text,
  source_id uuid,
  created_at timestamptz not null default now(),
  unique (source_table, source_id)          -- 1:1元記録の二重計上防止(AC-11・null同士は非衝突)
);
create index idx_invoice_items_invoice on invoice_items(invoice_id);
alter table invoice_items enable row level security;

create table invoice_adjustments (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id),
  adjustment_kind text not null check (adjustment_kind in ('plus','minus')),
  amount int not null check (amount > 0),   -- 符号はkindで表現(明細化時にminusは負値)
  origin_invoice_id uuid references invoices(id),
  origin_item_id uuid references invoice_items(id),
  guardian_note text not null,              -- 保護者向け説明(必須・§12.5)
  internal_note text,
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  approved_by uuid references employees(id),
  approved_at timestamptz,
  applied_invoice_id uuid references invoices(id)
);
alter table invoice_adjustments enable row level security;

create table invoice_number_sequences (
  office_id uuid not null references offices(id),
  year_month text not null,                 -- 'YYYYMM'
  last_no int not null default 0,
  primary key (office_id, year_month)
);
alter table invoice_number_sequences enable row level security;

create table billing_cycle_checks (
  id uuid primary key default gen_random_uuid(),
  cycle_id uuid not null references billing_cycles(id),
  check_key text not null,
  severity text not null check (severity in ('error','warning','info')),
  child_id uuid references children(id),
  message text not null,
  created_at timestamptz not null default now()
);
create index idx_billing_cycle_checks_cycle on billing_cycle_checks(cycle_id);
alter table billing_cycle_checks enable row level security;

-- 取込整合のFK(395で列のみ用意していた分)+取込検索用index
alter table billable_usage_days
  add constraint billable_usage_days_invoice_item_fk
  foreign key (invoice_item_id) references invoice_items(id);
create index idx_billable_usage_days_invoice_item on billable_usage_days(invoice_item_id)
  where invoice_item_id is not null;

-- ============================================================
-- (1b) 390 generate_age_band_snapshots の同族バグ修正(レビュー重大1の水平展開):
--      age_groupは施設により「N歳」「N歳児」が混在→数字で判定に統一
-- ============================================================
create or replace function generate_age_band_snapshots(p_office_id uuid, p_fiscal_year int)
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_count int;
begin
  if not is_executive_director_or_admin() then raise exception 'not authorized'; end if;
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  if not is_billing_enabled_for_office(p_office_id) then raise exception 'feature disabled'; end if;

  insert into child_age_band_snapshots (child_id, fiscal_year, age_band, basis_class_id, determined_at)
  select distinct on (cce.child_id)
    cce.child_id, p_fiscal_year,
    case when substring(cl.age_group from '[0-9]')::int = 0 then 'age0' else 'age1_2' end,
    cl.id, now()
  from child_class_enrollments cce
  join childcare_classes cl on cl.id = cce.class_id
  join children ch on ch.id = cce.child_id
  where cl.office_id = p_office_id
    and cl.school_year = p_fiscal_year
    and substring(cl.age_group from '[0-9]')::int between 0 and 2
    and ch.enrollment_status <> '退園済み'
  order by cce.child_id, cce.effective_start_date, cce.id
  on conflict (child_id, fiscal_year) do update
    set age_band = excluded.age_band,
        basis_class_id = excluded.basis_class_id,
        determined_at = excluded.determined_at;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ============================================================
-- (2) generate_billable_usage_days の権限を主任以上へ緩和
--     (サイクル実行=日常操作=主任以上の写像に整合。395では統括のみだった)
-- ============================================================
create or replace function generate_billable_usage_days(p_office_id uuid, p_billing_month date)
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_month date;
  v_last date;
  v_count int;
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  if not is_billing_enabled_for_office(p_office_id) then raise exception 'feature disabled'; end if;
  if p_billing_month is null then raise exception '対象月を指定してください'; end if;
  v_month := date_trunc('month', p_billing_month)::date;
  v_last := least((v_month + interval '1 month' - interval '1 day')::date,
                  (now() at time zone 'Asia/Tokyo')::date);
  if v_last < v_month then raise exception '未来の月は生成できません'; end if;

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
  on conflict (child_id, usage_date, kind) do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ============================================================
-- 内部: 請求番号の採番(排他・呼び出し元subtransactionのロールバックで番号も戻る)
-- ============================================================
create or replace function next_invoice_no(p_office_id uuid, p_billing_month date)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_code text;
  v_ym text := to_char(p_billing_month, 'YYYYMM');
  v_no int;
begin
  select billing_code into v_code from offices where id = p_office_id;
  if v_code is null then raise exception '施設の請求コード(billing_code)が未設定です'; end if;
  insert into invoice_number_sequences (office_id, year_month, last_no)
  values (p_office_id, v_ym, 1)
  on conflict (office_id, year_month) do update set last_no = invoice_number_sequences.last_no + 1
  returning last_no into v_no;
  return v_code || '-' || v_ym || '-' || lpad(v_no::text, 3, '0');
end;
$$;
revoke execute on function next_invoice_no(uuid, date) from public, anon, authenticated;

-- ============================================================
-- (3) run_billing_cycle — サイクル実行(主任以上)。下書き請求の一括作成+自動チェック
-- ============================================================
create or replace function run_billing_cycle(p_office_id uuid, p_billing_month date)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_month date;
  v_var_month date;                          -- 変動の対象=前月
  v_var_end date;
  v_office_code text;
  v_cycle uuid;
  v_child record;
  v_invoice uuid;
  v_total int;
  v_item uuid;
  v_fiscal int;
  r record;
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  if not is_billing_enabled_for_office(p_office_id) then raise exception 'feature disabled'; end if;
  if p_billing_month is null or extract(day from p_billing_month) <> 1 then
    raise exception '請求月は月初日で指定してください';
  end if;
  v_month := p_billing_month;
  v_var_month := (v_month - interval '1 month')::date;
  v_var_end := (v_month - interval '1 day')::date;
  v_fiscal := case when extract(month from v_var_month) >= 4
                   then extract(year from v_var_month)::int
                   else extract(year from v_var_month)::int - 1 end;
  select office_code into v_office_code from offices where id = p_office_id;

  if v_month > date_trunc('month', (now() at time zone 'Asia/Tokyo')::date)::date then
    raise exception '未来の請求月はまだ実行できません(前月実績が確定してから実行してください)';
  end if;
  if exists (select 1 from billing_cycles
             where office_id = p_office_id and billing_month = v_month and status <> 'cancelled') then
    raise exception 'この月のサイクルは既にあります(取消してから再実行してください)';
  end if;

  insert into billing_cycles (office_id, billing_month, status, opened_by)
  values (p_office_id, v_month, 'draft', my_employee_id())
  returning id into v_cycle;

  -- 変動(前月)のスナップショットを最新化
  perform generate_billable_usage_days(p_office_id, v_var_month);

  -- 対象園児: ①在籍中/退園予定で請求月に契約がある子 ②未取込の変動が残っている子(過去月分含む=
  -- マイナス保留の持ち越し・レビュー重大3) ③大和は前月末に3歳以上クラス在籍(退園児の最終月給食=重大4)
  -- ④承認済み未適用の調整がある子(退園後の実費精算=中1)
  for v_child in
    select distinct c.id, c.display_name
    from children c
    where c.office_id = p_office_id
      and (
        (c.enrollment_status in ('在籍中','退園予定')
         and exists (select 1 from child_contracts cc
                     where cc.child_id = c.id and cc.start_month <= v_month
                       and (cc.end_month is null or cc.end_month >= v_month)))
        or exists (select 1 from billable_usage_days b
                   where b.child_id = c.id and b.office_id = p_office_id
                     and b.invoice_item_id is null and b.usage_date <= v_var_end)
        or (v_office_code = 'O' and exists (
              select 1 from child_class_enrollments cce
              join childcare_classes cl on cl.id = cce.class_id
              where cce.child_id = c.id
                and cl.office_id = p_office_id
                and cce.effective_start_date <= v_var_end
                and (cce.effective_end_date is null or cce.effective_end_date >= v_var_end)
                and substring(cl.age_group from '[0-9]')::int >= 3))
        or exists (select 1 from invoice_adjustments a
                   where a.child_id = c.id and a.approved_by is not null
                     and a.applied_invoice_id is null)
      )
    order by c.display_name
  loop
    -- 会社負担(職員の子)は請求書を作らない(利用実績は記録済み)
    if exists (select 1 from child_exemptions x
               where x.child_id = v_child.id and x.kind = 'company_paid'
                 and x.start_month <= v_month and (x.end_month is null or x.end_month >= v_month)) then
      insert into billing_cycle_checks (cycle_id, check_key, severity, child_id, message)
      values (v_cycle, 'company_paid_skip', 'info', v_child.id,
              v_child.display_name || ': 会社負担のため請求書を作成しません');
      continue;
    end if;

    begin  -- 園児単位のsubtransaction(合計0以下なら丸ごと取り消し=採番も戻る)
      insert into invoices (cycle_id, child_id, office_id, billing_month, invoice_no, status)
      values (v_cycle, v_child.id, p_office_id, v_month,
              next_invoice_no(p_office_id, v_month), 'draft')
      returning id into v_invoice;

      -- a) 月極保育料(企業主導型・当月分。無償化免除中はスキップ)
      insert into invoice_items (invoice_id, category, description, target_period,
                                 quantity, unit_amount, amount, fee_rate_version_id)
      select v_invoice, 'monthly_base', f.name, to_char(v_month, 'YYYY年MM月分'),
             1, fr.amount, fr.amount, fr.id
      from child_contracts cc
      join contract_plans p on p.id = cc.contract_plan_id
      join fee_items f on f.id = p.monthly_fee_item_id and f.is_active
      join fee_rate_versions fr on fr.fee_item_id = f.id
        and fr.effective_from <= v_month
        and (fr.effective_to is null or fr.effective_to >= v_month)
      where cc.child_id = v_child.id
        and cc.start_month <= v_month and (cc.end_month is null or cc.end_month >= v_month)
        and p.monthly_fee_item_id is not null
        and not exists (select 1 from child_exemptions x
                        where x.child_id = v_child.id and x.kind = 'free_childcare'
                          and x.start_month <= v_month
                          and (x.end_month is null or x.end_month >= v_month));

      -- b) 月極延長(大和・当月分)
      insert into invoice_items (invoice_id, category, description, target_period,
                                 quantity, unit_amount, amount, fee_rate_version_id)
      select v_invoice, 'monthly_extension', m.name, to_char(v_month, 'YYYY年MM月分'),
             1, fr.amount, fr.amount, fr.id
      from child_extension_contracts ec
      join monthly_extension_plans m on m.id = ec.monthly_extension_plan_id
      join fee_items f on f.id = m.fee_item_id and f.is_active
      join fee_rate_versions fr on fr.fee_item_id = m.fee_item_id
        and fr.effective_from <= v_month
        and (fr.effective_to is null or fr.effective_to >= v_month)
      where ec.child_id = v_child.id
        and ec.start_month <= v_month and (ec.end_month is null or ec.end_month >= v_month);

      -- c) 給食費(大和のみ・前月分・3歳以上クラス基準・登園0日でも請求・免除適用)
      if v_office_code = 'O' then
        insert into invoice_items (invoice_id, category, description, target_period,
                                   quantity, unit_amount, amount, fee_rate_version_id)
        select v_invoice, f.category, f.name, to_char(v_var_month, 'YYYY年MM月分'),
               1, fr.amount, fr.amount, fr.id
        from fee_items f
        join fee_rate_versions fr on fr.fee_item_id = f.id
          and fr.effective_from <= v_var_month
          and (fr.effective_to is null or fr.effective_to >= v_var_month)
        where f.office_id = p_office_id
          and f.category in ('meal_main','meal_side')
          and f.is_active
          and exists (  -- 前月末時点で3歳以上クラスに在籍。
            -- age_groupは大和実データで「3歳」表記(182)・他所は「N歳児」→数字で判定(レビュー重大1)
            select 1 from child_class_enrollments cce
            join childcare_classes cl on cl.id = cce.class_id
            where cce.child_id = v_child.id
              and cl.office_id = p_office_id
              and cce.effective_start_date <= v_var_end
              and (cce.effective_end_date is null or cce.effective_end_date >= v_var_end)
              and substring(cl.age_group from '[0-9]')::int >= 3)
          and not exists (  -- 同種免除(主食/副食/無償化に伴う副食免除は別kindで登録)
            select 1 from child_exemptions x
            where x.child_id = v_child.id and x.kind = f.category
              and x.start_month <= v_var_month
              and (x.end_month is null or x.end_month >= v_var_month));
      end if;

      -- d) 変動(延長・閉園超過): 未取込の全実績(過去月分含む=マイナス保留の持ち越し・重大3)を
      --    kind×発生月×単価版ごとに集約(数量×単価=金額が検算できる明細・中2)。
      --    施設一致で転園児の他施設分を混ぜない(中4)。取込マークで二重計上を封じる
      for r in
        select b.kind, date_trunc('month', b.usage_date)::date as usage_month,
               b.unit_amount, b.fee_rate_version_id,
               case b.kind when 'closing_overrun' then 'closing_overrun'
                           when 'temp_care_time' then 'temp_care'
                           else 'extension' end as category,
               case b.kind when 'extension_am' then '早朝延長保育料'
                           when 'extension_pm' then '延長保育料'
                           when 'monthly_ext_overrun' then '月極延長の超過分'
                           when 'closing_overrun' then '閉園時刻超過実費'
                           else '一時預かり保育料' end as description,
               sum(b.units) as qty,
               sum(b.amount - b.waived_amount) as net_amount,
               sum(b.waived_amount) as waived_total
        from billable_usage_days b
        where b.child_id = v_child.id
          and b.office_id = p_office_id
          and b.usage_date <= v_var_end
          and b.invoice_item_id is null
        group by b.kind, date_trunc('month', b.usage_date), b.unit_amount, b.fee_rate_version_id
      loop
        insert into invoice_items (invoice_id, category, description, target_period,
                                   quantity, unit_amount, amount, fee_rate_version_id)
        values (v_invoice, r.category,
                r.description || case when r.waived_total > 0
                                      then '(園側免除 ▲' || r.waived_total || '円適用)' else '' end,
                to_char(r.usage_month, 'YYYY年MM月分'),
                r.qty, r.unit_amount, r.net_amount, r.fee_rate_version_id)
        returning id into v_item;
        update billable_usage_days set invoice_item_id = v_item
        where child_id = v_child.id and office_id = p_office_id
          and kind = r.kind and unit_amount = r.unit_amount
          and fee_rate_version_id is not distinct from r.fee_rate_version_id
          and date_trunc('month', usage_date)::date = r.usage_month
          and invoice_item_id is null;
      end loop;

      -- e) 承認済みの請求額調整(未適用分)
      for r in
        select a.id, a.adjustment_kind, a.amount, a.guardian_note
        from invoice_adjustments a
        where a.child_id = v_child.id
          and a.approved_by is not null
          and a.applied_invoice_id is null
      loop
        insert into invoice_items (invoice_id, category, description, quantity, unit_amount, amount,
                                   source_table, source_id)
        values (v_invoice,
                case r.adjustment_kind when 'plus' then 'adjustment_plus' else 'adjustment_minus' end,
                '請求額調整: ' || r.guardian_note, 1,
                case r.adjustment_kind when 'plus' then r.amount else -r.amount end,
                case r.adjustment_kind when 'plus' then r.amount else -r.amount end,
                'invoice_adjustments', r.id);
        update invoice_adjustments set applied_invoice_id = v_invoice where id = r.id;
      end loop;

      select coalesce(sum(amount), 0) into v_total from invoice_items where invoice_id = v_invoice;
      if v_total < 0 then
        raise exception using errcode = 'P0901';  -- マイナス合計→発行しない(§12.5)
      elsif not exists (select 1 from invoice_items where invoice_id = v_invoice) then
        raise exception using errcode = 'P0902';  -- 明細なし→発行しない
      end if;
      -- 明細があれば0円でも発行する(調整の相殺を消費して無限持ち越しを防ぐ=レビュー重大3)
      update invoices set total_amount = v_total where id = v_invoice;
    exception
      when sqlstate 'P0901' then
        insert into billing_cycle_checks (cycle_id, check_key, severity, child_id, message)
        values (v_cycle, 'negative_total', 'warning', v_child.id,
                v_child.display_name || ': マイナス合計のため発行を保留(繰越/返金の判断が必要)');
      when sqlstate 'P0902' then
        insert into billing_cycle_checks (cycle_id, check_key, severity, child_id, message)
        values (v_cycle, 'zero_total', 'info', v_child.id,
                v_child.display_name || ': 請求対象がないため発行しません');
    end;
  end loop;

  -- ===== 自動チェック(§19のうち現データで判定可能な項目・エラーは自動修正しない) =====
  -- 1) 在籍中で請求月に契約がない
  insert into billing_cycle_checks (cycle_id, check_key, severity, child_id, message)
  select v_cycle, 'missing_contract', 'error', c.id, c.display_name || ': 請求月の契約プランが未設定です'
  from children c
  where c.office_id = p_office_id and c.enrollment_status = '在籍中'
    and not exists (select 1 from child_contracts cc
                    where cc.child_id = c.id and cc.start_month <= v_month
                      and (cc.end_month is null or cc.end_month >= v_month));

  -- 2) 退園済みなのに契約が開いている
  insert into billing_cycle_checks (cycle_id, check_key, severity, child_id, message)
  select v_cycle, 'open_contract_after_withdrawal', 'warning', c.id,
         c.display_name || ': 退園済みですが契約が終了していません'
  from children c
  join child_contracts cc on cc.child_id = c.id
  where c.office_id = p_office_id and c.enrollment_status = '退園済み'
    and cc.start_month <= v_month and (cc.end_month is null or cc.end_month >= v_month);

  -- 3) 月極単価の未登録(契約プランの月極項目に請求月の版がない)
  insert into billing_cycle_checks (cycle_id, check_key, severity, child_id, message)
  select distinct v_cycle, 'missing_monthly_rate', 'error', cc.child_id,
         '月極項目「' || f.name || '」に請求月の単価がありません'
  from child_contracts cc
  join contract_plans p on p.id = cc.contract_plan_id
  join fee_items f on f.id = p.monthly_fee_item_id
  where p.office_id = p_office_id
    and cc.start_month <= v_month and (cc.end_month is null or cc.end_month >= v_month)
    and not exists (select 1 from fee_rate_versions fr
                    where fr.fee_item_id = f.id and fr.effective_from <= v_month
                      and (fr.effective_to is null or fr.effective_to >= v_month))
    and not exists (select 1 from child_exemptions x   -- 無償化免除中は月極を請求しないため対象外
                    where x.child_id = cc.child_id and x.kind = 'free_childcare'
                      and x.start_month <= v_month
                      and (x.end_month is null or x.end_month >= v_month));

  -- 4) 免除の書類未確認(確認待ち/不備あり)
  insert into billing_cycle_checks (cycle_id, check_key, severity, child_id, message)
  select v_cycle, 'exemption_doc_unconfirmed', 'error', x.child_id,
         c.display_name || ': 免除の書類が未確認です(' || x.document_state || ')'
  from child_exemptions x
  join children c on c.id = x.child_id
  where c.office_id = p_office_id
    and x.document_state in ('pending','deficient')
    and x.start_month <= v_month and (x.end_month is null or x.end_month >= v_month);

  -- 5) 免除書類の年度不一致(確認済みでも年度が古い=毎年度更新・§11.1)
  insert into billing_cycle_checks (cycle_id, check_key, severity, child_id, message)
  select v_cycle, 'exemption_fy_mismatch', 'error', x.child_id,
         c.display_name || ': 免除書類の年度(' || coalesce(x.document_fiscal_year::text, '未記入')
           || ')が対象年度(' || v_fiscal || ')と一致しません'
  from child_exemptions x
  join children c on c.id = x.child_id
  where c.office_id = p_office_id
    and x.document_state = 'confirmed'
    and (x.document_fiscal_year is null or x.document_fiscal_year <> v_fiscal)  -- 年度未記入もエラー
    and x.start_month <= v_month and (x.end_month is null or x.end_month >= v_var_month);

  -- 6) 打刻順序異常(前月・登園のみ/降園のみの日)
  insert into billing_cycle_checks (cycle_id, check_key, severity, child_id, message)
  select v_cycle, 'stamp_order_anomaly', 'warning', t.child_id,
         c.display_name || ': ' || to_char(t.d, 'MM/DD') || ' の打刻が片側のみです(登園' || t.drops || '/降園' || t.picks || ')'
  from (
    select e.child_id, (e.occurred_at at time zone 'Asia/Tokyo')::date as d,
           count(*) filter (where e.event_type in ('drop_off','proxy_drop_off')) as drops,
           count(*) filter (where e.event_type in ('pick_up','proxy_pick_up')) as picks
    from child_attendance_events e
    join children c2 on c2.id = e.child_id
    where c2.office_id = p_office_id
      and e.event_type in ('drop_off','proxy_drop_off','pick_up','proxy_pick_up')  -- rejected等は対象外
      and (e.occurred_at at time zone 'Asia/Tokyo')::date between v_var_month and v_var_end
    group by e.child_id, (e.occurred_at at time zone 'Asia/Tokyo')::date
    having count(*) filter (where e.event_type in ('drop_off','proxy_drop_off')) = 0
        or count(*) filter (where e.event_type in ('pick_up','proxy_pick_up')) = 0
  ) t
  join children c on c.id = t.child_id;

  -- 7) 休園日の打刻(前月)
  insert into billing_cycle_checks (cycle_id, check_key, severity, child_id, message)
  select distinct v_cycle, 'closed_day_stamp', 'warning', e.child_id,
         c.display_name || ': 休園日 ' || to_char((e.occurred_at at time zone 'Asia/Tokyo')::date, 'MM/DD') || ' に打刻があります(計上していません)'
  from child_attendance_events e
  join children c on c.id = e.child_id
  where c.office_id = p_office_id
    and (e.occurred_at at time zone 'Asia/Tokyo')::date between v_var_month and v_var_end
    and is_office_closed(p_office_id, (e.occurred_at at time zone 'Asia/Tokyo')::date);

  -- 8) 高額警告
  insert into billing_cycle_checks (cycle_id, check_key, severity, child_id, message)
  select v_cycle, 'high_amount', 'warning', i.child_id,
         c.display_name || ': 請求額が高額です(' || i.total_amount || '円)'
  from invoices i join children c on c.id = i.child_id
  where i.cycle_id = v_cycle and i.total_amount > 100000;

  update billing_cycles
     set status = 'review_required', calculated_at = now()
   where id = v_cycle;
  return v_cycle;
end;
$$;
grant execute on function run_billing_cycle(uuid, date) to authenticated, service_role;
revoke execute on function run_billing_cycle(uuid, date) from public, anon;

-- ============================================================
-- (4) 承認・公開・取消(統括のみ=AC-13)
-- ============================================================
create or replace function approve_billing_cycle(p_cycle_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_cycle record;
begin
  if not is_executive_director_or_admin() then raise exception 'not authorized'; end if;
  select * into v_cycle from billing_cycles where id = p_cycle_id;
  if v_cycle.id is null then raise exception 'not found'; end if;
  if not is_billing_enabled_for_office(v_cycle.office_id) then raise exception 'feature disabled'; end if;
  if v_cycle.status <> 'review_required' then
    raise exception '確認待ちのサイクルのみ承認できます(現在: %)', v_cycle.status;
  end if;
  -- errorのチェックが残っている間は承認不可(解消して取消→再実行が正規ルート・レビュー中3)
  if exists (select 1 from billing_cycle_checks
             where cycle_id = p_cycle_id and severity = 'error') then
    raise exception 'エラーのチェックが残っています。内容を解消し、サイクルを取消→再実行してください';
  end if;
  update invoices set status = 'approved', approved_by = my_employee_id(), approved_at = now()
  where cycle_id = p_cycle_id and status = 'draft';
  update billing_cycles set status = 'approved', approved_by = my_employee_id(), approved_at = now()
  where id = p_cycle_id;
end;
$$;
grant execute on function approve_billing_cycle(uuid) to authenticated, service_role;
revoke execute on function approve_billing_cycle(uuid) from public, anon;

create or replace function publish_billing_cycle(p_cycle_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_cycle record;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  if not is_executive_director_or_admin() then raise exception 'not authorized'; end if;
  select * into v_cycle from billing_cycles where id = p_cycle_id;
  if v_cycle.id is null then raise exception 'not found'; end if;
  if not is_billing_enabled_for_office(v_cycle.office_id) then raise exception 'feature disabled'; end if;
  if v_cycle.status <> 'approved' then
    raise exception '承認済みのサイクルのみ公開できます(現在: %)', v_cycle.status;
  end if;
  update invoices
     set status = 'issued', published_at = now(), due_date = v_today + 10   -- 期限=公開+10日(暦日)
   where cycle_id = p_cycle_id and status = 'approved';
  update billing_cycles set status = 'published', published_at = now()
  where id = p_cycle_id;
end;
$$;
grant execute on function publish_billing_cycle(uuid) to authenticated, service_role;
revoke execute on function publish_billing_cycle(uuid) from public, anon;

create or replace function cancel_billing_cycle(p_cycle_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_cycle record;
begin
  if not is_executive_director_or_admin() then raise exception 'not authorized'; end if;
  select * into v_cycle from billing_cycles where id = p_cycle_id;
  if v_cycle.id is null then raise exception 'not found'; end if;
  if not is_billing_enabled_for_office(v_cycle.office_id) then raise exception 'feature disabled'; end if;
  if v_cycle.status = 'published' then
    raise exception '公開済みサイクルは取り消せません(差額は請求額調整で対応してください)';
  end if;
  if v_cycle.status = 'cancelled' then return; end if;
  if p_reason is null or btrim(p_reason) = '' then raise exception '取消理由を入力してください'; end if;

  -- 取込マークの解除(再実行可能に)。調整も未適用へ戻す。請求書・明細は監査のため残すが、
  -- 明細の元記録リンク(source)は外す=再実行時のunique(source_table,source_id)衝突を防ぐ
  -- (レビュー重大2。取消済み明細の由来はdescriptionに残る)
  update billable_usage_days set invoice_item_id = null
  where invoice_item_id in (
    select it.id from invoice_items it
    join invoices i on i.id = it.invoice_id
    where i.cycle_id = p_cycle_id);
  update invoice_adjustments set applied_invoice_id = null
  where applied_invoice_id in (select id from invoices where cycle_id = p_cycle_id);
  update invoice_items set source_table = null, source_id = null
  where invoice_id in (select id from invoices where cycle_id = p_cycle_id)
    and source_table is not null;
  update invoices
     set status = 'cancelled', cancelled_at = now(), cancelled_by = my_employee_id(),
         cancel_reason = p_reason
   where cycle_id = p_cycle_id and status <> 'cancelled';
  update billing_cycles set status = 'cancelled', cancelled_at = now(),
         note = coalesce(note || E'\n', '') || '取消: ' || p_reason
  where id = p_cycle_id;
end;
$$;
grant execute on function cancel_billing_cycle(uuid, text) to authenticated, service_role;
revoke execute on function cancel_billing_cycle(uuid, text) from public, anon;

-- ============================================================
-- (5) 閲覧RPC(主任以上)
-- ============================================================
create or replace function fetch_billing_cycle_overview(p_office_id uuid, p_billing_month date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_cycle record;
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  if not is_billing_enabled_for_office(p_office_id) then raise exception 'feature disabled'; end if;
  select * into v_cycle from billing_cycles
  where office_id = p_office_id and billing_month = date_trunc('month', p_billing_month)::date
    and status <> 'cancelled'
  order by opened_at desc limit 1;
  if v_cycle.id is null then return jsonb_build_object('cycle', null); end if;

  return jsonb_build_object(
    'cycle', jsonb_build_object(
      'id', v_cycle.id, 'billing_month', v_cycle.billing_month, 'status', v_cycle.status,
      'calculated_at', v_cycle.calculated_at, 'approved_at', v_cycle.approved_at,
      'published_at', v_cycle.published_at, 'note', v_cycle.note),
    'invoices', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id, 'invoice_no', i.invoice_no, 'child_id', i.child_id,
        'child_name', c.display_name, 'status', i.status,
        'total_amount', i.total_amount, 'due_date', i.due_date
      ) order by i.invoice_no)
      from invoices i join children c on c.id = i.child_id
      where i.cycle_id = v_cycle.id), '[]'::jsonb),
    'checks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'check_key', ck.check_key, 'severity', ck.severity,
        'child_id', ck.child_id, 'message', ck.message
      ) order by case ck.severity when 'error' then 0 when 'warning' then 1 else 2 end, ck.message)
      from billing_cycle_checks ck where ck.cycle_id = v_cycle.id), '[]'::jsonb),
    'totals', (
      select jsonb_build_object(
        'invoice_count', count(*), 'total_amount', coalesce(sum(i.total_amount), 0))
      from invoices i where i.cycle_id = v_cycle.id and i.status <> 'cancelled')
  );
end;
$$;
grant execute on function fetch_billing_cycle_overview(uuid, date) to authenticated, service_role;
revoke execute on function fetch_billing_cycle_overview(uuid, date) from public, anon;

create or replace function fetch_invoice_detail(p_invoice_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_inv record;
begin
  select i.*, c.display_name as child_name into v_inv
  from invoices i join children c on c.id = i.child_id
  where i.id = p_invoice_id;
  if v_inv.id is null then raise exception 'not found'; end if;
  if not manages_childcare(v_inv.office_id) then raise exception 'not authorized'; end if;
  if not is_billing_enabled_for_office(v_inv.office_id) then raise exception 'feature disabled'; end if;
  return jsonb_build_object(
    'invoice', jsonb_build_object(
      'id', v_inv.id, 'invoice_no', v_inv.invoice_no, 'child_id', v_inv.child_id,
      'child_name', v_inv.child_name, 'billing_month', v_inv.billing_month,
      'status', v_inv.status, 'total_amount', v_inv.total_amount,
      'paid_amount', v_inv.paid_amount, 'due_date', v_inv.due_date,
      'published_at', v_inv.published_at),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'category', it.category, 'description', it.description,
        'target_period', it.target_period, 'quantity', it.quantity,
        'unit_amount', it.unit_amount, 'amount', it.amount
      ) order by it.created_at, it.category)
      from invoice_items it where it.invoice_id = p_invoice_id), '[]'::jsonb)
  );
end;
$$;
grant execute on function fetch_invoice_detail(uuid) to authenticated, service_role;
revoke execute on function fetch_invoice_detail(uuid) from public, anon;

-- ============================================================
-- (6) 請求額調整: 起票=主任以上/承認=統括のみ(§12.5)
-- ============================================================
create or replace function create_invoice_adjustment(
  p_child_id uuid,
  p_adjustment_kind text,
  p_amount int,
  p_guardian_note text,
  p_internal_note text default null,
  p_origin_invoice_id uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_office uuid;
  v_id uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  if not is_billing_enabled_for_office(v_office) then raise exception 'feature disabled'; end if;
  if p_adjustment_kind not in ('plus','minus') then raise exception '調整種別が不正です'; end if;
  if p_amount is null or p_amount <= 0 then raise exception '調整金額は1円以上で指定してください'; end if;
  if p_guardian_note is null or btrim(p_guardian_note) = '' then
    raise exception '保護者向け説明を入力してください';
  end if;
  insert into invoice_adjustments
    (child_id, adjustment_kind, amount, guardian_note, internal_note, origin_invoice_id, created_by)
  values (p_child_id, p_adjustment_kind, p_amount, btrim(p_guardian_note), p_internal_note,
          p_origin_invoice_id, my_employee_id())
  returning id into v_id;
  return v_id;
end;
$$;
grant execute on function create_invoice_adjustment(uuid, text, int, text, text, uuid)
  to authenticated, service_role;
revoke execute on function create_invoice_adjustment(uuid, text, int, text, text, uuid) from public, anon;

create or replace function approve_invoice_adjustment(p_adjustment_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_adj record;
  v_office uuid;
begin
  if not is_executive_director_or_admin() then raise exception 'not authorized'; end if;
  select * into v_adj from invoice_adjustments where id = p_adjustment_id;
  if v_adj.id is null then raise exception 'not found'; end if;
  select office_id into v_office from children where id = v_adj.child_id;
  if not is_billing_enabled_for_office(v_office) then raise exception 'feature disabled'; end if;
  if v_adj.approved_by is not null then raise exception '既に承認済みです'; end if;
  update invoice_adjustments set approved_by = my_employee_id(), approved_at = now()
  where id = p_adjustment_id;
end;
$$;
grant execute on function approve_invoice_adjustment(uuid) to authenticated, service_role;
revoke execute on function approve_invoice_adjustment(uuid) from public, anon;
