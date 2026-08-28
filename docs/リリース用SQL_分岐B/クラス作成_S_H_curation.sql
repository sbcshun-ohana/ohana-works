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

-- 確認(期待: S=3行・H=3行が追加され、合計15行程度になる)
select o.office_code, c.class_name, c.age_group
from childcare_classes c join offices o on o.id = c.office_id
order by o.office_code, c.age_group;
