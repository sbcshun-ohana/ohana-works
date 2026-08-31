-- 401: 備品注文機能(俊要件 2026-08-28・設計承認 2026-08-31)。
--   保護者がアプリから備品(料金マスターのsupply品目)を注文→園(主任以上)が承認で確定
--   →月次請求サイクルが「備品代」明細として自動合算(1注文=1明細・source 1:1でAC-11)。
--   単価は承認時点の版でスナップショット(承認後の単価改訂に影響されない)。
--   却下=理由必須・保護者へ通知。保護者は申請中のみ取消可。

-- ============================================================
-- (1) supply_orders
-- ============================================================
create table supply_orders (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id),
  office_id uuid not null references offices(id),
  fee_item_id uuid not null references fee_items(id),
  quantity int not null check (quantity between 1 and 20),
  status text not null default 'requested'
    check (status in ('requested','approved','rejected','cancelled')),
  note text,                                  -- 保護者からの備考(サイズ等)
  requested_by uuid references guardians(id),
  requested_at timestamptz not null default now(),
  approved_by uuid references employees(id),
  approved_at timestamptz,
  unit_amount int,                            -- 承認時点の単価スナップショット
  fee_rate_version_id uuid references fee_rate_versions(id),
  rejected_reason text,
  cancelled_at timestamptz,
  invoice_item_id uuid references invoice_items(id),  -- 請求取込マーク(二重計上防止)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_supply_orders_child on supply_orders(child_id);
create index idx_supply_orders_office_status on supply_orders(office_id, status);
create trigger trg_supply_orders_updated before update on supply_orders
  for each row execute function set_updated_at();
alter table supply_orders enable row level security;

-- ============================================================
-- (2) 保護者側RPC
-- ============================================================
-- 注文できる備品カタログ(単価未登録の品目は出さない)
create or replace function fetch_supply_catalog(p_child_id uuid)
returns table (fee_item_id uuid, name text, unit_amount int, display_note text)
language plpgsql stable security definer set search_path = public as $$
declare
  v_guardian uuid := my_guardian_id();
  v_office uuid;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  if v_guardian is null then raise exception 'not authorized'; end if;
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'not found'; end if;
  if not exists (select 1 from guardian_child_links gcl
                 where gcl.guardian_id = v_guardian and gcl.child_id = p_child_id) then
    raise exception 'not authorized';
  end if;
  if not is_billing_enabled_for_office(v_office) then raise exception 'feature disabled'; end if;
  return query
  select f.id, f.name, v.amount, f.display_note
  from fee_items f
  join fee_rate_versions v on v.fee_item_id = f.id
    and v.effective_from <= v_today and (v.effective_to is null or v.effective_to >= v_today)
  where f.office_id = v_office and f.category = 'supply' and f.is_active
  order by f.sort_order, f.name;
end;
$$;
grant execute on function fetch_supply_catalog(uuid) to authenticated, service_role;
revoke execute on function fetch_supply_catalog(uuid) from public, anon;

