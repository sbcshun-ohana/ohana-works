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
