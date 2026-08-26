-- 348: 実機テスト用の暫定データ第2弾(俊指示 2026-08-26)。
--   A) アレルギー(除去食)を確実に表示: 大和はな組の在籍児に「卵」除去の診断書(受領日=経過措置内)を付与。
--   B) 厨房ビューの複数施設レイアウト確認: BABY MAHALO(M)/Mahalo Station(S)の食数を暫定投入。
--   C) 職員食事表のレイアウト確認: 大和の職員数名 × 8/22〜8/26 の食事参加を暫定投入。
--   ※すべてテスト用の適当な値。冪等。
do $$
declare
  v_office uuid := 'c0a7010a-fd37-4cad-971b-6b3f2e80f842';
  v_date   date := date '2026-08-26';
  v_hana   uuid;
  v_child  uuid;
  o record; r record; emp record;
  d date; i int := 0;
begin
  -- ===== A) アレルギー児(はな組・卵除去・経過措置で除去食提供)=====
  select id into v_hana from childcare_classes
    where office_id = v_office and age_group = '0歳' and is_active
    order by school_year desc limit 1;
  if v_hana is not null then
    select ch.id into v_child from children ch
      join child_class_enrollments e on e.child_id = ch.id and e.class_id = v_hana and e.effective_end_date is null
      where ch.office_id = v_office and ch.enrollment_status = '在籍中'
      order by ch.display_name limit 1;
    if v_child is not null then
      delete from child_daily_attendance where child_id = v_child and business_date = v_date and is_absent;
      if not exists (
        select 1 from child_allergy_diagnoses
        where child_id = v_child and status = 'received' and '卵' = any(coalesce(elimination_targets, '{}'))
      ) then
        insert into child_allergy_diagnoses
          (child_id, office_id, status, requested_at, received_at, elimination_targets, effective_from, doctor_name, diagnosis_content)
        values (v_child, v_office, 'received', date '2026-07-25', date '2026-08-01', array['卵'], date '2026-08-01', 'テスト医師', 'テスト用(卵除去)');
      end if;
    end if;
  end if;

  -- ===== B) M/S 施設の食数(プレビュー用の暫定数)=====
  for o in select id, office_code from offices where office_code in ('M', 'S') loop
    insert into meal_count_days (office_id, business_date, computed_at)
    values (o.id, v_date, now())
    on conflict (office_id, business_date) do update set computed_at = now();
    for r in select rd.row_key, rd.row_type, rd.am_snack, rd.lunch, rd.pm_snack from meal_row_definitions rd
             where rd.office_id = o.id and rd.is_active loop
      if r.am_snack then
        insert into meal_count_rows (office_id, business_date, row_key, meal_slot, child_count, staff_count)
        values (o.id, v_date, r.row_key, 'am_snack', case when r.row_type = 'children' then 5 else 0 end, case when r.row_type = 'staff' then 3 else 0 end)
        on conflict (office_id, business_date, row_key, meal_slot) do update set child_count = excluded.child_count, staff_count = excluded.staff_count, updated_at = now();
      end if;
      if r.lunch then
        insert into meal_count_rows (office_id, business_date, row_key, meal_slot, child_count, staff_count)
        values (o.id, v_date, r.row_key, 'lunch', case when r.row_type = 'children' then 5 else 0 end, case when r.row_type = 'staff' then 3 else 0 end)
        on conflict (office_id, business_date, row_key, meal_slot) do update set child_count = excluded.child_count, staff_count = excluded.staff_count, updated_at = now();
      end if;
      if r.pm_snack then
        insert into meal_count_rows (office_id, business_date, row_key, meal_slot, child_count, staff_count)
        values (o.id, v_date, r.row_key, 'pm_snack', case when r.row_type = 'children' then 5 else 0 end, case when r.row_type = 'staff' then 3 else 0 end)
        on conflict (office_id, business_date, row_key, meal_slot) do update set child_count = excluded.child_count, staff_count = excluded.staff_count, updated_at = now();
      end if;
    end loop;
  end loop;

  -- ===== C) 職員食事表(大和の職員数名 × 8/22〜8/26・土日除く)=====
  for emp in select e.id from employees e where e.home_office_id = v_office order by e.id limit 5 loop
    d := date '2026-08-22';
    while d <= v_date loop
      if extract(dow from d) not in (0, 6) then
        insert into staff_meal_participation (employee_id, office_id, business_date, ate, source)
        values (emp.id, v_office, d, true, case when i % 2 = 0 then 'auto' else 'self_order' end)
        on conflict (employee_id, business_date) do update set ate = true, source = excluded.source, updated_at = now();
      end if;
      d := d + 1;
    end loop;
    i := i + 1;
  end loop;
end $$;
