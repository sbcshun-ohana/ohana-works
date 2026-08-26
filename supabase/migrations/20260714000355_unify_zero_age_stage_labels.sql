-- 355: 0歳児の給食段階(はな組/リコ等)の行ラベルを「後期/完了期/幼児食」に統一する(俊指示 2026-08-26)。
--   従来は「はな組(後期)」「リコ(後期)」のようにクラス名付きで施設ごとにバラついていた。
--   各施設に0歳クラスは1つ(=段階名だけで一意)のため、段階名のみに揃える。上から 後期→完了期→幼児食(sort_order順)。
--   meal_stage で一括更新。冪等。
update meal_row_definitions set row_label = '後期'   where meal_stage = 'late'     and row_label <> '後期';
update meal_row_definitions set row_label = '完了期' where meal_stage = 'complete' and row_label <> '完了期';
update meal_row_definitions set row_label = '幼児食' where meal_stage = 'toddler'  and row_label <> '幼児食';
