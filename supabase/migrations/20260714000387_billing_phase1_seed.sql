-- 387: 請求決済 Phase1(その2) — 料金マスター初期データ(2026年度値・草案§5/§10/§11と1円単位で突合)。
--   俊承認(2026-08-28): 2026年度値で投入・2027年度改定は版追加で対応(削除禁止)。
--   備品(supply)15品目は器のみ(単価=fee_rate_versions は俊の金額確定後に登録)。
--   event/misc/adjustment系は金額都度入力(詳細設計§11 Q&A-4)のため単価版なし。
--   全て office_code/名前解決・on conflict で冪等。effective_from=2026-04-01・version=1。
--   ※「契約時間外(30分500円)」等の名称は料金区分の識別子として金額を含む(改定時は新版で金額のみ
--     変わり得る点を display_note に明記する運用)。

-- ============================================================
-- (1) fee_items — 大和(O)
-- ============================================================
insert into fee_items (office_id, category, name, calc_unit, sort_order)
select o.id, v.cat, v.name, v.unit, v.ord
from offices o
join (values
  ('O', 'monthly_extension', '月極延長 30分(〜18:30)', 'monthly',   10),
  ('O', 'monthly_extension', '月極延長 1時間(〜19:00)', 'monthly',  11),
  ('O', 'extension',         '随時延長(30分)',           'per_30min', 20),
  ('O', 'meal_main',         '主食費(3歳以上)',         'monthly',   30),
  ('O', 'meal_side',         '副食費(3歳以上)',         'monthly',   31),
  ('O', 'diaper',            'おむつ',                    'per_piece', 40),
  ('O', 'event',             '行事費',                    'one_time',  90),
  ('O', 'misc',              'その他実費',                'one_time',  91),
  ('O', 'adjustment_plus',   '請求額調整(加算)',        'one_time',  98),
  ('O', 'adjustment_minus',  '請求額調整(減算)',        'one_time',  99)
) as v(code, cat, name, unit, ord) on v.code = o.office_code
on conflict (office_id, category, name) do nothing;

-- ============================================================
-- (2) fee_items — BABY MAHALO(M)
-- ============================================================
insert into fee_items (office_id, category, name, calc_unit, sort_order)
select o.id, v.cat, v.name, v.unit, v.ord
from offices o
join (values
  ('M', 'monthly_base',    '月極保育料 7:00-20:00 0歳児',   'monthly', 1),
  ('M', 'monthly_base',    '月極保育料 7:00-20:00 1・2歳児', 'monthly', 2),
  ('M', 'monthly_base',    '月極保育料 8:00-18:00 0歳児',   'monthly', 3),
  ('M', 'monthly_base',    '月極保育料 8:00-18:00 1・2歳児', 'monthly', 4),
  ('M', 'monthly_base',    '月極保育料 9:00-17:00 0歳児',   'monthly', 5),
  ('M', 'monthly_base',    '月極保育料 9:00-17:00 1・2歳児', 'monthly', 6),
  ('M', 'monthly_base',    '月極保育料 9:00-16:00 0歳児',   'monthly', 7),
  ('M', 'monthly_base',    '月極保育料 9:00-16:00 1・2歳児', 'monthly', 8),
  ('M', 'extension',       '契約時間外(30分500円)',        'per_30min', 20),
  ('M', 'extension',       '契約時間外(30分700円)',        'per_30min', 21),
  ('M', 'extension',       '契約時間外(30分1000円)',       'per_30min', 22),
  ('M', 'closing_overrun', '閉園時刻超過(10分)',           'per_10min', 25),
  ('M', 'temp_care',       '一時預かり(10分)',             'per_10min', 50),
  ('M', 'temp_care_meal',  '一時預かり給食費',              'per_day',   51),
  ('M', 'temp_care_snack', '一時預かりおやつ代',            'per_day',   52),
  ('M', 'event',            '行事費',                        'one_time',  90),
  ('M', 'misc',             'その他実費',                    'one_time',  91),
  ('M', 'adjustment_plus',  '請求額調整(加算)',            'one_time',  98),
  ('M', 'adjustment_minus', '請求額調整(減算)',            'one_time',  99)
) as v(code, cat, name, unit, ord) on v.code = o.office_code
on conflict (office_id, category, name) do nothing;

