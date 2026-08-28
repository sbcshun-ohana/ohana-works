-- リリース当日 curation Step B〜D(2026-08-28・本番用・この順で1回実行)
-- B: S/Hクラス作成 → C: 339/354再実行(S/H給食行。pushの時点でクラスが無く0行だったため) → D: 8/26テスト食数の掃除

-- ===== Step B: S/Hクラス作成 =====
-- リリース当日 curation: Station(S)/Halelea(H) のクラス作成(§0.2bで本番未作成と判明)。
-- 実行タイミング: db push 完了後・給食フラグONまでに(§4.2の後)。本番SQLエディタで実行。
-- クラス構成は staging の実運用と同一(2026年度・0〜2歳各1クラス)。
-- age_group は本番の既存表記(M/Oと同じ「クラス名/N歳児」形式)に合わせる。
-- office は office_code で解決(UUID非依存)。unique(office_id, school_year, class_name) で冪等。
insert into childcare_classes (office_id, school_year, class_name, age_group)
select o.id, v.school_year, v.class_name, v.age_group
from (values
  ('S', 2026, 'リコ',   'リコ/0歳児'),
  ('S', 2026, 'ラウ',   'ラウ/1歳児'),
  ('S', 2026, 'プア',   'プア/2歳児'),
  ('H', 2026, 'ナル',   'ナル/0歳児'),
  ('H', 2026, 'カイ',   'カイ/1歳児'),
  ('H', 2026, 'モアナ', 'モアナ/2歳児')
) as v(office_code, school_year, class_name, age_group)
join offices o on o.office_code = v.office_code
on conflict (office_id, school_year, class_name) do nothing;


-- ===== Step C-1: 339 再実行(M/S/H 給食行seed・冪等) =====
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

-- ===== Step C-2: 354 再実行(0歳クラスに幼児食行・8/26暫定食数も再投入されるがStep Dで削除) =====
-- 354: BABY MAHALO(M)/Mahalo Station(S)/ハレレア(H) の0歳児クラスに「幼児食(toddler)」行を追加(俊指示 2026-08-26)。
--   大和はな組と同じく 後期/完了期/幼児食 の3分割に揃える(339は後期/完了期の2行のみで幼児食が抜けていた)。
--   row_key は339と同じ 'cls_<class_id>_toddler'。sort_orderは後期(late)行+2(次クラスは+10なので衝突しない)。
--   併せて 8/26 の暫定食数(表示確認用・M=4/S=6/H=5・確定で維持)も投入。冪等。
do $$
declare
  o record; c record; v_late int; v_child int;
  v_date date := date '2026-08-26';
begin
  for o in select id, office_code from offices where office_code in ('M', 'S', 'H') loop
    v_child := case when o.office_code = 'M' then 4 when o.office_code = 'S' then 6 else 5 end;
    for c in
      select cc.id, cc.class_name from childcare_classes cc
      where cc.office_id = o.id and cc.is_active
        and coalesce(substring(cc.age_group from '(\d)歳')::int, 9) = 0
    loop
      -- 0歳分割(後期行)がある施設のみ対象。
      select sort_order into v_late from meal_row_definitions
        where office_id = o.id and row_key = 'cls_' || c.id || '_late';
      if v_late is null then continue; end if;

      insert into meal_row_definitions
        (office_id, row_key, row_label, class_id, meal_stage, row_type, am_snack, lunch, pm_snack, sort_order, is_active)
      values (o.id, 'cls_' || c.id || '_toddler', c.class_name || '(幼児食)', c.id, 'toddler', 'children', true, true, true, v_late + 2, true)
      on conflict (office_id, row_key) do nothing;

      -- 8/26 暫定食数(3区分)。
      insert into meal_count_days (office_id, business_date, computed_at)
        values (o.id, v_date, now())
        on conflict (office_id, business_date) do update set computed_at = now();
      insert into meal_count_rows (office_id, business_date, row_key, meal_slot, child_count, staff_count, is_confirmed)
      select o.id, v_date, 'cls_' || c.id || '_toddler', s.slot, v_child, 0, true
      from (values ('am_snack'), ('lunch'), ('pm_snack')) as s(slot)
      on conflict (office_id, business_date, row_key, meal_slot)
        do update set child_count = excluded.child_count, is_confirmed = true, updated_at = now();
    end loop;
  end loop;
end $$;

-- ===== Step D: 8/26テスト食数の掃除(354混入分) =====
delete from meal_count_rows where business_date = '2026-08-26';
delete from meal_count_days where business_date = '2026-08-26';

-- ===== 最終確認 =====
select o.office_code, count(*) as meal_rows from meal_row_definitions m join offices o on o.id = m.office_id group by 1 order by 1;
select count(*) as aug26_should_be_0 from meal_count_days where business_date = '2026-08-26';
