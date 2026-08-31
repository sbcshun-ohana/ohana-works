-- 400: 下書き請求書への手動明細の追加・削除(俊要望 2026-08-31)。
--   備品もれ・行事費などを下書き状態の請求書に統括が直接追加できるようにする。
--   原則: 自動生成明細(給食・延長・月極等)は編集不可(計算の証跡を守る)。
--   手動明細は is_manual=true で区別し、手動明細のみ削除可。追加・削除のたび合計を再計算。
--   公開後の修正は「個別差し戻し→再発行(下書き)→明細追加→承認→公開」(399の流れ)。
--   ※再発行(rebuild)は明細を作り直すため、手動明細は再発行の後に追加する運用。

alter table invoice_items add column if not exists is_manual boolean not null default false;

-- fetch_invoice_detail に item id / is_manual を追加(編集UIで使用)
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
        'id', it.id, 'category', it.category, 'description', it.description,
        'target_period', it.target_period, 'quantity', it.quantity,
        'unit_amount', it.unit_amount, 'amount', it.amount,
        'is_manual', it.is_manual
      ) order by it.created_at, it.category)
      from invoice_items it where it.invoice_id = p_invoice_id), '[]'::jsonb)
  );
end;
$$;

-- ============================================================
-- 手動明細の追加(統括のみ・下書きの請求書のみ・手入力系カテゴリのみ)
-- ============================================================
create or replace function add_manual_invoice_item(
  p_invoice_id uuid,
  p_category text,
  p_description text,
  p_quantity numeric,
  p_unit_amount int
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_inv record;
  v_id uuid;
  v_amount int;
begin
  if not is_executive_director_or_admin() then raise exception 'not authorized'; end if;
  select * into v_inv from invoices where id = p_invoice_id;
  if v_inv.id is null then raise exception 'not found'; end if;
  if not is_billing_enabled_for_office(v_inv.office_id) then raise exception 'feature disabled'; end if;
  if v_inv.status <> 'draft' then
    raise exception '明細を追加できるのは下書きの請求書のみです(公開済みは差し戻し→再発行してください)';
  end if;
  -- 手入力を許すのは実費系のみ(月極・給食・延長などの自動計算系は不可=証跡保護)
  if p_category not in ('supply','diaper','event','misc','temp_care','temp_care_meal','temp_care_snack') then
    raise exception 'この種別は自動計算のため手動追加できません';
  end if;
  if p_description is null or btrim(p_description) = '' then raise exception '内容を入力してください'; end if;
  if p_quantity is null or p_quantity <= 0 then raise exception '数量は1以上で入力してください'; end if;
  if p_unit_amount is null or p_unit_amount < 0 then raise exception '単価は0円以上で入力してください'; end if;
  v_amount := round(p_quantity * p_unit_amount)::int;

  insert into invoice_items (invoice_id, category, description, quantity, unit_amount, amount, is_manual)
  values (p_invoice_id, p_category, btrim(p_description), p_quantity, p_unit_amount, v_amount, true)
  returning id into v_id;
  update invoices set total_amount =
    (select coalesce(sum(amount), 0) from invoice_items where invoice_id = p_invoice_id)
  where id = p_invoice_id;
  return v_id;
end;
$$;
grant execute on function add_manual_invoice_item(uuid, text, text, numeric, int)
  to authenticated, service_role;
revoke execute on function add_manual_invoice_item(uuid, text, text, numeric, int) from public, anon;

-- ============================================================
-- 手動明細の削除(統括のみ・下書きのみ・is_manual=trueの行のみ)
-- ============================================================
create or replace function delete_manual_invoice_item(p_item_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_item record;
  v_inv record;
begin
  if not is_executive_director_or_admin() then raise exception 'not authorized'; end if;
  select * into v_item from invoice_items where id = p_item_id;
  if v_item.id is null then raise exception 'not found'; end if;
  select * into v_inv from invoices where id = v_item.invoice_id;
  if not is_billing_enabled_for_office(v_inv.office_id) then raise exception 'feature disabled'; end if;
  if v_inv.status <> 'draft' then raise exception '下書きの請求書のみ変更できます'; end if;
  if not v_item.is_manual then raise exception '自動計算の明細は削除できません'; end if;

  delete from invoice_items where id = p_item_id;
  update invoices set total_amount =
    (select coalesce(sum(amount), 0) from invoice_items where invoice_id = v_item.invoice_id)
  where id = v_item.invoice_id;
end;
$$;
grant execute on function delete_manual_invoice_item(uuid) to authenticated, service_role;
revoke execute on function delete_manual_invoice_item(uuid) from public, anon;