-- ============================================================
-- (3) fee_items — MahaloStation(S)
-- ============================================================
insert into fee_items (office_id, category, name, calc_unit, sort_order)
select o.id, v.cat, v.name, v.unit, v.ord
from offices o
join (values
  ('S', 'monthly_base', '月極保育料 8:00-19:00 0歳児',   'monthly', 1),
  ('S', 'monthly_base', '月極保育料 8:00-19:00 1・2歳児', 'monthly', 2),
  ('S', 'monthly_base', '月極保育料 9:00-18:00 0歳児',   'monthly', 3),
  ('S', 'monthly_base', '月極保育料 9:00-18:00 1・2歳児', 'monthly', 4),
  ('S', 'monthly_base', '月極保育料 9:00-17:00 0歳児',   'monthly', 5),
  ('S', 'monthly_base', '月極保育料 9:00-17:00 1・2歳児', 'monthly', 6),
  ('S', 'monthly_base', '月極保育料 9:00-16:00 0歳児',   'monthly', 7),
  ('S', 'monthly_base', '月極保育料 9:00-16:00 1・2歳児', 'monthly', 8),
  ('S', 'monthly_base', '月極保育料 9:00-15:00 0歳児',   'monthly', 9),
  ('S', 'monthly_base', '月極保育料 9:00-15:00 1・2歳児', 'monthly', 10),
  ('S', 'extension',    '契約時間外(30分300円)',        'per_30min', 20),
  ('S', 'extension',    '契約時間外(30分500円)',        'per_30min', 21),
  ('S', 'extension',    '契約時間外(30分700円)',        'per_30min', 22),
  ('S', 'extension',    '契約時間外(30分1000円)',       'per_30min', 23),
  ('S', 'event',            '行事費',            'one_time', 90),
  ('S', 'misc',             'その他実費',        'one_time', 91),
  ('S', 'adjustment_plus',  '請求額調整(加算)', 'one_time', 98),
  ('S', 'adjustment_minus', '請求額調整(減算)', 'one_time', 99)
) as v(code, cat, name, unit, ord) on v.code = o.office_code
on conflict (office_id, category, name) do nothing;

-- ============================================================
-- (4) fee_items — Halelea(H)
-- ============================================================
insert into fee_items (office_id, category, name, calc_unit, sort_order)
select o.id, v.cat, v.name, v.unit, v.ord
from offices o
join (values
  ('H', 'monthly_base', '月極保育料 8:00-19:00 0歳児',   'monthly', 1),
  ('H', 'monthly_base', '月極保育料 8:00-19:00 1・2歳児', 'monthly', 2),
  ('H', 'monthly_base', '月極保育料 9:00-17:00 0歳児',   'monthly', 3),
  ('H', 'monthly_base', '月極保育料 9:00-17:00 1・2歳児', 'monthly', 4),
  ('H', 'monthly_base', '月極保育料 9:00-16:00 0歳児',   'monthly', 5),
  ('H', 'monthly_base', '月極保育料 9:00-16:00 1・2歳児', 'monthly', 6),
  ('H', 'monthly_base', '月極保育料 9:00-15:00 0歳児',   'monthly', 7),
  ('H', 'monthly_base', '月極保育料 9:00-15:00 1・2歳児', 'monthly', 8),
  ('H', 'extension',    '契約時間外(30分500円)',        'per_30min', 20),
  ('H', 'extension',    '契約時間外(30分700円)',        'per_30min', 21),
  ('H', 'extension',    '契約時間外(30分1000円)',       'per_30min', 22),
  ('H', 'event',            '行事費',            'one_time', 90),
  ('H', 'misc',             'その他実費',        'one_time', 91),
  ('H', 'adjustment_plus',  '請求額調整(加算)', 'one_time', 98),
  ('H', 'adjustment_minus', '請求額調整(減算)', 'one_time', 99)
) as v(code, cat, name, unit, ord) on v.code = o.office_code
on conflict (office_id, category, name) do nothing;

