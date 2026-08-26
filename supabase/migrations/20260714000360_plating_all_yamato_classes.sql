-- 360: 盛り付け配膳を大和オハナ保育園の全クラスに拡張(俊指示 2026-08-26)。
--   つき/ほし/にじ(3-5歳)も厨房で盛り付け配膳することが判明 → 大和は全クラスが盛り付け対象。
--   requires_plating を 大和(office_code='O')の全児童クラス行に true(359では0-2歳のみだった)。
--   これで発注数ボードの「昼食/午後おやつ」で全大和クラスに 児/職 を別入力できる(後期/完了期は職員なし=幼児食に含める)。
update meal_row_definitions rd
set requires_plating = true
from childcare_classes c, offices o
where rd.class_id = c.id and c.office_id = o.id and o.office_code = 'O'
  and rd.row_type = 'children'
  and rd.requires_plating = false;
