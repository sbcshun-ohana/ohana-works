-- 398: 請求管理UI改善2件(俊要望 2026-08-31)
--   (1) fetch_billing_cycle_overview へ class_name を追加(クラスフィルター用)
--   (2) 公開済みサイクルの差し戻しを統括のみ可能に(cancel_billing_cycle 再定義):
--       ・入金済み(paid_amount>0)の請求が1件でもあれば差し戻し不可(返金は請求額調整で対応)
--       ・公開済みを差し戻すと保護者アプリから消えるため、保護者へ取り下げ通知を送る
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
        'total_amount', i.total_amount, 'due_date', i.due_date,
        'class_name', (
          select cl.class_name from child_class_enrollments cce
          join childcare_classes cl on cl.id = cce.class_id
          where cce.child_id = c.id
            and cce.effective_start_date <= (now() at time zone 'Asia/Tokyo')::date
            and (cce.effective_end_date is null
                 or cce.effective_end_date >= (now() at time zone 'Asia/Tokyo')::date)
          order by cce.effective_start_date desc limit 1)
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

-- ============================================================
-- (2) cancel_billing_cycle — 公開済みの差し戻しを許可(統括のみ・入金済みは不可)
-- ============================================================
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

  -- 入金が始まっている請求があれば差し戻し不可(過去請求は不変の原則・差額は請求額調整で)
  if exists (select 1 from invoices
             where cycle_id = p_cycle_id and status <> 'cancelled' and paid_amount > 0) then
    raise exception '入金済みの請求があるため差し戻しできません(請求額調整で対応してください)';
  end if;

  -- 取込マークの解除(再実行可能に)。調整も未適用へ戻す。請求書・明細は監査のため残すが、
  -- 明細の元記録リンク(source)は外す=再実行時のunique(source_table,source_id)衝突を防ぐ
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

  -- 公開済みだった場合、保護者へ取り下げのお知らせ(混乱防止)
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
