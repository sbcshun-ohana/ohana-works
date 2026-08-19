-- 250: ヒヤリハット・事故報告 Phase A ⑤(初期ルックアップseed)。施設共通・冪等(既存labelはスキップ)。
-- 受診記録系(med_*)は俊承認(2026-08-19)の初期リスト。管理者以上が管理Webで後から編集可。

insert into incident_lookup_options (kind, label, sort_order)
select 'place', v.label, v.ord from (values
  ('保育室', 10), ('遊戯室(ホール)', 20), ('廊下・階段', 30), ('玄関', 40),
  ('トイレ・手洗い場', 50), ('園庭', 60), ('テラス・ベランダ', 70), ('駐車場', 80),
  ('プール・水遊び場', 90), ('給食室・調理室', 100), ('午睡室', 110),
  ('園外(散歩・公園)', 120), ('送迎車内', 130), ('その他', 999)
) as v(label, ord)
where not exists (select 1 from incident_lookup_options o where o.kind = 'place' and o.label = v.label);

insert into incident_lookup_options (kind, label, sort_order)
select 'injury_site', v.label, v.ord from (values
  ('頭', 10), ('顔', 20), ('目', 30), ('口・歯', 40), ('耳', 50), ('鼻', 60),
  ('首', 70), ('肩', 80), ('腕', 90), ('ひじ', 100), ('手・指', 110),
  ('胸・腹', 120), ('背中', 130), ('腰', 140), ('お尻', 150),
  ('脚(太もも・すね)', 160), ('ひざ', 170), ('足首・足', 180), ('全身', 190), ('その他', 999)
) as v(label, ord)
where not exists (select 1 from incident_lookup_options o where o.kind = 'injury_site' and o.label = v.label);

insert into incident_lookup_options (kind, label, sort_order)
select 'med_department', v.label, v.ord from (values
  ('小児科', 10), ('整形外科', 20), ('外科', 30), ('皮膚科', 40), ('眼科', 50),
  ('耳鼻咽喉科', 60), ('歯科', 70), ('脳神経外科', 80), ('その他', 999)
) as v(label, ord)
where not exists (select 1 from incident_lookup_options o where o.kind = 'med_department' and o.label = v.label);

insert into incident_lookup_options (kind, label, sort_order)
select 'med_exam', v.label, v.ord from (values
  ('レントゲン', 10), ('CT', 20), ('MRI', 30), ('エコー', 40), ('血液検査', 50),
  ('視診・触診', 60), ('経過観察', 70), ('その他', 999)
) as v(label, ord)
where not exists (select 1 from incident_lookup_options o where o.kind = 'med_exam' and o.label = v.label);

insert into incident_lookup_options (kind, label, sort_order)
select 'med_treatment', v.label, v.ord from (values
  ('消毒', 10), ('縫合', 20), ('テープ固定', 30), ('ギプス', 40), ('冷却', 50),
  ('軟膏塗布', 60), ('処置なし', 70), ('その他', 999)
) as v(label, ord)
where not exists (select 1 from incident_lookup_options o where o.kind = 'med_treatment' and o.label = v.label);

insert into incident_lookup_options (kind, label, sort_order)
select 'med_prescription', v.label, v.ord from (values
  ('抗生剤', 10), ('解熱鎮痛剤', 20), ('塗り薬(軟膏)', 30), ('湿布', 40),
  ('目薬', 50), ('なし', 60), ('その他', 999)
) as v(label, ord)
where not exists (select 1 from incident_lookup_options o where o.kind = 'med_prescription' and o.label = v.label);
