-- 399: 請求書の個別差し戻し・再発行(俊要望 2026-08-31)。
--   保護者から「金額が違う」等の指摘があった場合に、その園児の請求書1件だけを
--   差し戻し→(打刻修正・調整などで内容修正)→再発行→承認→公開できるようにする。
--   他の園児の請求はそのまま。入金済みは個別でも差し戻し不可(請求額調整で対応)。
--   実装: 396のサイクルループ内にあった「1園児分の請求書生成」を内部関数
--   build_child_invoice に切り出し、run_billing_cycle(一括)と rebuild_child_invoice
--   (個別再発行)の両方から呼ぶ(ロジックの二重管理を防ぐ)。

-- ============================================================
-- (1) build_child_invoice — 1園児分の請求書生成(内部専用・呼び出し元がsubtransactionで包む)
--     マイナス合計= P0901 / 明細なし= P0902 を投げる(番号消費はロールバックで戻る)
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
revoke execute on function build_child_invoice(uuid, uuid) from public, anon, authenticated;

-- ============================================================
-- (2) run_billing_cycle — ループ本体を build_child_invoice 呼び出しに置換(ロジックは396と同一)
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

  -- ===== 自動チェック(396と同一) =====
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

-- ============================================================
-- (3) cancel_invoice — 園児1件の差し戻し(統括のみ・入金済み不可・公開済みなら取り下げ通知)
-- ============================================================
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
grant execute on function cancel_invoice(uuid, text) to authenticated, service_role;
revoke execute on function cancel_invoice(uuid, text) from public, anon;

-- ============================================================
-- (4) rebuild_child_invoice — 差し戻した園児の再発行(下書き・統括のみ)
-- ============================================================
create or replace function rebuild_child_invoice(p_cycle_id uuid, p_child_id uuid)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_cycle record;
  v_id uuid;
begin
  if not is_executive_director_or_admin() then raise exception 'not authorized'; end if;
  select * into v_cycle from billing_cycles where id = p_cycle_id;
  if v_cycle.id is null then raise exception 'not found'; end if;
  if not is_billing_enabled_for_office(v_cycle.office_id) then raise exception 'feature disabled'; end if;
  if v_cycle.status not in ('review_required','approved','published') then
    raise exception 'このサイクルでは再発行できません(現在: %)', v_cycle.status;
  end if;
  if exists (select 1 from invoices
             where child_id = p_child_id and billing_month = v_cycle.billing_month
               and status <> 'cancelled') then
    raise exception 'この園児には有効な請求書があります(先に差し戻してください)';
  end if;
  -- 変動スナップショットを最新化(打刻修正後の再計算を反映)
  perform generate_billable_usage_days(v_cycle.office_id, (v_cycle.billing_month - interval '1 month')::date);

  begin
    v_id := build_child_invoice(p_cycle_id, p_child_id);
  exception
    when sqlstate 'P0901' then
      raise exception 'マイナス合計のため発行できません(調整内容を見直してください)';
    when sqlstate 'P0902' then
      raise exception '請求対象がありません(契約・実績・調整をご確認ください)';
  end;
  return v_id;
end;
$$;
grant execute on function rebuild_child_invoice(uuid, uuid) to authenticated, service_role;
revoke execute on function rebuild_child_invoice(uuid, uuid) from public, anon;

-- ============================================================
-- (5) approve_invoice / publish_invoice — 個別の承認・公開(統括のみ・公開時に通知)
-- ============================================================
create or replace function approve_invoice(p_invoice_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_inv record;
begin
  if not is_executive_director_or_admin() then raise exception 'not authorized'; end if;
  select * into v_inv from invoices where id = p_invoice_id;
  if v_inv.id is null then raise exception 'not found'; end if;
  if not is_billing_enabled_for_office(v_inv.office_id) then raise exception 'feature disabled'; end if;
  if v_inv.status <> 'draft' then raise exception '下書きの請求のみ承認できます(現在: %)', v_inv.status; end if;
  update invoices set status = 'approved', approved_by = my_employee_id(), approved_at = now()
  where id = p_invoice_id;
end;
$$;
grant execute on function approve_invoice(uuid) to authenticated, service_role;
revoke execute on function approve_invoice(uuid) from public, anon;

create or replace function publish_invoice(p_invoice_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_inv record;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  if not is_executive_director_or_admin() then raise exception 'not authorized'; end if;
  select * into v_inv from invoices where id = p_invoice_id;
  if v_inv.id is null then raise exception 'not found'; end if;
  if not is_billing_enabled_for_office(v_inv.office_id) then raise exception 'feature disabled'; end if;
  if v_inv.status <> 'approved' then raise exception '承認済みの請求のみ公開できます(現在: %)', v_inv.status; end if;

  update invoices
     set status = 'issued', published_at = now(), due_date = v_today + 10
   where id = p_invoice_id;

  insert into notifications (notification_type, title, body, channels, target_guardian_id, payload, status)
  select 'invoice_published',
         to_char(v_inv.billing_month, 'YYYY年FMMM月') || '分のご請求のお知らせ',
         c.display_name || 'さんの' || to_char(v_inv.billing_month, 'FMMM月') || '分ご請求(¥'
           || to_char(v_inv.total_amount, 'FM999,999,999') || ')を公開しました。お支払い期限は'
           || to_char(v_today + 10, 'FMMM月FMDD日') || 'です。アプリでご確認ください。',
         array['in_app','push'], g.guardian_id,
         jsonb_build_object('invoice_id', v_inv.id::text), 'pending'
  from children c
  join (select distinct gcl.guardian_id, gcl.child_id from guardian_child_links gcl) g
    on g.child_id = c.id
  where c.id = v_inv.child_id;
end;
$$;
grant execute on function publish_invoice(uuid) to authenticated, service_role;
revoke execute on function publish_invoice(uuid) from public, anon;
