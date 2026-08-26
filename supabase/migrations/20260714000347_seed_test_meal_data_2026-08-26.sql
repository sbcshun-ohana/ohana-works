-- 347: 実機テスト用の暫定データ(大和・2026-08-26)。食数(行区分別)+献立(通常/離乳食/除去食)を投入し、
--   厨房ビュー・献立・アレルギー(除去食)の表示を確認できるようにする(俊指示 2026-08-26)。
--   ※あくまでテスト用の適当な数字。冪等(再実行で上書き)。除去食対象児は既存(きゅうちゃん=卵)を使用。
do $$
declare
  v_office uuid := 'c0a7010a-fd37-4cad-971b-6b3f2e80f842';
  v_date   date := date '2026-08-26';
  v_import uuid;
  r record;
  v_child int; v_staff int;
begin
  -- ===== 食数(meal_count_rows)=====
  insert into meal_count_days (office_id, business_date, computed_at)
  values (v_office, v_date, now())
  on conflict (office_id, business_date) do update set computed_at = now();

  for r in
    select rd.row_key, rd.row_type, rd.am_snack, rd.lunch, rd.pm_snack,
      case rd.row_key
        when 'hana_late' then 3 when 'hana_complete' then 4 when 'hana_toddler' then 2
        when 'sora' then 8 when 'kaze' then 10 when 'tsuki' then 12 when 'hoshi' then 11 when 'niji' then 13
        else 5 end as cnt
    from meal_row_definitions rd
    where rd.office_id = v_office and rd.is_active
  loop
    v_child := case when r.row_type = 'children' then r.cnt else 0 end;
    v_staff := case when r.row_type = 'staff' then 6 else 0 end;
    if r.am_snack then
      insert into meal_count_rows (office_id, business_date, row_key, meal_slot, child_count, staff_count)
      values (v_office, v_date, r.row_key, 'am_snack', v_child, v_staff)
      on conflict (office_id, business_date, row_key, meal_slot) do update set child_count = excluded.child_count, staff_count = excluded.staff_count, updated_at = now();
    end if;
    if r.lunch then
      insert into meal_count_rows (office_id, business_date, row_key, meal_slot, child_count, staff_count)
      values (v_office, v_date, r.row_key, 'lunch', v_child, v_staff)
      on conflict (office_id, business_date, row_key, meal_slot) do update set child_count = excluded.child_count, staff_count = excluded.staff_count, updated_at = now();
    end if;
    if r.pm_snack then
      insert into meal_count_rows (office_id, business_date, row_key, meal_slot, child_count, staff_count)
      values (v_office, v_date, r.row_key, 'pm_snack', v_child, v_staff)
      on conflict (office_id, business_date, row_key, meal_slot) do update set child_count = excluded.child_count, staff_count = excluded.staff_count, updated_at = now();
    end if;
  end loop;

  -- ===== 献立(menu_imports + menu_days)=====
  select id into v_import from menu_imports
    where office_id = v_office and target_month = date '2026-08-01' order by version desc limit 1;
  if v_import is null then
    insert into menu_imports (office_id, target_month, format, source_path, format_kind, version, status)
    values (v_office, date '2026-08-01', 'excel', 'test/2026-08_ohana.xlsx', 'yasuda', 1, 'published')
    returning id into v_import;
  else
    update menu_imports set status = 'published' where id = v_import;
  end if;

  delete from menu_days where import_id = v_import and menu_date = v_date;
  insert into menu_days (import_id, office_id, menu_date, food_type, meal_slot, menu_text, removal_kind, removal_note) values
    (v_import, v_office, v_date, 'regular_over3',  'lunch',    'ごはん／鶏のから揚げ／ほうれん草のごま和え／すまし汁', null, null),
    (v_import, v_office, v_date, 'regular_over3',  'pm_snack', '牛乳／さつまいも蒸しパン', null, null),
    (v_import, v_office, v_date, 'regular_under3', 'am_snack', '牛乳／ビスケット', null, null),
    (v_import, v_office, v_date, 'regular_under3', 'lunch',    '軟飯／鶏そぼろあんかけ／ほうれん草和え／すまし汁', null, null),
    (v_import, v_office, v_date, 'regular_under3', 'pm_snack', '麦茶／おにぎり', null, null),
    (v_import, v_office, v_date, 'weaning_late',   'lunch',    '全がゆ／鶏ささみと野菜のとろとろ煮', null, null),
    (v_import, v_office, v_date, 'weaning_final',  'lunch',    '軟飯／白身魚と野菜の煮物', null, null),
    (v_import, v_office, v_date, 'allergy_removed','lunch',    'ごはん／鶏のから揚げ(卵不使用)／ほうれん草のごま和え／すまし汁', '卵', 'から揚げの衣を卵不使用に変更／ごま和えのマヨを除きノンエッグドレッシングで提供');
end $$;
