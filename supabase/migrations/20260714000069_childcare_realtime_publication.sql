-- 保育業務 Phase1: Realtime配信対象への追加
-- 欠席チェック・クラス活動・連絡帳の承認/差し戻し/コメントを複数端末へ即時反映するため、
-- supabase_realtimeパブリケーションに対象テーブルを追加する。
-- (適用前に確認済み: supabase_realtimeパブリケーションは0テーブルのため、既存機能への影響はない)

alter publication supabase_realtime add table child_daily_attendance;
alter publication supabase_realtime add table class_daily_activities;
alter publication supabase_realtime add table child_daily_contacts;
