-- 排便記録: 健康チェック(検温)画面から排便を記録できるようにする(俊確定 2026-08-12)。
-- 二重管理回避: データは連絡帳の child_daily_contacts.toileting_records(jsonb 配列
--   [{time:"HH:MM", type:便性状}]・087で追加済)と同一。連絡帳の排泄欄と同じ実体を読み書きする。
--   便性状 type は既存の {普通/軟便/硬便/下痢便}(admin_web TOILETING_TYPES)を想定(DB非強制)。
--
-- 検温(child_temperature_records=独立テーブル・any-staff書込)とは持ち方が異なり、toileting は
--   contacts の列で UPDATE RLS が「assignee本人 or 主任以上・draft/rejected」に限られる。健康チェック
--   画面は担任以外も使うため、188(検温)と同じ認可(当日=施設職員 / 過去日=主任以上)を持つ
--   security definer RPC で橋渡しする。公開後(submitted以降)の改変は主任以上に限定(保護者可視内容の保護)。
--
-- 冪等: create or replace のみ。DB スキーマ変更なし(toileting_records 列は既存)。

-- 追加: ensure_child_daily_contact で当日の連絡帳行を用意し、toileting_records 末尾へ1件追記。
create or replace function add_toileting_record(
  p_child_id uuid, p_business_date date, p_time time, p_type text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_office uuid;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
  v_contact_id uuid;
  v_status text;
begin
  if p_type is null or btrim(p_type) = '' then raise exception 'type required'; end if;
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  if p_business_date <> v_today and not manages_childcare(v_office) then
    raise exception 'not authorized to edit for non-current date';
  end if;

  v_contact_id := ensure_child_daily_contact(p_child_id, p_business_date);
  select status into v_status from child_daily_contacts where id = v_contact_id;
  -- 公開/申請済み内容の改変は主任以上のみ(保護者可視の連絡帳を守る)。
  if v_status not in ('draft', 'rejected') and not manages_childcare(v_office) then
    raise exception 'contact is % and cannot be edited', v_status;
  end if;

  update child_daily_contacts
  set toileting_records = coalesce(toileting_records, '[]'::jsonb)
        || jsonb_build_object('time', to_char(p_time, 'HH24:MI'), 'type', p_type)
  where id = v_contact_id;
end; $$;

-- 削除: toileting_records の index 指定で1件除去(健康チェック画面での取り消し用)。
create or replace function delete_toileting_record(
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
  set toileting_records = coalesce(toileting_records, '[]'::jsonb) - p_index
  where id = v_contact_id;
end; $$;

-- 取得: 健康チェック画面で当日の排便記録を一覧表示するための読み取り(RLS: 施設アクセス)。
create or replace function fetch_toileting_records(p_child_id uuid, p_business_date date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_office uuid; v_records jsonb;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  select coalesce(toileting_records, '[]'::jsonb) into v_records
  from child_daily_contacts where child_id = p_child_id and business_date = p_business_date;
  return coalesce(v_records, '[]'::jsonb);
end; $$;
