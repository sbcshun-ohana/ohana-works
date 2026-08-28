-- 388: 請求決済 Phase2 — 料金マスター管理RPC(2026-08-28俊承認の設計どおり)。
--   権限写像(2026-08-28確定): 閲覧=主任以上 manages_childcare(147) / 登録・改訂=統括園長以上
--   is_executive_director_or_admin()(205)。386の方針どおり直テーブルアクセスは不可(RLSポリシー無し)
--   のまま、全て定義者RPC経由。金額はKids・一般職員に出さない(AC-22)=一般職員はRPC自体が拒否。
--   版運用: 改訂=新版追加+旧版autoクローズ(書き換え禁止=AC-14/20)。適用中・過去の版は削除不可。
--   未来日付の最新版のみ取消可(入力ミス救済)。
--   契約プラン(contract_plans/monthly_extension_plans/closing_overrun_rules)は本Phaseでは閲覧のみ
--   (改訂UIはPhase3で契約と一緒に扱う)。

-- ============================================================
-- (1) fetch_billing_offices — 請求フラグONかつ自分が管理する施設一覧。
--     admin Webのナビ表示判定を兼ねる(0件=料金マスタータブ非表示)。
-- ============================================================
create or replace function fetch_billing_offices()
returns table (office_id uuid, office_name text, office_code text, can_edit boolean)
language sql stable security definer set search_path = public as $$
  select o.id, o.name, o.office_code, is_executive_director_or_admin()
  from offices o
  where is_billing_enabled_for_office(o.id)
    and manages_childcare(o.id)
  order by o.office_code;
$$;
grant execute on function fetch_billing_offices() to authenticated, service_role;

-- ============================================================
-- (2) fetch_fee_master — 品目+版履歴+プラン一式(1画面分を一括返却)。
--     current_* = 本日時点で適用中の版(未来版は versions 内で is_future=true)。
-- ============================================================
create or replace function fetch_fee_master(p_office_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_result jsonb;
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  if not is_billing_enabled_for_office(p_office_id) then raise exception 'feature disabled'; end if;

  select jsonb_build_object(
    'can_edit', is_executive_director_or_admin(),
    'items', coalesce((
      select jsonb_agg(item order by
        array_position(array['monthly_base','monthly_extension','extension','closing_overrun',
          'meal_main','meal_side','temp_care','temp_care_meal','temp_care_snack',
          'diaper','supply','event','misc','adjustment_plus','adjustment_minus'], item->>'category'),
        (item->>'sort_order')::int, item->>'name')
      from (
        select jsonb_build_object(
          'id', f.id, 'category', f.category, 'name', f.name, 'calc_unit', f.calc_unit,
          'display_note', f.display_note, 'sort_order', f.sort_order, 'is_active', f.is_active,
          'current_amount', cur.amount, 'current_version', cur.version,
          'current_effective_from', cur.effective_from, 'current_effective_to', cur.effective_to,
          'versions', coalesce((
            select jsonb_agg(jsonb_build_object(
              'id', v.id, 'version', v.version, 'amount', v.amount,
              'effective_from', v.effective_from, 'effective_to', v.effective_to,
              'approved_by_name', e.name, 'approved_at', v.approved_at,
              'source_note', v.source_note,
              'is_future', v.effective_from > current_date
            ) order by v.version desc)
            from fee_rate_versions v
            left join employees e on e.id = v.approved_by
            where v.fee_item_id = f.id
          ), '[]'::jsonb)
        ) as item
        from fee_items f
        left join lateral (
          select v.amount, v.version, v.effective_from, v.effective_to
          from fee_rate_versions v
          where v.fee_item_id = f.id
            and v.effective_from <= current_date
            and (v.effective_to is null or v.effective_to >= current_date)
          limit 1
        ) cur on true
        where f.office_id = p_office_id
      ) items
    ), '[]'::jsonb),
    'plans', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'name', p.name, 'cert_type', p.cert_type, 'age_band', p.age_band,
        'usage_start', p.usage_start, 'usage_end', p.usage_end,
        'saturday_usage_end', p.saturday_usage_end,
        'monthly_fee_item', mf.name, 'monthly_amount', mfr.amount,
        'overtime_fee_item', ot.name, 'overtime_amount', otr.amount,
        'overtime_calc_unit', ot.calc_unit,
        'effective_from', p.effective_from, 'effective_to', p.effective_to,
        'is_active', p.is_active
      ) order by p.age_band nulls first, p.usage_end, p.name)
      from contract_plans p
      left join fee_items mf on mf.id = p.monthly_fee_item_id
      left join lateral (
        select v.amount from fee_rate_versions v
        where v.fee_item_id = mf.id and v.effective_from <= current_date
          and (v.effective_to is null or v.effective_to >= current_date) limit 1
      ) mfr on true
      left join fee_items ot on ot.id = p.overtime_fee_item_id
      left join lateral (
        select v.amount from fee_rate_versions v
        where v.fee_item_id = ot.id and v.effective_from <= current_date
          and (v.effective_to is null or v.effective_to >= current_date) limit 1
      ) otr on true
      where p.office_id = p_office_id
    ), '[]'::jsonb),
    'monthly_extension_plans', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'name', m.name, 'coverage_end', m.coverage_end,
        'fee_item', f.name, 'amount', fr.amount,
        'effective_from', m.effective_from, 'effective_to', m.effective_to, 'is_active', m.is_active
      ) order by m.coverage_end)
      from monthly_extension_plans m
      join fee_items f on f.id = m.fee_item_id
      left join lateral (
        select v.amount from fee_rate_versions v
        where v.fee_item_id = f.id and v.effective_from <= current_date
          and (v.effective_to is null or v.effective_to >= current_date) limit 1
      ) fr on true
      where m.office_id = p_office_id
    ), '[]'::jsonb),
    'closing_overrun_rules', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'fee_item', f.name, 'calc_unit', f.calc_unit, 'amount', fr.amount,
        'enabled_from_fiscal_year', r.enabled_from_fiscal_year, 'is_active', r.is_active
      ))
      from closing_overrun_rules r
      join fee_items f on f.id = r.fee_item_id
      left join lateral (
        select v.amount from fee_rate_versions v
        where v.fee_item_id = f.id and v.effective_from <= current_date
          and (v.effective_to is null or v.effective_to >= current_date) limit 1
      ) fr on true
      where r.office_id = p_office_id
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;
grant execute on function fetch_fee_master(uuid) to authenticated, service_role;

