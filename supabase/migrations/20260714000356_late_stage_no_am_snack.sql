-- 356: 0歳児「後期(late)」食は午前おやつの提供なし(俊指示 2026-08-26)。
--   後期行の am_snack を false にし、既存の(後期×午前おやつ)食数行も削除する。
--   完了期(complete)/幼児食(toddler)、そら/かぜ(1・2歳)、ラウ/プア等は午前おやつあり(変更なし)。全施設共通。
update meal_row_definitions set am_snack = false where meal_stage = 'late' and am_snack;

-- 既に算出/暫定投入済みの「後期×午前おやつ」食数行を削除(ボードに残さない)。
delete from meal_count_rows mr
using meal_row_definitions rd
where mr.office_id = rd.office_id and mr.row_key = rd.row_key
  and rd.meal_stage = 'late' and mr.meal_slot = 'am_snack';
