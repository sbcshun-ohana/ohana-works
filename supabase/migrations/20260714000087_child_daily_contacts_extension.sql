-- 保護者アプリ Phase A: 既存child_daily_contacts(Phase1)への列追加(指示書§5.3 変更4)
--
-- これは唯一の「既存テーブルの変更」であり、指示書自身が明示的に指示している例外
-- (別機能としては作らず、既存の連絡帳入力画面を拡張する)。既存のRLSポリシー・RPC・
-- 監査トリガーはそのまま維持され、行単位のポリシーは新列にも自動的に適用される。
--
-- - 午睡時間: 複数区間の時間帯を持てるようjsonb配列(例: [{"start":"10:00","end":"11:30"}])
-- - 排泄: 選択式(普通/軟便/硬便/下痢便)を複数回記録できるようjsonb配列
-- - 食事: 完食割合(100/75/50/25/0%)+自由記入欄。連絡帳本文への自動転記はRPC/UI側で行う
-- - 検温: 35.0〜42.0℃・0.1℃刻み(家庭連絡帳と統一)
-- - 入浴: あり/なしのみ

alter table child_daily_contacts
  add column nap_periods jsonb not null default '[]',
  add column toileting_records jsonb not null default '[]',
  add column meal_completion_pct int check (meal_completion_pct in (100, 75, 50, 25, 0)),
  add column meal_free_note text,
  add column temperature numeric(3,1) check (temperature between 35.0 and 42.0),
  add column temperature_measured_at time,
  add column bath_taken boolean;
