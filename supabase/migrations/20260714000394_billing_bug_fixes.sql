-- 394: 本日分バグレビュー(2026-08-28・Fable 2系統横断)の修正。
--   S1: 手動設定した契約終了月が「予約追加→予約取消」で消滅する
--       → 終了月付き契約への予約追加を日本語エラーで拒否(先に終了月を解除する運用)。
--       add_child_contract / add_child_extension_contract を390からガード追加で再定義。
--   S2: child_weekly_schedule の直接書き込みRLS(184)が393の履歴規約・AC-04をバイパス可能
--       → 書き込みポリシー削除(全書き込みは元々RPC経由・消費者グレップ済みで副作用なし)。
--   軽微1: 388の日付判定がUTC(current_date)でJST 0:00-9:00に現行版/取消可否がズレる
--       → fetch_fee_master / cancel_future_rate_version をJST日付に統一(390と同規約)。
--   軽微2: 386のフラグ判定関数に public/anon revoke が無い(慣行不整合)→ 追加。

-- ============================================================
-- (S2) 週次予定の直接書き込みポリシー削除(閲覧ポリシーは維持)
-- ============================================================
drop policy if exists child_weekly_schedule_write_scoped on child_weekly_schedule;

-- ============================================================
-- (軽微2) 386フラグ関数のrevoke(anonはフラグ値のプローブのみだが慣行に合わせ遮断)
-- ============================================================
revoke execute on function is_billing_enabled_for_office(uuid) from public, anon;
revoke execute on function is_billing_payment_enabled_for_office(uuid) from public, anon;

