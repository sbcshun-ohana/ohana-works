-- 390: 請求決済 Phase3(その2) — 園児契約RPC(園児マスター「契約」モーダル用)。
--   権限写像(2026-08-28確定): 契約・月極延長の閲覧/日常操作=主任以上 manages_childcare
--   / 免除(請求0円化+機微書類・閲覧含む)・年齢スナップショット生成=統括園長以上。
--   ※免除は非課税世帯を示唆する機微情報のため「閲覧も統括のみ」(Fableレビュー中2反映)。
--   月の表現・重複防止・「閉じて作る」規約は389冒頭コメントのとおり。
--   月境界の判定は日本時間( (now() at time zone 'Asia/Tokyo')::date )で行う(請求の月跨ぎ事故防止)。

-- 内部ヘルパー: 園児の施設を返しつつ 主任以上+請求フラグON を検証(定義者関数からのみ呼ぶ)
create or replace function assert_billing_child_access(p_child_id uuid)
returns uuid
language plpgsql stable security definer set search_path = public as $$
declare
  v_office uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  if not is_billing_enabled_for_office(v_office) then raise exception 'feature disabled'; end if;
  return v_office;
end;
$$;
-- 補助関数は直接呼ばせない(definer間呼び出しは所有者権限で成立するためgrant不要)。
revoke execute on function assert_billing_child_access(uuid) from public, anon, authenticated;

-- 内部ヘルパー: 日本時間の今月(月初日)
create or replace function jst_current_month()
returns date
language sql stable as $$
  select date_trunc('month', (now() at time zone 'Asia/Tokyo')::date)::date;
$$;
revoke execute on function jst_current_month() from public, anon, authenticated;

-- ============================================================
-- (1) fetch_child_billing_contracts — モーダル1画面分を一括返却
-- ============================================================
create or replace function fetch_child_billing_contracts(p_child_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_office uuid;
  v_is_exec boolean;
begin
  v_office := assert_billing_child_access(p_child_id);
  v_is_exec := is_executive_director_or_admin();

  return jsonb_build_object(
    'can_edit_exemptions', v_is_exec,
    'contracts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id, 'contract_plan_id', c.contract_plan_id, 'plan_name', p.name,
        'cert_type', p.cert_type, 'age_band', p.age_band,
        'usage_start', p.usage_start, 'usage_end', p.usage_end,
        'start_month', c.start_month, 'end_month', c.end_month, 'note', c.note,
        'created_by_name', e.name,
        'is_future', c.start_month > jst_current_month()
      ) order by c.start_month desc)
      from child_contracts c
      join contract_plans p on p.id = c.contract_plan_id
      left join employees e on e.id = c.created_by
      where c.child_id = p_child_id
    ), '[]'::jsonb),
    'extension_contracts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id, 'monthly_extension_plan_id', c.monthly_extension_plan_id,
        'plan_name', m.name, 'coverage_end', m.coverage_end,
        'start_month', c.start_month, 'end_month', c.end_month, 'note', c.note,
        'is_future', c.start_month > jst_current_month()
      ) order by c.start_month desc)
      from child_extension_contracts c
      join monthly_extension_plans m on m.id = c.monthly_extension_plan_id
      where c.child_id = p_child_id
    ), '[]'::jsonb),
    -- 免除は機微情報(非課税世帯の示唆)のため統括のみ返す
    'exemptions', case when v_is_exec then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.id, 'kind', x.kind,
        'start_month', x.start_month, 'end_month', x.end_month,
        'document_state', x.document_state,
        'document_fiscal_year', x.document_fiscal_year,
        'has_document', x.document_path is not null,
        'document_path', x.document_path,
        'document_confirmed_by_name', ce.name, 'document_confirmed_at', x.document_confirmed_at,
        'note', x.note
      ) order by x.start_month desc, x.kind)
      from child_exemptions x
      left join employees ce on ce.id = x.document_confirmed_by
      where x.child_id = p_child_id
    ), '[]'::jsonb) else '[]'::jsonb end,
    'age_band_snapshots', coalesce((
      select jsonb_agg(jsonb_build_object(
        'fiscal_year', s.fiscal_year, 'age_band', s.age_band,
        'basis_class_name', cl.class_name, 'determined_at', s.determined_at
      ) order by s.fiscal_year desc)
      from child_age_band_snapshots s
      left join childcare_classes cl on cl.id = s.basis_class_id
      where s.child_id = p_child_id
    ), '[]'::jsonb),
    -- 割当候補: 有効かつ「今月以降も適用がある」プランのみ(失効版を出さない)
    'available_plans', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'name', p.name, 'cert_type', p.cert_type, 'age_band', p.age_band,
        'usage_start', p.usage_start, 'usage_end', p.usage_end
      ) order by p.age_band nulls first, p.usage_end, p.name)
      from contract_plans p
      where p.office_id = v_office and p.is_active
        and (p.effective_to is null or p.effective_to >= jst_current_month())
    ), '[]'::jsonb),
    'available_extension_plans', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'name', m.name, 'coverage_end', m.coverage_end
      ) order by m.coverage_end)
      from monthly_extension_plans m
      where m.office_id = v_office and m.is_active
        and (m.effective_to is null or m.effective_to >= jst_current_month())
    ), '[]'::jsonb)
  );
