-- 保護者アプリ Phase A: デイリーボード用の日次状態集約
--
-- child_attendance_events(登降園)とchild_daily_attendance(Phase1・欠席フラグ)を
-- 突き合わせた結果を1園児1日1行に集約する。更新はDBトリガーではなく、
-- イベント記録RPC(20260714000093)側で明示的にupsertする方針とする
-- (「何が状態を変えたか」をコードで追いやすくするため)。

create table daily_child_status (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  business_date date not null,
  status text not null default 'not_arrived' check (status in ('not_arrived', 'present', 'picked_up', 'absent')),
  last_event_id uuid references child_attendance_events(id),
  updated_at timestamptz not null default now(),
  unique (child_id, business_date)
);
create trigger trg_daily_child_status_updated_at before update on daily_child_status
  for each row execute function set_updated_at();

alter table daily_child_status enable row level security;
create policy daily_child_status_select on daily_child_status
  for select using (
    guardian_has_child_access(child_id) or staff_has_guardian_data_access(child_id)
  );

do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'daily_child_status'
  );
end $$;
