-- 199: 健康チェック拡張 — ミルク量・食事(午前おやつ/昼食/午後おやつ)の記録(俊確定 2026-08-13)。
--
-- 背景: 健康チェックページを6タブ化(検温/排便/ミルク/午前おやつ/昼食/午後おやつ)。
--   ミルク=生後18ヶ月未満の園児の飲んだ量(ml)を複数回記録。
--   食事=0・1・2歳児のスロット別(午前おやつ/昼食/午後おやつ)の食べた分量を記録。
--   ※タブ表示の年齢絞り込みはUI側(birth_date基準)。DBは全園児に記録可能(将来の運用変更に耐える)。
--
-- 二重管理回避(194と同方針): データは連絡帳 child_daily_contacts の列として持ち、
--   連絡帳と同一実体を読み書きする。
--   - milk_records jsonb 配列: [{time:"HH:MM", amount_ml:120}, ...](時刻順はクライアント表示側で整列)
--   - meal_records  jsonb オブジェクト: {"am_snack":"完食","lunch":"半分","pm_snack":"食べず"}
--     スロット= am_snack/lunch/pm_snack。分量文言は UI 側の選択肢で管理(DB非強制。194のtype同方針)。
--
-- 認可(194 add/delete_toileting_record と同一):
--   当日=施設職員(has_childcare_office_access) / 過去日=主任以上(manages_childcare)。
--   連絡帳が draft/rejected 以外(公開・申請済み)の改変は主任以上のみ。
--
-- 取得: fetch_health_check_for_office(施設×日で全園児分の排便/ミルク/食事+birth_dateを一括返却)。
--   健康チェックページの per-child N+1(現状の排便 fetch_toileting_records 並列呼び)も解消する。
--   birth_date を返すのはタブの年齢絞り込み(18ヶ月未満/0-2歳)のため。
--
-- 冪等: 列追加は if not exists、関数は create or replace(いずれも新規名・戻り型変更なし)。

-- (1) 連絡帳への列追加
alter table child_daily_contacts add column if not exists milk_records jsonb;
alter table child_daily_contacts add column if not exists meal_records jsonb;

comment on column child_daily_contacts.milk_records is
  'ミルク記録(199): [{time:"HH:MM", amount_ml:int}] 健康チェック/連絡帳共用。18ヶ月未満の絞り込みはUI側';
comment on column child_daily_contacts.meal_records is
  '食事記録(199): {"am_snack":分量,"lunch":分量,"pm_snack":分量} 分量文言はUI選択肢で管理(DB非強制)';

-- (2) ミルク追加: ensure_child_daily_contact で当日行を用意し milk_records 末尾へ1件追記。
create or replace function add_milk_record(
  p_child_id uuid, p_business_date date, p_time time, p_amount_ml int)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_office uuid;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
  v_contact_id uuid;
  v_status text;
begin
  if p_amount_ml is null or p_amount_ml <= 0 or p_amount_ml > 500 then
    raise exception 'amount_ml must be between 1 and 500';
  end if;
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  if p_business_date <> v_today and not manages_childcare(v_office) then
    raise exception 'not authorized to edit for non-current date';
  end if;

  v_contact_id := ensure_child_daily_contact(p_child_id, p_business_date);
  select status into v_status from child_daily_contacts where id = v_contact_id;
  if v_status not in ('draft', 'rejected') and not manages_childcare(v_office) then
    raise exception 'contact is % and cannot be edited', v_status;
  end if;

  update child_daily_contacts
  set milk_records = coalesce(milk_records, '[]'::jsonb)
        || jsonb_build_object('time', to_char(p_time, 'HH24:MI'), 'amount_ml', p_amount_ml)
  where id = v_contact_id;
end; $$;

-- (3) ミルク削除: index 指定で1件除去(取り消し用)。
create or replace function delete_milk_record(
  p_child_id uuid, p_business_date date, p_index int)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_office uuid;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
  v_contact_id uuid;
  v_status text;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  if p_business_date <> v_today and not manages_childcare(v_office) then
    raise exception 'not authorized to edit for non-current date';
  end if;

  select id, status into v_contact_id, v_status from child_daily_contacts
  where child_id = p_child_id and business_date = p_business_date;
  if v_contact_id is null then return; end if;
  if v_status not in ('draft', 'rejected') and not manages_childcare(v_office) then
    raise exception 'contact is % and cannot be edited', v_status;
  end if;

  update child_daily_contacts
  set milk_records = coalesce(milk_records, '[]'::jsonb) - p_index
  where id = v_contact_id;
end; $$;

-- (4) 食事の分量設定: スロット(am_snack/lunch/pm_snack)ごとに上書き。p_amount=NULLでそのスロットを未記録に戻す。
create or replace function set_meal_record(
  p_child_id uuid, p_business_date date, p_slot text, p_amount text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_office uuid;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
  v_contact_id uuid;
  v_status text;
begin
  if p_slot not in ('am_snack', 'lunch', 'pm_snack') then
    raise exception 'invalid slot: %', p_slot;
  end if;
  if p_amount is not null and btrim(p_amount) = '' then
    raise exception 'amount must be null or non-empty';
  end if;
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  if p_business_date <> v_today and not manages_childcare(v_office) then
    raise exception 'not authorized to edit for non-current date';
  end if;

  v_contact_id := ensure_child_daily_contact(p_child_id, p_business_date);
  select status into v_status from child_daily_contacts where id = v_contact_id;
  if v_status not in ('draft', 'rejected') and not manages_childcare(v_office) then
    raise exception 'contact is % and cannot be edited', v_status;
  end if;

  if p_amount is null then
    update child_daily_contacts
    set meal_records = coalesce(meal_records, '{}'::jsonb) - p_slot
    where id = v_contact_id;
  else
    update child_daily_contacts
    set meal_records = coalesce(meal_records, '{}'::jsonb) || jsonb_build_object(p_slot, p_amount)
    where id = v_contact_id;
  end if;
end; $$;

-- (5) 一括取得: 施設×日の全在籍園児について 排便/ミルク/食事 と birth_date を返す。
--   健康チェックページの一覧表示用(排便のper-child並列取得のN+1も本RPCへ置換して解消)。
create or replace function fetch_health_check_for_office(p_office_id uuid, p_business_date date)
returns table (
  child_id uuid,
  birth_date date,
  toileting_records jsonb,
  milk_records jsonb,
  meal_records jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not has_childcare_office_access(p_office_id) then
    raise exception 'not authorized';
  end if;

  return query
  select
    c.id,
    c.birth_date,
    coalesce(cdc.toileting_records, '[]'::jsonb),
    coalesce(cdc.milk_records, '[]'::jsonb),
    coalesce(cdc.meal_records, '{}'::jsonb)
  from children c
  left join child_daily_contacts cdc
    on cdc.child_id = c.id and cdc.business_date = p_business_date
  where c.office_id = p_office_id and c.enrollment_status <> '退園済み';
end;
$$;

-- 実行権限(198と同一の実効権限を明示付与)。
grant execute on function add_milk_record(uuid, date, time, int) to anon, authenticated, service_role;
grant execute on function delete_milk_record(uuid, date, int) to anon, authenticated, service_role;
grant execute on function set_meal_record(uuid, date, text, text) to anon, authenticated, service_role;
grant execute on function fetch_health_check_for_office(uuid, date) to anon, authenticated, service_role;
