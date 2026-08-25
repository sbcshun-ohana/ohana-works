-- 339: BABY MAHALO(M)/Mahalo Station(S)/Halelea(H) の食数行区分マスタ seed(給食管理 §4.1・俊承認 option1)。
--   現エンジンは「1行=1クラス(class_id)」方式のため、各施設の在籍クラスを1行ずつ登録する(大和と同方式)。
--   0歳クラスは給食段階(後期/完了期)に分割。1・2歳クラスは1行。加えて一時保育(手動加算)と職員行を用意。
--   ※ 年齢帯まとめ表示(0歳/1・2歳)は将来のエンジン拡張で対応(本seedはクラス別)。
--   クラス構成に依存しないよう在籍クラスを反復。冪等(office_id×row_key で重複回避)。M/S/H にクラス未登録の
--   場合は児童行は作られない(一時保育・職員行のみ)。オンボード後に再実行すればクラス行が追加される。
do $$
declare
  o record; c record; v_age int; v_sort int;
begin
  for o in select id, office_code from offices where office_code in ('M', 'S', 'H') loop
    v_sort := 0;

    -- 児童行(クラス別・0歳は後期/完了期に分割)。0〜2歳施設のため朝おやつ対象。
    for c in
      select id, class_name, age_group from childcare_classes
      where office_id = o.id and is_active
      order by coalesce(substring(age_group from '(\d)歳')::int, 9), class_name
    loop
      v_age := coalesce(substring(c.age_group from '(\d)歳')::int, 9);
      v_sort := v_sort + 10;
      if v_age = 0 then
        insert into meal_row_definitions
          (office_id, row_key, row_label, class_id, meal_stage, row_type, am_snack, lunch, pm_snack, sort_order)
        values (o.id, 'cls_' || c.id || '_late', c.class_name || '(後期)', c.id, 'late', 'children', true, true, true, v_sort)
        on conflict (office_id, row_key) do nothing;
        insert into meal_row_definitions
          (office_id, row_key, row_label, class_id, meal_stage, row_type, am_snack, lunch, pm_snack, sort_order)
        values (o.id, 'cls_' || c.id || '_complete', c.class_name || '(完了期)', c.id, 'complete', 'children', true, true, true, v_sort + 1)
        on conflict (office_id, row_key) do nothing;
      else
        insert into meal_row_definitions
          (office_id, row_key, row_label, class_id, meal_stage, row_type, am_snack, lunch, pm_snack, sort_order)
        values (o.id, 'cls_' || c.id, c.class_name, c.id, null, 'children', v_age <= 2, true, true, v_sort)
        on conflict (office_id, row_key) do nothing;
      end if;
    end loop;

    -- 一時保育(手動加算欄)。0〜2歳は朝おやつも対象、3〜5歳は昼食・午後おやつ。
    insert into meal_row_definitions
      (office_id, row_key, row_label, class_id, meal_stage, row_type, am_snack, lunch, pm_snack, sort_order)
    values (o.id, 'temp_0_2', '一時保育(0〜2歳)', null, null, 'temp_care', true, true, true, 900)
    on conflict (office_id, row_key) do nothing;
    insert into meal_row_definitions
      (office_id, row_key, row_label, class_id, meal_stage, row_type, am_snack, lunch, pm_snack, sort_order)
    values (o.id, 'temp_3_5', '一時保育(3〜5歳)', null, null, 'temp_care', false, true, true, 910)
    on conflict (office_id, row_key) do nothing;

    -- 職員行(昼食)。
    insert into meal_row_definitions
      (office_id, row_key, row_label, class_id, meal_stage, row_type, am_snack, lunch, pm_snack, sort_order)
    values (o.id, 'office_staff', '職員', null, null, 'staff', false, true, false, 990)
    on conflict (office_id, row_key) do nothing;
  end loop;
end $$;
