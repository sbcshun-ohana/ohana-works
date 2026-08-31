-- 397: 請求決済 Phase8a — 保護者アプリの請求閲覧+公開通知(2026-08-31俊承認)。
--   閲覧は billing_enabled のみで可(確定仕様)。支払い(Stripe)は8bでbilling_payment_enabled
--   フラグと共に追加する(fetch_my_invoice_detail が payment_enabled を返しUI出し分けに使う)。
--   公開済み(issued以降)の請求のみ保護者へ見せる(下書き・承認前は不可視=§12.6)。
--   公開時通知は313(重要事項説明書)と同型: notifications へ挿入→毎分cronがpush配信。

-- ============================================================
-- (1) fetch_my_invoices — 自分の子の公開済み請求一覧(保護者)
-- ============================================================
create or replace function fetch_my_invoices()
returns table (
  invoice_id uuid,
  invoice_no text,
  child_id uuid,
  child_name text,
  billing_month date,
  status text,
  total_amount int,
  paid_amount int,
  due_date date,
  published_at timestamptz
)
language plpgsql stable security definer set search_path = public as $$
declare
  v_guardian uuid := my_guardian_id();
begin
  if v_guardian is null then raise exception 'not authorized'; end if;
  return query
  select i.id, i.invoice_no, i.child_id, c.display_name, i.billing_month, i.status,
         i.total_amount, i.paid_amount, i.due_date, i.published_at
  from invoices i
  join children c on c.id = i.child_id
  where i.status in ('issued','payment_pending','partially_paid','paid','overdue')
    and is_billing_enabled_for_office(i.office_id)
    and exists (select 1 from guardian_child_links gcl
                where gcl.guardian_id = v_guardian and gcl.child_id = i.child_id)
  order by i.billing_month desc, c.display_name, i.invoice_no;
end;
$$;
grant execute on function fetch_my_invoices() to authenticated, service_role;
revoke execute on function fetch_my_invoices() from public, anon;

-- ============================================================
-- (2) fetch_my_invoice_detail — 明細(保護者)。調整明細は区別できるようフラグ付き
-- ============================================================
create or replace function fetch_my_invoice_detail(p_invoice_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_guardian uuid := my_guardian_id();
  v_inv record;
begin
  if v_guardian is null then raise exception 'not authorized'; end if;
  select i.*, c.display_name as child_name into v_inv
  from invoices i join children c on c.id = i.child_id
  where i.id = p_invoice_id;
  if v_inv.id is null then raise exception 'not found'; end if;
  if not exists (select 1 from guardian_child_links gcl
                 where gcl.guardian_id = v_guardian and gcl.child_id = v_inv.child_id) then
    raise exception 'not authorized';
  end if;
  if v_inv.status not in ('issued','payment_pending','partially_paid','paid','overdue') then
    raise exception 'not found';   -- 未公開・取消は保護者には存在しない扱い(§12.6)
  end if;
  if not is_billing_enabled_for_office(v_inv.office_id) then raise exception 'feature disabled'; end if;

  return jsonb_build_object(
    'invoice', jsonb_build_object(
      'id', v_inv.id, 'invoice_no', v_inv.invoice_no, 'child_name', v_inv.child_name,
      'billing_month', v_inv.billing_month, 'status', v_inv.status,
      'total_amount', v_inv.total_amount, 'paid_amount', v_inv.paid_amount,
      'due_date', v_inv.due_date, 'published_at', v_inv.published_at),
    -- 支払いボタンの出し分け(8b)。現状は payment フラグOFF=false
    'payment_enabled', is_billing_payment_enabled_for_office(v_inv.office_id),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'category', it.category, 'description', it.description,
        'target_period', it.target_period, 'quantity', it.quantity,
        'unit_amount', it.unit_amount, 'amount', it.amount,
        'is_adjustment', it.category in ('adjustment_plus','adjustment_minus')
      ) order by it.created_at, it.category)
      from invoice_items it where it.invoice_id = p_invoice_id), '[]'::jsonb)
  );
end;
$$;
grant execute on function fetch_my_invoice_detail(uuid) to authenticated, service_role;
revoke execute on function fetch_my_invoice_detail(uuid) from public, anon;

-- ============================================================
-- (3) publish_billing_cycle — 公開時に保護者へ通知を追加(396から通知ブロックのみ追加)
-- ============================================================
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

  -- 公開した請求の保護者へ通知(in_app+push・313と同型。子ごとに1通=請求書ごと)
  insert into notifications (notification_type, title, body, channels, target_guardian_id, payload, status)
  select 'invoice_published',
         to_char(i.billing_month, 'YYYY年FMMM月') || '分のご請求のお知らせ',
         c.display_name || 'さんの' || to_char(i.billing_month, 'FMMM月') || '分ご請求(¥'
           || to_char(i.total_amount, 'FM999,999,999') || ')を公開しました。お支払い期限は'
           || to_char(i.due_date, 'FMMM月FMDD日') || 'です。アプリでご確認ください。',
         array['in_app','push'], g.guardian_id,
         jsonb_build_object('invoice_id', i.id::text), 'pending'
  from invoices i
  join children c on c.id = i.child_id
  join (select distinct gcl.guardian_id, gcl.child_id from guardian_child_links gcl) g
    on g.child_id = i.child_id
  where i.cycle_id = p_cycle_id and i.status = 'issued';
end;
$$;
grant execute on function publish_billing_cycle(uuid) to authenticated, service_role;
revoke execute on function publish_billing_cycle(uuid) from public, anon;