create or replace function create_supply_order(
  p_child_id uuid,
  p_fee_item_id uuid,
  p_quantity int,
  p_note text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_guardian uuid := my_guardian_id();
  v_office uuid;
  v_item record;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
  v_id uuid;
begin
  if v_guardian is null then raise exception 'not authorized'; end if;
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'not found'; end if;
  if not exists (select 1 from guardian_child_links gcl
                 where gcl.guardian_id = v_guardian and gcl.child_id = p_child_id) then
    raise exception 'not authorized';
  end if;
  if not is_billing_enabled_for_office(v_office) then raise exception 'feature disabled'; end if;
  select * into v_item from fee_items where id = p_fee_item_id;
  if v_item.id is null or v_item.office_id <> v_office
     or v_item.category <> 'supply' or not v_item.is_active then
    raise exception 'この品目は注文できません';
  end if;
  if not exists (select 1 from fee_rate_versions v
                 where v.fee_item_id = p_fee_item_id
                   and v.effective_from <= v_today
                   and (v.effective_to is null or v.effective_to >= v_today)) then
    raise exception 'この品目は現在注文を受け付けていません(単価未設定)';
  end if;
  if p_quantity is null or p_quantity < 1 or p_quantity > 20 then
    raise exception '数量は1〜20で指定してください';
  end if;

  insert into supply_orders (child_id, office_id, fee_item_id, quantity, note, requested_by)
  values (p_child_id, v_office, p_fee_item_id, p_quantity, nullif(btrim(coalesce(p_note,'')), ''), v_guardian)
  returning id into v_id;
  return v_id;
end;
$$;
grant execute on function create_supply_order(uuid, uuid, int, text) to authenticated, service_role;
revoke execute on function create_supply_order(uuid, uuid, int, text) from public, anon;

create or replace function fetch_my_supply_orders(p_child_id uuid)
returns table (
  order_id uuid, item_name text, quantity int, status text,
  unit_amount int, amount int, note text, rejected_reason text, requested_at timestamptz
)
language plpgsql stable security definer set search_path = public as $$
declare
  v_guardian uuid := my_guardian_id();
begin
  if v_guardian is null then raise exception 'not authorized'; end if;
  if not exists (select 1 from guardian_child_links gcl
                 where gcl.guardian_id = v_guardian and gcl.child_id = p_child_id) then
    raise exception 'not authorized';
  end if;
  return query
  select o.id, f.name, o.quantity, o.status,
         o.unit_amount, o.unit_amount * o.quantity, o.note, o.rejected_reason, o.requested_at
  from supply_orders o
  join fee_items f on f.id = o.fee_item_id
  where o.child_id = p_child_id
  order by o.requested_at desc;
end;
$$;
grant execute on function fetch_my_supply_orders(uuid) to authenticated, service_role;
revoke execute on function fetch_my_supply_orders(uuid) from public, anon;

create or replace function cancel_supply_order(p_order_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_guardian uuid := my_guardian_id();
  v_order record;
begin
  if v_guardian is null then raise exception 'not authorized'; end if;
  select * into v_order from supply_orders where id = p_order_id;
  if v_order.id is null then raise exception 'not found'; end if;
  if v_order.requested_by is distinct from v_guardian then raise exception 'not authorized'; end if;
  if v_order.status <> 'requested' then
    raise exception '承認済みの注文は取り消せません(園にご相談ください)';
  end if;
  update supply_orders set status = 'cancelled', cancelled_at = now() where id = p_order_id;
end;
$$;
grant execute on function cancel_supply_order(uuid) to authenticated, service_role;
revoke execute on function cancel_supply_order(uuid) from public, anon;

-- ============================================================
-- (3) 園側RPC(主任以上)
-- ============================================================
create or replace function fetch_supply_orders(p_office_id uuid)
returns table (
  order_id uuid, child_id uuid, child_name text, class_name text,
  item_name text, quantity int, status text, note text,
  unit_amount int, requested_at timestamptz, guardian_name text
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  if not is_billing_enabled_for_office(p_office_id) then raise exception 'feature disabled'; end if;
  return query
  select o.id, c.id, c.display_name,
         (select cl.class_name from child_class_enrollments cce
          join childcare_classes cl on cl.id = cce.class_id
          where cce.child_id = c.id
            and cce.effective_start_date <= (now() at time zone 'Asia/Tokyo')::date
            and (cce.effective_end_date is null
                 or cce.effective_end_date >= (now() at time zone 'Asia/Tokyo')::date)
          order by cce.effective_start_date desc limit 1),
         f.name, o.quantity, o.status, o.note, o.unit_amount, o.requested_at, g.name
  from supply_orders o
  join children c on c.id = o.child_id
  join fee_items f on f.id = o.fee_item_id
  left join guardians g on g.id = o.requested_by
  where o.office_id = p_office_id
    and (o.status = 'requested'
         or (o.status = 'approved' and o.invoice_item_id is null)
         or o.requested_at > now() - interval '30 days')
  order by case o.status when 'requested' then 0 else 1 end, o.requested_at desc;
end;
$$;
grant execute on function fetch_supply_orders(uuid) to authenticated, service_role;
revoke execute on function fetch_supply_orders(uuid) from public, anon;

create or replace function approve_supply_order(p_order_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_order record;
  v_rate record;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  select * into v_order from supply_orders where id = p_order_id;
  if v_order.id is null then raise exception 'not found'; end if;
  if not manages_childcare(v_order.office_id) then raise exception 'not authorized'; end if;
  if not is_billing_enabled_for_office(v_order.office_id) then raise exception 'feature disabled'; end if;
  if v_order.status <> 'requested' then
    raise exception '申請中の注文のみ承認できます(現在: %)', v_order.status;
  end if;
  select v.id, v.amount into v_rate from fee_rate_versions v
  where v.fee_item_id = v_order.fee_item_id
    and v.effective_from <= v_today and (v.effective_to is null or v.effective_to >= v_today)
  limit 1;
  if v_rate.id is null then raise exception 'この品目の単価が未設定です(料金マスターをご確認ください)'; end if;

  update supply_orders
     set status = 'approved', approved_by = my_employee_id(), approved_at = now(),
         unit_amount = v_rate.amount, fee_rate_version_id = v_rate.id
   where id = p_order_id;

  -- 保護者へお知らせ(次回請求に載る旨)
  insert into notifications (notification_type, title, body, channels, target_guardian_id, payload, status)
  select 'supply_order_approved', '備品のご注文を承りました',
         c.display_name || 'さんの「' || f.name || '」×' || v_order.quantity
           || '(' || to_char(v_rate.amount * v_order.quantity, 'FM999,999,999') || '円)を承りました。次回のご請求に合算されます。',
         array['in_app','push'], v_order.requested_by,
         jsonb_build_object('order_id', v_order.id::text), 'pending'
  from children c, fee_items f
  where c.id = v_order.child_id and f.id = v_order.fee_item_id
    and v_order.requested_by is not null;
end;
$$;
grant execute on function approve_supply_order(uuid) to authenticated, service_role;
revoke execute on function approve_supply_order(uuid) from public, anon;

create or replace function reject_supply_order(p_order_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_order record;
begin
  select * into v_order from supply_orders where id = p_order_id;
  if v_order.id is null then raise exception 'not found'; end if;
  if not manages_childcare(v_order.office_id) then raise exception 'not authorized'; end if;
  if not is_billing_enabled_for_office(v_order.office_id) then raise exception 'feature disabled'; end if;
  if v_order.status <> 'requested' then
    raise exception '申請中の注文のみ却下できます(現在: %)', v_order.status;
  end if;
  if p_reason is null or btrim(p_reason) = '' then raise exception '却下理由を入力してください'; end if;

  update supply_orders set status = 'rejected', rejected_reason = btrim(p_reason) where id = p_order_id;

  insert into notifications (notification_type, title, body, channels, target_guardian_id, payload, status)
  select 'supply_order_rejected', '備品のご注文について',
         c.display_name || 'さんの「' || f.name || '」のご注文は次の理由によりお受けできませんでした: ' || btrim(p_reason),
         array['in_app','push'], v_order.requested_by,
         jsonb_build_object('order_id', v_order.id::text), 'pending'
  from children c, fee_items f
  where c.id = v_order.child_id and f.id = v_order.fee_item_id
    and v_order.requested_by is not null;
end;
$$;
grant execute on function reject_supply_order(uuid, text) to authenticated, service_role;
revoke execute on function reject_supply_order(uuid, text) from public, anon;

-- ============================================================
-- (4) build_child_invoice — f)承認済み備品注文の取込を追加(399の定義+fブロックのみ追加)
-- ============================================================
create or replace function build_child_invoice(p_cycle_id uuid, p_child_id uuid)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_cycle record;
  v_month date;
  v_var_month date;
  v_var_end date;
  v_office_code text;
  v_invoice uuid;
  v_total int;
  v_item uuid;
  r record;
begin
  select * into v_cycle from billing_cycles where id = p_cycle_id;
  if v_cycle.id is null then raise exception 'not found'; end if;
  v_month := v_cycle.billing_month;
  v_var_month := (v_month - interval '1 month')::date;
  v_var_end := (v_month - interval '1 day')::date;
  select office_code into v_office_code from offices where id = v_cycle.office_id;

  insert into invoices (cycle_id, child_id, office_id, billing_month, invoice_no, status)
  values (p_cycle_id, p_child_id, v_cycle.office_id, v_month,
          next_invoice_no(v_cycle.office_id, v_month), 'draft')
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
  where cc.child_id = p_child_id
    and cc.start_month <= v_month and (cc.end_month is null or cc.end_month >= v_month)
    and p.monthly_fee_item_id is not null
    and not exists (select 1 from child_exemptions x
                    where x.child_id = p_child_id and x.kind = 'free_childcare'
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
  where ec.child_id = p_child_id
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
    where f.office_id = v_cycle.office_id
      and f.category in ('meal_main','meal_side')
      and f.is_active
      and exists (
        select 1 from child_class_enrollments cce
        join childcare_classes cl on cl.id = cce.class_id
        where cce.child_id = p_child_id
          and cl.office_id = v_cycle.office_id
          and cce.effective_start_date <= v_var_end
          and (cce.effective_end_date is null or cce.effective_end_date >= v_var_end)
          and substring(cl.age_group from '[0-9]')::int >= 3)
      and not exists (
        select 1 from child_exemptions x
        where x.child_id = p_child_id and x.kind = f.category
          and x.start_month <= v_var_month
          and (x.end_month is null or x.end_month >= v_var_month));
  end if;

  -- d) 変動(未取込の全実績・kind×発生月×単価版で集約・施設一致)
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
    where b.child_id = p_child_id
      and b.office_id = v_cycle.office_id
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
    where child_id = p_child_id and office_id = v_cycle.office_id
      and kind = r.kind and unit_amount = r.unit_amount
      and fee_rate_version_id is not distinct from r.fee_rate_version_id
      and date_trunc('month', usage_date)::date = r.usage_month
      and invoice_item_id is null;
  end loop;

  -- e) 承認済みの請求額調整(未適用分)
  for r in
    select a.id, a.adjustment_kind, a.amount, a.guardian_note
    from invoice_adjustments a
    where a.child_id = p_child_id
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

  -- f) 承認済みの備品注文(未取込分・401)。1注文=1明細・単価は承認時スナップショット
  for r in
    select o.id, o.quantity, o.unit_amount, o.fee_rate_version_id, o.note, f.name as item_name
    from supply_orders o
    join fee_items f on f.id = o.fee_item_id
    where o.child_id = p_child_id
      and o.office_id = v_cycle.office_id
      and o.status = 'approved'
      and o.invoice_item_id is null
  loop
    insert into invoice_items (invoice_id, category, description, quantity, unit_amount, amount,
                               fee_rate_version_id, source_table, source_id)
    values (v_invoice, 'supply',
            r.item_name || coalesce('(' || r.note || ')', ''),
            r.quantity, r.unit_amount, r.quantity * r.unit_amount,
            r.fee_rate_version_id, 'supply_orders', r.id)
    returning id into v_item;
    update supply_orders set invoice_item_id = v_item where id = r.id;
  end loop;

  select coalesce(sum(amount), 0) into v_total from invoice_items where invoice_id = v_invoice;
  if v_total < 0 then
    raise exception using errcode = 'P0901';
  elsif not exists (select 1 from invoice_items where invoice_id = v_invoice) then
    raise exception using errcode = 'P0902';
  end if;
  update invoices set total_amount = v_total where id = v_invoice;
  return v_invoice;
end;
$$;

-- ============================================================
-- (5) 対象園児の抽出に「承認済み・未取込の備品注文がある子」を追加(run_billing_cycleの
--     eligible条件のみ変更・他は399と同一)+取消系で注文の取込マークも解除
-- ============================================================
create or replace function run_billing_cycle(p_office_id uuid, p_billing_month date)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_month date;
  v_var_month date;
  v_var_end date;
  v_office_code text;
  v_cycle uuid;
  v_child record;
  v_fiscal int;
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

  perform generate_billable_usage_days(p_office_id, v_var_month);

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
        or exists (select 1 from supply_orders o
                   where o.child_id = c.id and o.office_id = p_office_id
                     and o.status = 'approved' and o.invoice_item_id is null)
      )
    order by c.display_name
  loop
    if exists (select 1 from child_exemptions x
               where x.child_id = v_child.id and x.kind = 'company_paid'
                 and x.start_month <= v_month and (x.end_month is null or x.end_month >= v_month)) then
      insert into billing_cycle_checks (cycle_id, check_key, severity, child_id, message)
      values (v_cycle, 'company_paid_skip', 'info', v_child.id,
              v_child.display_name || ': 会社負担のため請求書を作成しません');
      continue;
    end if;

    begin
      perform build_child_invoice(v_cycle, v_child.id);
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

  insert into billing_cycle_checks (cycle_id, check_key, severity, child_id, message)
  select v_cycle, 'missing_contract', 'error', c.id, c.display_name || ': 請求月の契約プランが未設定です'
  from children c
  where c.office_id = p_office_id and c.enrollment_status = '在籍中'
    and not exists (select 1 from child_contracts cc
                    where cc.child_id = c.id and cc.start_month <= v_month
                      and (cc.end_month is null or cc.end_month >= v_month));

  insert into billing_cycle_checks (cycle_id, check_key, severity, child_id, message)
  select v_cycle, 'open_contract_after_withdrawal', 'warning', c.id,
         c.display_name || ': 退園済みですが契約が終了していません'
  from children c
  join child_contracts cc on cc.child_id = c.id
  where c.office_id = p_office_id and c.enrollment_status = '退園済み'
    and cc.start_month <= v_month and (cc.end_month is null or cc.end_month >= v_month);

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
    and not exists (select 1 from child_exemptions x
                    where x.child_id = cc.child_id and x.kind = 'free_childcare'
                      and x.start_month <= v_month
                      and (x.end_month is null or x.end_month >= v_month));

  insert into billing_cycle_checks (cycle_id, check_key, severity, child_id, message)
  select v_cycle, 'exemption_doc_unconfirmed', 'error', x.child_id,
         c.display_name || ': 免除の書類が未確認です(' || x.document_state || ')'
  from child_exemptions x
  join children c on c.id = x.child_id
  where c.office_id = p_office_id
    and x.document_state in ('pending','deficient')
    and x.start_month <= v_month and (x.end_month is null or x.end_month >= v_month);

  insert into billing_cycle_checks (cycle_id, check_key, severity, child_id, message)
  select v_cycle, 'exemption_fy_mismatch', 'error', x.child_id,
         c.display_name || ': 免除書類の年度(' || coalesce(x.document_fiscal_year::text, '未記入')
           || ')が対象年度(' || v_fiscal || ')と一致しません'
  from child_exemptions x
  join children c on c.id = x.child_id
  where c.office_id = p_office_id
    and x.document_state = 'confirmed'
    and (x.document_fiscal_year is null or x.document_fiscal_year <> v_fiscal)
    and x.start_month <= v_month and (x.end_month is null or x.end_month >= v_var_month);

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
      and e.event_type in ('drop_off','proxy_drop_off','pick_up','proxy_pick_up')
      and (e.occurred_at at time zone 'Asia/Tokyo')::date between v_var_month and v_var_end
    group by e.child_id, (e.occurred_at at time zone 'Asia/Tokyo')::date
    having count(*) filter (where e.event_type in ('drop_off','proxy_drop_off')) = 0
        or count(*) filter (where e.event_type in ('pick_up','proxy_pick_up')) = 0
  ) t
  join children c on c.id = t.child_id;

  insert into billing_cycle_checks (cycle_id, check_key, severity, child_id, message)
  select distinct v_cycle, 'closed_day_stamp', 'warning', e.child_id,
         c.display_name || ': 休園日 ' || to_char((e.occurred_at at time zone 'Asia/Tokyo')::date, 'MM/DD') || ' に打刻があります(計上していません)'
  from child_attendance_events e
  join children c on c.id = e.child_id
  where c.office_id = p_office_id
    and (e.occurred_at at time zone 'Asia/Tokyo')::date between v_var_month and v_var_end
    and is_office_closed(p_office_id, (e.occurred_at at time zone 'Asia/Tokyo')::date);

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

