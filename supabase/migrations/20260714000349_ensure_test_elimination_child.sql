-- 349: 厨房ビューの「アレルギー対応食」を表(セル内)+下部リストの両方に確実に表示させるテスト用調整(俊指示 2026-08-26)。
--   ① 大和の除去食対象児の診断書を経過措置内(受領<=2026-08-21・有効・received)に整え、除去食提供(elimination)判定にする。
--   ② 該当児が居なければ、はな組の在籍児に「卵」除去を新規付与。当日(8/26)は非欠席にする(欠席は集計除外のため)。
--   ③ 除去食児に「承認済み給食段階(child_meal_stages)」を付与する。
--      理由: 食数エンジン(257)も厨房ビュー集計(346)も、児を「クラス×給食段階」で行(meal_row_definitions)へ振り分ける。
--            0歳(はな組=後期/完了期/幼児食に分割)の児は current_stage が無いとどの行にも一致せず allergy_count=0 になる。
--      → serving_start<=当日 の 'late'(後期食) を与え、はな組(後期)行に紐付ける。分割なしクラス(meal_stage=null)でも無害。
do $$
declare
  v_office uuid := 'c0a7010a-fd37-4cad-971b-6b3f2e80f842';
  v_date   date := date '2026-08-26';
  v_hana   uuid; v_child uuid; er record;
begin
  -- ① 既存の除去診断を経過措置内・有効に整える(受領日を2026-08-01以前へ、有効終了をnull)。
  update child_allergy_diagnoses
    set status = 'received',
        received_at   = least(coalesce(received_at,   date '2026-08-01'), date '2026-08-01'),
        effective_from = least(coalesce(effective_from, date '2026-08-01'), date '2026-08-01'),
        effective_until = null
  where office_id = v_office and coalesce(array_length(elimination_targets, 1), 0) > 0;

  -- ② 除去診断のある児が居なければ、はな組の在籍児に卵除去を新規付与。
  if not exists (
    select 1 from child_allergy_diagnoses
    where office_id = v_office and status = 'received' and coalesce(array_length(elimination_targets, 1), 0) > 0
  ) then
    select id into v_hana from childcare_classes where office_id = v_office and age_group = '0歳' and is_active order by school_year desc limit 1;
    select ch.id into v_child from children ch
      join child_class_enrollments e on e.child_id = ch.id and e.class_id = v_hana and e.effective_end_date is null
      where ch.office_id = v_office and ch.enrollment_status = '在籍中' order by ch.display_name limit 1;
    if v_child is not null then
      insert into child_allergy_diagnoses
        (child_id, office_id, status, requested_at, received_at, elimination_targets, effective_from, doctor_name, diagnosis_content)
      values (v_child, v_office, 'received', date '2026-07-25', date '2026-08-01', array['卵'], date '2026-08-01', 'テスト医師', 'テスト用(卵除去)');
    end if;
  end if;

  -- ③ 当日は非欠席に(fetch_daily_elimination は欠席児を除外するため)。
  delete from child_daily_attendance a using child_allergy_diagnoses d
  where a.child_id = d.child_id and d.office_id = v_office
    and coalesce(array_length(d.elimination_targets, 1), 0) > 0
    and a.business_date = v_date and a.is_absent;

  -- ③ 除去食児に承認済み給食段階(後期食)を付与(current_stage が無いと行に振り分かないため)。
  for er in
    select distinct d.child_id
    from child_allergy_diagnoses d
    where d.office_id = v_office and d.status = 'received'
      and coalesce(array_length(d.elimination_targets, 1), 0) > 0
  loop
    if not exists (
      select 1 from child_meal_stages s
      where s.child_id = er.child_id and s.serving_start_date <= v_date
    ) then
      insert into child_meal_stages (child_id, office_id, stage, serving_start_date, note)
      values (er.child_id, v_office, 'late', date '2026-08-01', 'テスト用(後期食)');
    end if;
  end loop;
end $$;