-- ============================================================
-- (5) fee_items — 備品(supply)15品目 × 全4施設(器のみ・単価は俊の金額確定後に登録)
-- ============================================================
insert into fee_items (office_id, category, name, calc_unit, sort_order)
select o.id, 'supply', v.name, 'per_piece', 60 + v.ord
from offices o
cross join (values
  ('帽子', 1), ('名札', 2), ('おどうぐ箱', 3), ('体操服(上)', 4), ('体操服(下)', 5),
  ('スモック', 6), ('マーカーペン', 7), ('クレヨン', 8), ('製作帳', 9), ('自由画帳', 10),
  ('のり', 11), ('はさみ', 12), ('ベッドシーツ', 13), ('防災頭巾', 14), ('ヘルメット', 15)
) as v(name, ord)
where o.office_code in ('O', 'M', 'S', 'H')
on conflict (office_id, category, name) do nothing;

-- ============================================================
-- (6) fee_rate_versions — 単価(2026年度・version=1・effective_from=2026-04-01)
-- ============================================================
insert into fee_rate_versions (fee_item_id, amount, version, effective_from, source_note)
select f.id, v.amount, 1, date '2026-04-01', '草案§5/§10/§11(2026年度)'
from (values
  -- 大和(O)
  ('O', 'monthly_extension', '月極延長 30分(〜18:30)',  3000),
  ('O', 'monthly_extension', '月極延長 1時間(〜19:00)', 6000),
  ('O', 'extension',         '随時延長(30分)',            500),
  ('O', 'meal_main',         '主食費(3歳以上)',          2000),
  ('O', 'meal_side',         '副食費(3歳以上)',          4500),
  ('O', 'diaper',            'おむつ',                       90),
  -- BABY MAHALO(M)
  ('M', 'monthly_base', '月極保育料 7:00-20:00 0歳児',   35000),
  ('M', 'monthly_base', '月極保育料 7:00-20:00 1・2歳児', 30000),
  ('M', 'monthly_base', '月極保育料 8:00-18:00 0歳児',   30000),
  ('M', 'monthly_base', '月極保育料 8:00-18:00 1・2歳児', 25000),
  ('M', 'monthly_base', '月極保育料 9:00-17:00 0歳児',   25000),
  ('M', 'monthly_base', '月極保育料 9:00-17:00 1・2歳児', 20000),
  ('M', 'monthly_base', '月極保育料 9:00-16:00 0歳児',   20000),
  ('M', 'monthly_base', '月極保育料 9:00-16:00 1・2歳児', 10000),
  ('M', 'extension',       '契約時間外(30分500円)',   500),
  ('M', 'extension',       '契約時間外(30分700円)',   700),
  ('M', 'extension',       '契約時間外(30分1000円)', 1000),
  ('M', 'closing_overrun', '閉園時刻超過(10分)',      450),
  ('M', 'temp_care',       '一時預かり(10分)',        200),
  ('M', 'temp_care_meal',  '一時預かり給食費',         500),
  ('M', 'temp_care_snack', '一時預かりおやつ代',       100),
  -- MahaloStation(S)
  ('S', 'monthly_base', '月極保育料 8:00-19:00 0歳児',   30000),
  ('S', 'monthly_base', '月極保育料 8:00-19:00 1・2歳児', 25000),
  ('S', 'monthly_base', '月極保育料 9:00-18:00 0歳児',   25000),
  ('S', 'monthly_base', '月極保育料 9:00-18:00 1・2歳児', 20000),
  ('S', 'monthly_base', '月極保育料 9:00-17:00 0歳児',   20000),
  ('S', 'monthly_base', '月極保育料 9:00-17:00 1・2歳児', 15000),
  ('S', 'monthly_base', '月極保育料 9:00-16:00 0歳児',   15000),
  ('S', 'monthly_base', '月極保育料 9:00-16:00 1・2歳児', 10000),
  ('S', 'monthly_base', '月極保育料 9:00-15:00 0歳児',   10000),
  ('S', 'monthly_base', '月極保育料 9:00-15:00 1・2歳児',  5000),
  ('S', 'extension', '契約時間外(30分300円)',   300),
  ('S', 'extension', '契約時間外(30分500円)',   500),
  ('S', 'extension', '契約時間外(30分700円)',   700),
  ('S', 'extension', '契約時間外(30分1000円)', 1000),
  -- Halelea(H)
  ('H', 'monthly_base', '月極保育料 8:00-19:00 0歳児',   25000),
  ('H', 'monthly_base', '月極保育料 8:00-19:00 1・2歳児', 20000),
  ('H', 'monthly_base', '月極保育料 9:00-17:00 0歳児',   20000),
  ('H', 'monthly_base', '月極保育料 9:00-17:00 1・2歳児', 15000),
  ('H', 'monthly_base', '月極保育料 9:00-16:00 0歳児',   15000),
  ('H', 'monthly_base', '月極保育料 9:00-16:00 1・2歳児', 10000),
  ('H', 'monthly_base', '月極保育料 9:00-15:00 0歳児',   10000),
  ('H', 'monthly_base', '月極保育料 9:00-15:00 1・2歳児',  5000),
  ('H', 'extension', '契約時間外(30分500円)',   500),
  ('H', 'extension', '契約時間外(30分700円)',   700),
  ('H', 'extension', '契約時間外(30分1000円)', 1000)
) as v(code, cat, name, amount)
join offices o on o.office_code = v.code
join fee_items f on f.office_id = o.id and f.category = v.cat and f.name = v.name
on conflict (fee_item_id, version) do nothing;