-- 取消時に備品注文の取込マークも解除(サイクル取消=398版+1行/個別取消=399版+1行)
create or replace function cancel_billing_cycle(p_cycle_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_cycle record;
  v_was_published boolean;
begin
  if not is_executive_director_or_admin() then raise exception 'not authorized'; end if;
  select * into v_cycle from billing_cycles where id = p_cycle_id;
  if v_cycle.id is null then raise exception 'not found'; end if;
  if not is_billing_enabled_for_office(v_cycle.office_id) then raise exception 'feature disabled'; end if;
  if v_cycle.status = 'cancelled' then return; end if;
  if p_reason is null or btrim(p_reason) = '' then raise exception '取消理由を入力してください'; end if;
  v_was_published := (v_cycle.status = 'published');

  if exists (select 1 from invoices
             where cycle_id = p_cycle_id and status <> 'cancelled' and paid_amount > 0) then
    raise exception '入金済みの請求があるため差し戻しできません(請求額調整で対応してください)';
  end if;

  update billable_usage_days set invoice_item_id = null
  where invoice_item_id in (
    select it.id from invoice_items it
    join invoices i on i.id = it.invoice_id
    where i.cycle_id = p_cycle_id);
  update supply_orders set invoice_item_id = null
  where invoice_item_id in (
    select it.id from invoice_items it
    join invoices i on i.id = it.invoice_id
    where i.cycle_id = p_cycle_id);
  update invoice_adjustments set applied_invoice_id = null
  where applied_invoice_id in (select id from invoices where cycle_id = p_cycle_id);
  update invoice_items set source_table = null, source_id = null
  where invoice_id in (select id from invoices where cycle_id = p_cycle_id)
    and source_table is not null;

  if v_was_published then
    insert into notifications (notification_type, title, body, channels, target_guardian_id, payload, status)
    select 'invoice_withdrawn',
           to_char(i.billing_month, 'YYYY年FMMM月') || '分のご請求 取り下げのお知らせ',
           c.display_name || 'さんの' || to_char(i.billing_month, 'FMMM月')
             || '分ご請求は、園の都合により一旦取り下げました。再発行までお待ちください。',
           array['in_app','push'], g.guardian_id,
           jsonb_build_object('invoice_id', i.id::text), 'pending'
    from invoices i
    join children c on c.id = i.child_id
    join (select distinct gcl.guardian_id, gcl.child_id from guardian_child_links gcl) g
      on g.child_id = i.child_id
    where i.cycle_id = p_cycle_id and i.status = 'issued';
  end if;

  update invoices
     set status = 'cancelled', cancelled_at = now(), cancelled_by = my_employee_id(),
         cancel_reason = p_reason
   where cycle_id = p_cycle_id and status <> 'cancelled';
  update billing_cycles set status = 'cancelled', cancelled_at = now(),
         note = coalesce(note || E'\n', '') || case when v_was_published then '差し戻し: ' else '取消: ' end || p_reason
  where id = p_cycle_id;
end;
$$;

create or replace function cancel_invoice(p_invoice_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_inv record;
begin
  if not is_executive_director_or_admin() then raise exception 'not authorized'; end if;
  select * into v_inv from invoices where id = p_invoice_id;
  if v_inv.id is null then raise exception 'not found'; end if;
  if not is_billing_enabled_for_office(v_inv.office_id) then raise exception 'feature disabled'; end if;
  if v_inv.status = 'cancelled' then return; end if;
  if p_reason is null or btrim(p_reason) = '' then raise exception '差し戻し理由を入力してください'; end if;
  if v_inv.paid_amount > 0 then
    raise exception '入金済みのため差し戻しできません(請求額調整で対応してください)';
  end if;

  update billable_usage_days set invoice_item_id = null
  where invoice_item_id in (select id from invoice_items where invoice_id = p_invoice_id);
  update supply_orders set invoice_item_id = null
  where invoice_item_id in (select id from invoice_items where invoice_id = p_invoice_id);
  update invoice_adjustments set applied_invoice_id = null
  where applied_invoice_id = p_invoice_id;
  update invoice_items set source_table = null, source_id = null
  where invoice_id = p_invoice_id and source_table is not null;

  if v_inv.status = 'issued' then
    insert into notifications (notification_type, title, body, channels, target_guardian_id, payload, status)
    select 'invoice_withdrawn',
           to_char(v_inv.billing_month, 'YYYY年FMMM月') || '分のご請求 取り下げのお知らせ',
           c.display_name || 'さんの' || to_char(v_inv.billing_month, 'FMMM月')
             || '分ご請求は、内容確認のため一旦取り下げました。再発行までお待ちください。',
           array['in_app','push'], g.guardian_id,
           jsonb_build_object('invoice_id', v_inv.id::text), 'pending'
    from children c
    join (select distinct gcl.guardian_id, gcl.child_id from guardian_child_links gcl) g
      on g.child_id = c.id
    where c.id = v_inv.child_id;
  end if;

  update invoices
     set status = 'cancelled', cancelled_at = now(), cancelled_by = my_employee_id(),
         cancel_reason = p_reason
   where id = p_invoice_id;
end;
$$;
