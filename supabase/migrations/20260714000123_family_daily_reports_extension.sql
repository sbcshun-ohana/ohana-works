-- 家庭連絡帳(family_daily_reports)拡張: 機嫌・排便・睡眠・食事・お迎え変更連絡
-- 既存の提出済みデータとの後方互換のため、追加カラムは全てnullableにする。
-- 睡眠・食事の時刻は既存のtemperature_measured_atと同じ「time型(日付を持たない)」方式を踏襲する。
-- sleep_start_at/dinner_atはbusiness_dateの前日夜、sleep_end_at/breakfast_atは当日朝という運用前提。

alter table family_daily_reports
  add column night_mood text check (night_mood in ('good', 'normal', 'bad')),
  add column morning_mood text check (morning_mood in ('good', 'normal', 'bad')),
  add column night_bowel_count int check (night_bowel_count between 0 and 5),
  add column night_bowel_condition text check (night_bowel_condition in ('normal', 'soft', 'hard', 'small')),
  add column morning_bowel_count int check (morning_bowel_count between 0 and 5),
  add column morning_bowel_condition text check (morning_bowel_condition in ('normal', 'soft', 'hard', 'small')),
  add column sleep_start_at time,
  add column sleep_end_at time,
  add column dinner_content text,
  add column dinner_at time,
  add column breakfast_content text,
  add column breakfast_at time,
  add column pickup_person_name text,
  add column pickup_person_relationship text,
  add column pickup_time_from time,
  add column pickup_time_to time;

comment on column family_daily_reports.sleep_start_at is '入眠時刻(前日夜、時刻のみ)';
comment on column family_daily_reports.sleep_end_at is '起床時刻(当日朝、時刻のみ)';
comment on column family_daily_reports.dinner_at is '夕食摂取時刻(前日夜、時刻のみ)';
comment on column family_daily_reports.breakfast_at is '朝食摂取時刻(当日朝、時刻のみ)';
comment on column family_daily_reports.pickup_person_name is 'お迎え者変更連絡(任意)。既存のparent_requests(pickup_person_change申請)とは別の、日々の連絡帳としての入力。';