end;
$$;
grant execute on function fetch_child_billing_contracts(uuid) to authenticated, service_role;

-- ============================================================
-- (2) add_child_contract — 契約割当(現行契約は自動で前月末クローズ=閉じて作る)
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

  -- 園児単位で直列化(同時操作の競合防止)
  perform 1 from children where id = p_child_id for update;

  -- 開始月以降に既存契約があれば拒否(予約の上書きは削除→追加で行う)
  if exists (select 1 from child_contracts
             where child_id = p_child_id and start_month >= p_start_month) then
    raise exception '開始月以降に既存の契約があります(先に予約を取り消してください)';
  end if;

  -- 現行のオープン契約(または開始月をまたぐ契約)を前月でクローズ
  select * into v_open from child_contracts
  where child_id = p_child_id and start_month < p_start_month
    and (end_month is null or end_month >= p_start_month)
  order by start_month desc limit 1;
  if v_open.id is not null then
    update child_contracts
       set end_month = (p_start_month - interval '1 month')::date
     where id = v_open.id;
  end if;

  insert into child_contracts (child_id, contract_plan_id, start_month, note, created_by)
  values (p_child_id, p_contract_plan_id, p_start_month, p_note, my_employee_id())
  returning id into v_id;
  -- 自動クローズの由来を記録(予約削除時の再オープン判定に使う)
  if v_open.id is not null then
    update child_contracts set superseded_by = v_id where id = v_open.id;
  end if;
  return v_id;
end;
$$;
grant execute on function add_child_contract(uuid, uuid, date, text) to authenticated, service_role;

-- ============================================================
-- (3) set_child_contract_end — 終了月の設定/解除(後続契約との重複は日本語エラーで拒否)
-- ============================================================
create or replace function set_child_contract_end(p_contract_id uuid, p_end_month date)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_row record;
  v_next_start date;
begin
  select * into v_row from child_contracts where id = p_contract_id;
  if v_row.id is null then raise exception 'not found'; end if;
  perform assert_billing_child_access(v_row.child_id);
  if p_end_month is not null and (extract(day from p_end_month) <> 1 or p_end_month < v_row.start_month) then
    raise exception '終了月は開始月以降の月初日で指定してください';
  end if;
  select min(start_month) into v_next_start from child_contracts
  where child_id = v_row.child_id and start_month > v_row.start_month;
  if v_next_start is not null and (p_end_month is null or p_end_month >= v_next_start) then
    raise exception '後続の契約(%開始)と重複するため設定できません', v_next_start;
  end if;
  -- 手動での終了月変更=自動クローズ由来ではなくなる
  update child_contracts set end_month = p_end_month, superseded_by = null where id = p_contract_id;
end;
$$;
grant execute on function set_child_contract_end(uuid, date) to authenticated, service_role;

