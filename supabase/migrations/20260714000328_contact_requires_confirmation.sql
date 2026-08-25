-- 328: 園連絡帳の「重要事項として開封確認を求める」フラグ(俊指示 2026-08-25)。
-- 従来は全連絡帳で保護者に「重要事項として確認しました」ボタンが出ていた。本来は園が重要事項として
-- 送った連絡帳のみボタンを出す。通常の連絡帳は開封(既読=communication_book_reads)を自動記録するだけで、
-- 保護者に確認ボタンを押させる必要はない。
alter table child_daily_contacts add column if not exists requires_confirmation boolean not null default false;
comment on column child_daily_contacts.requires_confirmation is
  '重要事項として保護者の開封確認(communication_book_confirmations)を求めるか。true のときのみ保護者アプリに確認ボタンを表示。';
