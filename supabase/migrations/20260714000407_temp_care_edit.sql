-- 407: 一時預かり児の登録内容の修正・登録取消(俊要望 2026-08-31)。
--   氏名・ふりがな・生年月日・性別を修正可能。生年月日を変えると保育年齢を再算出し、
--   連絡帳/午睡の児override(0-2歳=あり/3-5歳=なし)を自動で更新する。
--   登録取消=誤登録の除去。安全のため soft(退園済み+クラス在籍クローズ)。当日精算のみで
--   請求書は無いが、記録が残っている場合も含め一貫して soft 化(復活・監査可能)。

-- (1) 修正
create or replace function update_temp_care_child(
  p_child_id uuid,
  p_full_name text,
  p_birth_date date,
  p_gender text default null,
  p_name_kana text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_office uuid;
  v_kind text;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
  v_age int;
  v_needs_full boolean;
begin
  select office_id, child_kind into v_office, v_kind from children where id = p_child_id;
  if v_office is null then raise exception 'not found'; end if;
  if v_kind <> 'temporary' then raise exception '一時預かり児のみ修正できます'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  if p_full_name is null or btrim(p_full_name) = '' then raise exception '氏名を入力してください'; end if;
  if p_birth_date is null then raise exception '生年月日を入力してください'; end if;
  if p_birth_date > v_today then raise exception '生年月日が未来日です'; end if;
  if p_gender is not null and p_gender not in ('男','女','その他') then
    raise exception '性別が不正です';
  end if;

  v_age := nursery_age_for_date(p_birth_date, v_today);
  v_needs_full := (v_age <= 2);

  update children set
    full_name = btrim(p_full_name),
    display_name = btrim(p_full_name),
    name_kana = nullif(btrim(coalesce(p_name_kana,'')), ''),
    gender = p_gender,
    birth_date = p_birth_date,
    family_daily_report_required_override = v_needs_full,  -- 年齢変更に応じて連絡帳/午睡を再判定
    nap_check_required_override = v_needs_full
  where id = p_child_id;
end;
$$;
grant execute on function update_temp_care_child(uuid, text, date, text, text) to authenticated, service_role;
revoke execute on function update_temp_care_child(uuid, text, date, text, text) from public, anon;

-- (2) 登録取消(soft: 退園済み+クラス在籍クローズ)。誤登録の除去に使う。
create or replace function remove_temp_care_child(p_child_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_office uuid;
  v_kind text;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  select office_id, child_kind into v_office, v_kind from children where id = p_child_id;
  if v_office is null then raise exception 'not found'; end if;
  if v_kind <> 'temporary' then raise exception '一時預かり児のみ取消できます'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;

  update child_class_enrollments set effective_end_date = v_today
  where child_id = p_child_id and effective_end_date is null;
  update children set enrollment_status = '退園済み', withdrawal_date = v_today
  where id = p_child_id;
end;
$$;
grant execute on function remove_temp_care_child(uuid) to authenticated, service_role;
revoke execute on function remove_temp_care_child(uuid) from public, anon;
