-- 383: 年末年始の休園を 12/29〜1/3 に統一(俊確定 2026-08-27)。
--   049 seed は 12/31・1/1・1/2・1/3 のみで 12/29・12/30 が抜けていた。全園共通の休園として追加。
--   holidays は全園共通(office_id なし)。is_office_closed が year_end_new_year を休園扱いにする。
insert into holidays (holiday_date, holiday_type, name) values
  ('2025-12-29', 'year_end_new_year', '年末休園'),
  ('2025-12-30', 'year_end_new_year', '年末休園'),
  ('2026-12-29', 'year_end_new_year', '年末休園'),
  ('2026-12-30', 'year_end_new_year', '年末休園'),
  ('2027-12-29', 'year_end_new_year', '年末休園'),
  ('2027-12-30', 'year_end_new_year', '年末休園')
on conflict (holiday_date) do nothing;