-- ============================================================
-- (7) contract_plans — 大和2行+M8行+S10行+H8行(effective_from=2026-04-01)
-- ============================================================
insert into contract_plans
  (office_id, name, cert_type, usage_start, usage_end, age_band,
   monthly_fee_item_id, overtime_fee_item_id, effective_from)
select o.id, v.name, v.cert, v.us::time, v.ue::time, v.band, mf.id, ot.id, date '2026-04-01'
from (values
  -- 大和(認定2区分・月極保育料=自治体徴収でnull・時間外=随時延長500円)
  ('O', '保育標準時間', 'standard', '07:00', '18:00', null::text, null::text, '随時延長(30分)'),
  ('O', '保育短時間',   'short',    '08:00', '16:00', null,       null,       '随時延長(30分)'),
  -- BABY MAHALO(8行)
  ('M', '7:00-20:00 0歳児',    null, '07:00', '20:00', 'age0',    '月極保育料 7:00-20:00 0歳児',   null),
  ('M', '7:00-20:00 1・2歳児', null, '07:00', '20:00', 'age1_2',  '月極保育料 7:00-20:00 1・2歳児', null),
  ('M', '8:00-18:00 0歳児',    null, '08:00', '18:00', 'age0',    '月極保育料 8:00-18:00 0歳児',   '契約時間外(30分500円)'),
  ('M', '8:00-18:00 1・2歳児', null, '08:00', '18:00', 'age1_2',  '月極保育料 8:00-18:00 1・2歳児', '契約時間外(30分500円)'),
  ('M', '9:00-17:00 0歳児',    null, '09:00', '17:00', 'age0',    '月極保育料 9:00-17:00 0歳児',   '契約時間外(30分700円)'),
  ('M', '9:00-17:00 1・2歳児', null, '09:00', '17:00', 'age1_2',  '月極保育料 9:00-17:00 1・2歳児', '契約時間外(30分700円)'),
  ('M', '9:00-16:00 0歳児',    null, '09:00', '16:00', 'age0',    '月極保育料 9:00-16:00 0歳児',   '契約時間外(30分1000円)'),
  ('M', '9:00-16:00 1・2歳児', null, '09:00', '16:00', 'age1_2',  '月極保育料 9:00-16:00 1・2歳児', '契約時間外(30分1000円)'),
  -- MahaloStation(10行)
  ('S', '8:00-19:00 0歳児',    null, '08:00', '19:00', 'age0',    '月極保育料 8:00-19:00 0歳児',   null),
  ('S', '8:00-19:00 1・2歳児', null, '08:00', '19:00', 'age1_2',  '月極保育料 8:00-19:00 1・2歳児', null),
  ('S', '9:00-18:00 0歳児',    null, '09:00', '18:00', 'age0',    '月極保育料 9:00-18:00 0歳児',   '契約時間外(30分300円)'),
  ('S', '9:00-18:00 1・2歳児', null, '09:00', '18:00', 'age1_2',  '月極保育料 9:00-18:00 1・2歳児', '契約時間外(30分300円)'),
  ('S', '9:00-17:00 0歳児',    null, '09:00', '17:00', 'age0',    '月極保育料 9:00-17:00 0歳児',   '契約時間外(30分500円)'),
  ('S', '9:00-17:00 1・2歳児', null, '09:00', '17:00', 'age1_2',  '月極保育料 9:00-17:00 1・2歳児', '契約時間外(30分500円)'),
  ('S', '9:00-16:00 0歳児',    null, '09:00', '16:00', 'age0',    '月極保育料 9:00-16:00 0歳児',   '契約時間外(30分700円)'),
  ('S', '9:00-16:00 1・2歳児', null, '09:00', '16:00', 'age1_2',  '月極保育料 9:00-16:00 1・2歳児', '契約時間外(30分700円)'),
  ('S', '9:00-15:00 0歳児',    null, '09:00', '15:00', 'age0',    '月極保育料 9:00-15:00 0歳児',   '契約時間外(30分1000円)'),
  ('S', '9:00-15:00 1・2歳児', null, '09:00', '15:00', 'age1_2',  '月極保育料 9:00-15:00 1・2歳児', '契約時間外(30分1000円)'),
  -- Halelea(8行)
  ('H', '8:00-19:00 0歳児',    null, '08:00', '19:00', 'age0',    '月極保育料 8:00-19:00 0歳児',   null),
  ('H', '8:00-19:00 1・2歳児', null, '08:00', '19:00', 'age1_2',  '月極保育料 8:00-19:00 1・2歳児', null),
  ('H', '9:00-17:00 0歳児',    null, '09:00', '17:00', 'age0',    '月極保育料 9:00-17:00 0歳児',   '契約時間外(30分500円)'),
  ('H', '9:00-17:00 1・2歳児', null, '09:00', '17:00', 'age1_2',  '月極保育料 9:00-17:00 1・2歳児', '契約時間外(30分500円)'),
  ('H', '9:00-16:00 0歳児',    null, '09:00', '16:00', 'age0',    '月極保育料 9:00-16:00 0歳児',   '契約時間外(30分700円)'),
  ('H', '9:00-16:00 1・2歳児', null, '09:00', '16:00', 'age1_2',  '月極保育料 9:00-16:00 1・2歳児', '契約時間外(30分700円)'),
  ('H', '9:00-15:00 0歳児',    null, '09:00', '15:00', 'age0',    '月極保育料 9:00-15:00 0歳児',   '契約時間外(30分1000円)'),
  ('H', '9:00-15:00 1・2歳児', null, '09:00', '15:00', 'age1_2',  '月極保育料 9:00-15:00 1・2歳児', '契約時間外(30分1000円)')
) as v(code, name, cert, us, ue, band, mfname, otname)
join offices o on o.office_code = v.code
left join fee_items mf on mf.office_id = o.id and mf.category = 'monthly_base' and mf.name = v.mfname
left join fee_items ot on ot.office_id = o.id and ot.category = 'extension'    and ot.name = v.otname
on conflict (office_id, name, effective_from) do nothing;

-- ============================================================
-- (8) monthly_extension_plans — 大和2行
-- ============================================================
insert into monthly_extension_plans (office_id, name, coverage_end, fee_item_id, effective_from)
select o.id, v.pname, v.cov::time, f.id, date '2026-04-01'
from (values
  ('O', '月極延長 30分プラン',  '18:30', '月極延長 30分(〜18:30)'),
  ('O', '月極延長 1時間プラン', '19:00', '月極延長 1時間(〜19:00)')
) as v(code, pname, cov, finame)
join offices o on o.office_code = v.code
join fee_items f on f.office_id = o.id and f.category = 'monthly_extension' and f.name = v.finame
on conflict (office_id, name, effective_from) do nothing;

-- ============================================================
-- (9) closing_overrun_rules — BABY MAHALO のみ(S/Hは器のみ=行を作らない・将来INSERTで有効化)
-- ============================================================
insert into closing_overrun_rules (office_id, fee_item_id, enabled_from_fiscal_year)
select o.id, f.id, 2026
from offices o
join fee_items f on f.office_id = o.id and f.category = 'closing_overrun' and f.name = '閉園時刻超過(10分)'
where o.office_code = 'M'
on conflict (office_id, fee_item_id) do nothing;