-- ============================================================
-- (S1-1) add_child_contract — 終了月付き現行契約への予約追加を拒否
-- ============================================================
create or replace function add_child_contract(
  p_child_id uuid,
  p_contract_plan_id uuid,
  p_start_month date,
  p_note text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_office uuid;
  v_plan record;
  v_status text;
  v_open record;
  v_id uuid;
begin
  v_office := assert_billing_child_access(p_child_id);
  select enrollment_status into v_status from children where id = p_child_id;
  if v_status = '退園済み' then raise exception '退園済みの園児には契約を追加できません'; end if;
  select * into v_plan from contract_plans where id = p_contract_plan_id;
  if v_plan.id is null then raise exception 'not found'; end if;
  if v_plan.office_id <> v_office then raise exception 'プランが園児の施設と一致しません'; end if;
  if not v_plan.is_active then raise exception 'このプランは無効化されています'; end if;
  if p_start_month is null or extract(day from p_start_month) <> 1 then
    raise exception '開始月は月初日で指定してください';
  end if;
  if p_start_month < v_plan.effective_from
     or (v_plan.effective_to is not null and p_start_month > v_plan.effective_to) then
    raise exception 'プランの適用期間(%〜%)外の開始月です', v_plan.effective_from, coalesce(v_plan.effective_to::text, '');
  end if;

  perform 1 from children where id = p_child_id for update;

  if exists (select 1 from child_contracts
             where child_id = p_child_id and start_month >= p_start_month) then
    raise exception '開始月以降に既存の契約があります(先に予約を取り消してください)';
  end if;

  select * into v_open from child_contracts
  where child_id = p_child_id and start_month < p_start_month
    and (end_month is null or end_month >= p_start_month)
  order by start_month desc limit 1;
  -- 394修正(S1): 手動設定の終了月をautoクローズで上書きすると、予約取消時の再オープンで
  -- 終了月が失われ無期限契約に戻る(退園予定の消滅)。終了月付き契約への追加は拒否する。
  if v_open.id is not null and v_open.end_month is not null then
    raise exception '現行契約に終了月(%)が設定されています。先に終了月を解除してから契約を追加してください',
      to_char(v_open.end_month, 'YYYY-MM');
  end if;
  if v_open.id is not null then
    update child_contracts
       set end_month = (p_start_month - interval '1 month')::date
     where id = v_open.id;
  end if;

  insert into child_contracts (child_id, contract_plan_id, start_month, note, created_by)
  values (p_child_id, p_contract_plan_id, p_start_month, p_note, my_employee_id())
  returning id into v_id;
  if v_open.id is not null then
    update child_contracts set superseded_by = v_id where id = v_open.id;
  end if;
  return v_id;
end;
$$;

-- ============================================================
-- (S1-2) add_child_extension_contract — 同一ガード
-- ============================================================
create or replace function add_child_extension_contract(
  p_child_id uuid,
  p_monthly_extension_plan_id uuid,
  p_start_month date,
  p_note text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_office uuid;
  v_plan record;
  v_status text;
  v_open record;
  v_id uuid;
begin
  v_office := assert_billing_child_access(p_child_id);
  select enrollment_status into v_status from children where id = p_child_id;
  if v_status = '退園済み' then raise exception '退園済みの園児には月極延長を追加できません'; end if;
  select * into v_plan from monthly_extension_plans where id = p_monthly_extension_plan_id;
  if v_plan.id is null then raise exception 'not found'; end if;
  if v_plan.office_id <> v_office then raise exception 'プランが園児の施設と一致しません'; end if;
  if not v_plan.is_active then raise exception 'このプランは無効化されています'; end if;
  if p_start_month is null or extract(day from p_start_month) <> 1 then
    raise exception '開始月は月初日で指定してください';
  end if;
  if p_start_month < v_plan.effective_from
     or (v_plan.effective_to is not null and p_start_month > v_plan.effective_to) then
    raise exception 'プランの適用期間(%〜%)外の開始月です', v_plan.effective_from, coalesce(v_plan.effective_to::text, '');
  end if;

  perform 1 from children where id = p_child_id for update;
  if exists (select 1 from child_extension_contracts
             where child_id = p_child_id and start_month >= p_start_month) then
    raise exception '開始月以降に既存の月極延長があります(先に予約を取り消してください)';
  end if;
  select * into v_open from child_extension_contracts
  where child_id = p_child_id and start_month < p_start_month
    and (end_month is null or end_month >= p_start_month)
  order by start_month desc limit 1;
  -- 394修正(S1): 契約側と同旨
  if v_open.id is not null and v_open.end_month is not null then
    raise exception '現行の月極延長に終了月(%)が設定されています。先に終了月を解除してから追加してください',
      to_char(v_open.end_month, 'YYYY-MM');
  end if;
  if v_open.id is not null then
    update child_extension_contracts
       set end_month = (p_start_month - interval '1 month')::date
     where id = v_open.id;
  end if;

  insert into child_extension_contracts (child_id, monthly_extension_plan_id, start_month, note, created_by)
  values (p_child_id, p_monthly_extension_plan_id, p_start_month, p_note, my_employee_id())
  returning id into v_id;
  if v_open.id is not null then
    update child_extension_contracts set superseded_by = v_id where id = v_open.id;
  end if;
  return v_id;
end;
$$;

-- ============================================================
-- (軽微1-1) fetch_fee_master — current版判定をJST日付に統一(388から日付基準のみ変更)
-- ============================================================
create or replace function fetch_fee_master(p_office_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_result jsonb;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
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
              'is_future', v.effective_from > v_today
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
            and v.effective_from <= v_today
            and (v.effective_to is null or v.effective_to >= v_today)
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
        where v.fee_item_id = mf.id and v.effective_from <= v_today
          and (v.effective_to is null or v.effective_to >= v_today) limit 1
      ) mfr on true
      left join fee_items ot on ot.id = p.overtime_fee_item_id
      left join lateral (
        select v.amount from fee_rate_versions v
        where v.fee_item_id = ot.id and v.effective_from <= v_today
          and (v.effective_to is null or v.effective_to >= v_today) limit 1
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
        where v.fee_item_id = f.id and v.effective_from <= v_today
          and (v.effective_to is null or v.effective_to >= v_today) limit 1
      ) fr on true
      where m.office_id = p_office_id
    ), '[]'::jsonb),
    'closing_overrun_rules', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'fee_item', f.name, 'calc_unit', f.calc_unit, 'amount', fr.amount,
        'enabled_from_fiscal_year', r.enabled_from_fiscal_year, 'is_active', r.is_active
      ) order by f.name)
      from closing_overrun_rules r
      join fee_items f on f.id = r.fee_item_id
      left join lateral (
        select v.amount from fee_rate_versions v
        where v.fee_item_id = f.id and v.effective_from <= v_today
          and (v.effective_to is null or v.effective_to >= v_today) limit 1
      ) fr on true
      where r.office_id = p_office_id
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

-- ============================================================
-- (軽微1-2) cancel_future_rate_version — 未来判定をJSTに統一
-- ============================================================
create or replace function cancel_future_rate_version(p_version_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_target record;
  v_office uuid;
  v_max int;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
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
  if v_target.effective_from <= v_today then
    raise exception '適用開始済みの版は取消できません(改訂で対応してください)';
  end if;

  delete from fee_rate_versions where id = p_version_id;

  update fee_rate_versions
     set effective_to = null
   where fee_item_id = v_target.fee_item_id
     and effective_to = v_target.effective_from - 1;
end;
$$;