-- ============================================================
-- (4) delete_future_child_contract — 未来開始の契約(予約)のみ削除。
--     再オープンは superseded_by=削除対象 の行のみ(手動クローズは触らない=誤爆防止)。
--     後続契約が残る場合は再オープン先の終了月をその前月へ付け替え(空白期間を作らない)。
-- ============================================================
create or replace function delete_future_child_contract(p_contract_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_row record;
  v_next_start date;
  v_reopen uuid;
begin
  select * into v_row from child_contracts where id = p_contract_id;
  if v_row.id is null then raise exception 'not found'; end if;
  perform assert_billing_child_access(v_row.child_id);
  if v_row.start_month <= jst_current_month() then
    raise exception '開始済みの契約は削除できません(終了月の設定で対応してください)';
  end if;

  perform 1 from children where id = v_row.child_id for update;
  -- FK(superseded_by)が削除対象を参照したままだとDELETEできないため、先にリンクだけ外す
  -- (end_monthの再オープンは削除後。先に開くと削除前の行とexclusion違反になるため2段階)
  update child_contracts set superseded_by = null
   where child_id = v_row.child_id and superseded_by = p_contract_id
  returning id into v_reopen;
  delete from child_contracts where id = p_contract_id;
  if v_reopen is not null then
    select min(start_month) into v_next_start from child_contracts
    where child_id = v_row.child_id and start_month > v_row.start_month;
    update child_contracts
       set end_month = case when v_next_start is null then null
                            else (v_next_start - interval '1 month')::date end
     where id = v_reopen;
  end if;
end;
$$;
grant execute on function delete_future_child_contract(uuid) to authenticated, service_role;

-- ============================================================
-- (5)(6)(7) 月極延長の同3操作(大和のみ実データ・構造は契約と同型)
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
grant execute on function add_child_extension_contract(uuid, uuid, date, text) to authenticated, service_role;

create or replace function set_child_extension_end(p_contract_id uuid, p_end_month date)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_row record;
  v_next_start date;
begin
  select * into v_row from child_extension_contracts where id = p_contract_id;
  if v_row.id is null then raise exception 'not found'; end if;
  perform assert_billing_child_access(v_row.child_id);
  if p_end_month is not null and (extract(day from p_end_month) <> 1 or p_end_month < v_row.start_month) then
    raise exception '終了月は開始月以降の月初日で指定してください';
  end if;
  select min(start_month) into v_next_start from child_extension_contracts
  where child_id = v_row.child_id and start_month > v_row.start_month;
  if v_next_start is not null and (p_end_month is null or p_end_month >= v_next_start) then
    raise exception '後続の月極延長(%開始)と重複するため設定できません', v_next_start;
  end if;
  update child_extension_contracts set end_month = p_end_month, superseded_by = null where id = p_contract_id;
end;
$$;
grant execute on function set_child_extension_end(uuid, date) to authenticated, service_role;

create or replace function delete_future_child_extension(p_contract_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_row record;
  v_next_start date;
  v_reopen uuid;
begin
  select * into v_row from child_extension_contracts where id = p_contract_id;
  if v_row.id is null then raise exception 'not found'; end if;
  perform assert_billing_child_access(v_row.child_id);
  if v_row.start_month <= jst_current_month() then
    raise exception '開始済みの月極延長は削除できません(終了月の設定で対応してください)';
  end if;
  perform 1 from children where id = v_row.child_id for update;
  update child_extension_contracts set superseded_by = null
   where child_id = v_row.child_id and superseded_by = p_contract_id
  returning id into v_reopen;
  delete from child_extension_contracts where id = p_contract_id;
  if v_reopen is not null then
    select min(start_month) into v_next_start from child_extension_contracts
    where child_id = v_row.child_id and start_month > v_row.start_month;
    update child_extension_contracts
       set end_month = case when v_next_start is null then null
                            else (v_next_start - interval '1 month')::date end
     where id = v_reopen;
  end if;
end;
$$;
grant execute on function delete_future_child_extension(uuid) to authenticated, service_role;

-- ============================================================
-- (8) upsert_child_exemption — 免除の登録・変更(統括のみ)。
--     document_state は not_required/pending/deficient のみ受付。confirmed化は(9)経由に限定
--     (確認者・確認日時の記録漏れを防ぐ)。
-- ============================================================
create or replace function upsert_child_exemption(
  p_child_id uuid,
  p_id uuid,                                 -- null=新規
  p_kind text,
  p_start_month date,
  p_end_month date default null,
  p_document_state text default 'not_required',
  p_document_fiscal_year int default null,
  p_note text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  if not is_executive_director_or_admin() then raise exception 'not authorized'; end if;
  perform assert_billing_child_access(p_child_id);
  if p_kind is null or p_kind not in ('free_childcare','meal_main','meal_side','company_paid','custom') then
    raise exception '免除種別が不正です';
  end if;
  if p_document_state not in ('not_required','pending','deficient') then
    raise exception '書類状態が不正です(確認済みへの変更は書類の登録操作で行ってください)';
  end if;
  if p_start_month is null or extract(day from p_start_month) <> 1 then
    raise exception '開始月は月初日で指定してください';
  end if;
  if p_end_month is not null and (extract(day from p_end_month) <> 1 or p_end_month < p_start_month) then
    raise exception '終了月は開始月以降の月初日で指定してください';
  end if;

  if p_id is null then
    insert into child_exemptions
      (child_id, kind, start_month, end_month, document_state, document_fiscal_year, note, created_by)
    values
      (p_child_id, p_kind, p_start_month, p_end_month, p_document_state, p_document_fiscal_year,
       p_note, my_employee_id())
    returning id into v_id;
  else
    update child_exemptions
       set kind = p_kind, start_month = p_start_month, end_month = p_end_month,
           document_state = p_document_state, document_fiscal_year = p_document_fiscal_year,
           note = p_note
     where id = p_id and child_id = p_child_id
    returning id into v_id;
    if v_id is null then raise exception 'not found'; end if;
  end if;
  return v_id;
end;
$$;
grant execute on function upsert_child_exemption(uuid, uuid, text, date, date, text, int, text)
  to authenticated, service_role;

-- ============================================================
-- (9) set_exemption_document — 書類PDFの紐付け+確認記録(統括のみ・アップロードは
--     exemption-documents バケットへ直接(storageポリシーで統括限定済み))
-- ============================================================
create or replace function set_exemption_document(
  p_exemption_id uuid,
  p_document_path text,
  p_document_fiscal_year int,
  p_confirmed boolean default false          -- true=内容確認済み(confirmed)/false=pending
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_child uuid;
begin
  if not is_executive_director_or_admin() then raise exception 'not authorized'; end if;
  if p_document_path is null or btrim(p_document_path) = '' then
    raise exception '書類パスを指定してください';
  end if;
  select child_id into v_child from child_exemptions where id = p_exemption_id;
  if v_child is null then raise exception 'not found'; end if;
  perform assert_billing_child_access(v_child);
  update child_exemptions
     set document_path = p_document_path,
         document_fiscal_year = p_document_fiscal_year,
         document_state = case when p_confirmed then 'confirmed' else 'pending' end,
         document_confirmed_by = case when p_confirmed then my_employee_id() end,
         document_confirmed_at = case when p_confirmed then now() end
   where id = p_exemption_id;
end;
$$;
grant execute on function set_exemption_document(uuid, text, int, boolean) to authenticated, service_role;

-- ============================================================
-- (10) delete_child_exemption — 免除の削除(統括のみ。請求確定前のPhase3では単純削除)
-- ============================================================
create or replace function delete_child_exemption(p_exemption_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_child uuid;
begin
  if not is_executive_director_or_admin() then raise exception 'not authorized'; end if;
  select child_id into v_child from child_exemptions where id = p_exemption_id;
  if v_child is null then raise exception 'not found'; end if;
  perform assert_billing_child_access(v_child);
  delete from child_exemptions where id = p_exemption_id;
end;
$$;
grant execute on function delete_child_exemption(uuid) to authenticated, service_role;

-- ============================================================
-- (11) generate_age_band_snapshots — 年度の年齢区分を在籍クラスから一括確定(統括のみ・冪等)
--     0歳児クラス=age0 / 1・2歳児クラス=age1_2(それ以外のクラスは対象外)。
--     基準クラス=その年度で最初に在籍したクラス(同日開始はenrollment id順で決定的に)。
--     再実行時は上書き(請求開始前提の運用)。転園児は後から実行した施設で上書きされる点に注意。
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
    case when cl.age_group = '0歳児' then 'age0' else 'age1_2' end,
    cl.id, now()
  from child_class_enrollments cce
  join childcare_classes cl on cl.id = cce.class_id
  join children ch on ch.id = cce.child_id
  where cl.office_id = p_office_id
    and cl.school_year = p_fiscal_year
    and cl.age_group in ('0歳児', '1歳児', '2歳児')
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
grant execute on function generate_age_band_snapshots(uuid, int) to authenticated, service_role;

-- 防御多層(388と同慣行): 既定のPUBLIC EXECUTEを剥奪
revoke execute on function fetch_child_billing_contracts(uuid) from public, anon;
revoke execute on function add_child_contract(uuid, uuid, date, text) from public, anon;
revoke execute on function set_child_contract_end(uuid, date) from public, anon;
revoke execute on function delete_future_child_contract(uuid) from public, anon;
revoke execute on function add_child_extension_contract(uuid, uuid, date, text) from public, anon;
revoke execute on function set_child_extension_end(uuid, date) from public, anon;
revoke execute on function delete_future_child_extension(uuid) from public, anon;
revoke execute on function upsert_child_exemption(uuid, uuid, text, date, date, text, int, text) from public, anon;
revoke execute on function set_exemption_document(uuid, text, int, boolean) from public, anon;
revoke execute on function delete_child_exemption(uuid) from public, anon;
revoke execute on function generate_age_band_snapshots(uuid, int) from public, anon;
