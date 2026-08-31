-- 404: 会社負担(自社職員の子)の請求範囲を修正(俊確定 2026-08-31)。
--   確定ルール: 無償化されるのは「保育料のみ」。給食費・備品・調整は会社負担でも請求する。
--   → 403は会社負担で a-e(給食c含む)を全スキップしていたが、給食は徴収が正。
--   本migrationで build_child_invoice を修正:
--     会社負担でスキップ = 保育料類のみ = a)月極保育料 / b)月極延長 / d)随時延長・閉園超過
--     会社負担でも請求 = c)給食費(3-5歳は既存ロジックで自動) / e)調整 / f)備品
--   (403を verbatim 踏襲し、company_paid の if 範囲を a,b と d のみに絞る変更)

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
  v_company_paid boolean;   -- 会社負担=保育料類(a,b,d)のみ請求しない。給食c・調整e・備品fは請求
  r record;
begin
  select * into v_cycle from billing_cycles where id = p_cycle_id;
  if v_cycle.id is null then raise exception 'not found'; end if;
  v_month := v_cycle.billing_month;
  v_var_month := (v_month - interval '1 month')::date;
  v_var_end := (v_month - interval '1 day')::date;
  select office_code into v_office_code from offices where id = v_cycle.office_id;
  v_company_paid := exists (select 1 from child_exemptions x
                            where x.child_id = p_child_id and x.kind = 'company_paid'
                              and x.start_month <= v_month
                              and (x.end_month is null or x.end_month >= v_month));

  insert into invoices (cycle_id, child_id, office_id, billing_month, invoice_no, status)
  values (p_cycle_id, p_child_id, v_cycle.office_id, v_month,
          next_invoice_no(v_cycle.office_id, v_month), 'draft')
  returning id into v_invoice;

  -- a) 月極保育料 / b) 月極延長 = 保育料類。会社負担では請求しない。
  if not v_company_paid then
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
  end if;

  -- c) 給食費(大和のみ・前月分・3歳以上クラス基準・登園0日でも請求・免除適用)。
  --    会社負担でも徴収する(無償化は保育料のみ・俊確定2026-08-31)。3-5歳は既存ロジックで自動。
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

  -- d) 変動(随時延長・閉園超過)= 保育料類。会社負担では請求しない。
  if not v_company_paid then
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
  end if;

  -- e) 承認済みの請求額調整(未適用分)。会社負担でも適用(明示的な補正のため)。
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

  -- f) 承認済みの備品注文(未取込分)。会社負担でも保護者実費として請求。
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

-- run_billing_cycle の company_paid スキップ条件も見直し:
--   403では「company_paid かつ 備品注文なし」でスキップだったが、給食も請求対象になったため
--   「company_paid かつ 備品注文なし かつ (給食対象=3-5歳児クラス在籍 でない)」時のみスキップ。
--   実際には build_child_invoice が P0902(明細なし)を返せば zero_total で情報表示されるので、
--   スキップ判定を厳密化するより build に委ねるのが安全。company_paidの事前スキップを撤廃し、
--   全て build_child_invoice に通す(会社負担で明細ゼロなら自然にP0902でスキップ表示)。
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