-- ============================================================
-- (3) upsert_fee_item — 品目の追加/変更。統括園長以上のみ。
--     変更できるのは name / display_note / sort_order / is_active のみ。
--     category・calc_unit は作成時固定(請求明細の意味が変わるため。誤登録は非表示化→再作成)。
-- ============================================================
create or replace function upsert_fee_item(
  p_office_id uuid,
  p_id uuid,               -- null = 新規作成
  p_category text,
  p_name text,
  p_calc_unit text,
  p_display_note text default null,
  p_sort_order int default 0,
  p_is_active boolean default true
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  if not is_executive_director_or_admin() then raise exception 'not authorized'; end if;
  if not is_billing_enabled_for_office(p_office_id) then raise exception 'feature disabled'; end if;
  if p_name is null or btrim(p_name) = '' then raise exception '品目名を入力してください'; end if;

  if p_id is null then
    insert into fee_items (office_id, category, name, calc_unit, display_note, sort_order, is_active)
    values (p_office_id, p_category, btrim(p_name), p_calc_unit, p_display_note, p_sort_order, p_is_active)
    returning id into v_id;
  else
    update fee_items
       set name = btrim(p_name),
           display_note = p_display_note,
           sort_order = p_sort_order,
           is_active = p_is_active
     where id = p_id and office_id = p_office_id
    returning id into v_id;
    if v_id is null then raise exception 'not found'; end if;
  end if;
  return v_id;
end;
$$;
grant execute on function upsert_fee_item(uuid, uuid, text, text, text, text, int, boolean)
  to authenticated, service_role;

-- ============================================================
-- (4) add_fee_rate_version — 単価の新版追加+旧版autoクローズ。統括園長以上のみ。
--     旧版の effective_to = 新版開始日の前日(期間規約=386冒頭)。開始日の逆行・重複はエラー。
--     過去日の適用開始日は意図的に許容(4/1改定の遅延入力等。発行済み請求はPhase7で
--     請求書側に金額スナップショットを持つため遡及入力の影響を受けない)。
-- ============================================================
create or replace function add_fee_rate_version(
  p_fee_item_id uuid,
  p_amount int,
  p_effective_from date,
  p_source_note text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_office uuid;
  v_last record;
  v_id uuid;
begin
  if not is_executive_director_or_admin() then raise exception 'not authorized'; end if;
  select office_id into v_office from fee_items where id = p_fee_item_id;
  if v_office is null then raise exception 'not found'; end if;
  if not is_billing_enabled_for_office(v_office) then raise exception 'feature disabled'; end if;
  if p_amount is null or p_amount < 0 then raise exception '金額は0円以上で入力してください'; end if;
  if p_effective_from is null then raise exception '適用開始日を入力してください'; end if;

  -- 同一品目の版を直列化(同時改訂の競合防止)
  perform 1 from fee_items where id = p_fee_item_id for update;

  select * into v_last
  from fee_rate_versions
  where fee_item_id = p_fee_item_id
  order by version desc
  limit 1;

  if v_last.id is not null then
    if v_last.effective_from >= p_effective_from then
      raise exception '適用開始日は現行版の開始日(%)より後にしてください', v_last.effective_from;
    end if;
    if v_last.effective_to is null or v_last.effective_to >= p_effective_from then
      update fee_rate_versions
         set effective_to = p_effective_from - 1
       where id = v_last.id;
    end if;
  end if;

  insert into fee_rate_versions
    (fee_item_id, amount, version, effective_from, approved_by, approved_at, source_note)
  values
    (p_fee_item_id, p_amount, coalesce(v_last.version, 0) + 1, p_effective_from,
     my_employee_id(), now(), p_source_note)
  returning id into v_id;
  return v_id;
end;
$$;
grant execute on function add_fee_rate_version(uuid, int, date, text) to authenticated, service_role;

-- ============================================================
-- (5) cancel_future_rate_version — 未来日付の最新版のみ取消(入力ミス救済)。統括園長以上のみ。
--     旧版のクローズを解除(effective_to を元の null に戻す)。適用中・過去の版は取消不可。
-- ============================================================
create or replace function cancel_future_rate_version(p_version_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_target record;
  v_office uuid;
  v_max int;
begin
  if not is_executive_director_or_admin() then raise exception 'not authorized'; end if;
  select * into v_target from fee_rate_versions where id = p_version_id;
  if v_target.id is null then raise exception 'not found'; end if;
  select office_id into v_office from fee_items where id = v_target.fee_item_id;
  if not is_billing_enabled_for_office(v_office) then raise exception 'feature disabled'; end if;

  perform 1 from fee_items where id = v_target.fee_item_id for update;

  select max(version) into v_max from fee_rate_versions where fee_item_id = v_target.fee_item_id;
  if v_target.version <> v_max then
    raise exception '最新版のみ取消できます';
  end if;
  if v_target.effective_from <= current_date then
    raise exception '適用開始済みの版は取消できません(改訂で対応してください)';
  end if;

  delete from fee_rate_versions where id = p_version_id;

  -- 直前版のautoクローズを解除(取消した版の前日で閉じられていた場合のみ)
  update fee_rate_versions
     set effective_to = null
   where fee_item_id = v_target.fee_item_id
     and effective_to = v_target.effective_from - 1;
end;
$$;
grant execute on function cancel_future_rate_version(uuid) to authenticated, service_role;

-- 防御多層(007/367/368と同慣行): 既定のPUBLIC EXECUTEを剥奪(anonは実行不可に。
-- 実行できても my_employee_id()=null で全チェックfail-closedだが、慣例に合わせ明示)。
revoke execute on function fetch_billing_offices() from public, anon;
revoke execute on function fetch_fee_master(uuid) from public, anon;
revoke execute on function upsert_fee_item(uuid, uuid, text, text, text, text, int, boolean) from public, anon;
revoke execute on function add_fee_rate_version(uuid, int, date, text) from public, anon;
revoke execute on function cancel_future_rate_version(uuid) from public, anon;
