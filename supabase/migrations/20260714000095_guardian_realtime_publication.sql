-- 保護者アプリ Phase A: Realtime配信対象への追加
-- 登降園・デイリーボード・重要事項確認・保護者申請を複数端末(保護者アプリ・職員アプリ・
-- admin_web)へ即時反映する。

alter publication supabase_realtime add table daily_child_status;
alter publication supabase_realtime add table child_attendance_events;
alter publication supabase_realtime add table communication_book_confirmations;
alter publication supabase_realtime add table parent_requests;
