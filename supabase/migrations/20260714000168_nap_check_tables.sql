-- Phase 3 §3.6: 午睡チェックのテーブル(nap_sessions / nap_checks)と、
-- 必須対象(0〜2歳児クラス=自動)判定用フラグ childcare_classes.nap_check_required。
-- 権限は保育業務ドメインの既存パターン(has_childcare_office_access / manages_childcare)に合わせる。
-- 書き込みは後続169の security definer RPC 経由に限定し、SELECT のみ RLS で開放する。

-- 1) 必須対象フラグ。既定 false(明示的に有効化する安全側)。既存クラスは 0〜2歳相当で curated 済の
--    family_daily_report_required の値で初期化する(家庭連絡帳必須とは分離し、将来午睡独自に調整可)。
alter table childcare_classes add column nap_check_required boolean not null default false;
update childcare_classes set nap_check_required = family_daily_report_required;

-- 2) 午睡セッション(園児×日で1件)。入眠でチェック開始・起床で終了。
create table nap_sessions (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  office_id uuid not null references offices(id),
  class_id uuid not null references childcare_classes(id),
  session_date date not null,
  sleep_start_at timestamptz,
  wake_up_at timestamptz,
  is_required boolean not null default false,   -- 必須対象(0〜2歳)か任意追加(3歳以上)か
  added_by uuid references employees(id),        -- 任意追加した職員(必須対象は null)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (child_id, session_date)
);
create trigger trg_nap_sessions_updated_at before update on nap_sessions
  for each row execute function set_updated_at();

-- 3) 午睡チェック(セッション×5分スロットで1件)。
create table nap_checks (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references nap_sessions(id) on delete cascade,
  slot_at timestamptz not null,                  -- 5分刻みの正時刻(対象スロット)
  body_position text not null check (body_position in ('right', 'left', 'supine', 'prone_corrected')),
  breathing_checked boolean not null default false,
  complexion_checked boolean not null default false,
  bedding_checked boolean not null default false,
  checked_by uuid references employees(id),
  checked_at timestamptz not null default now(), -- 実記録時刻(30分ルール・監査用にslot_atと区別)
  source text not null default 'realtime' check (source in ('realtime', 'late_entry', 'admin_edit')),
  created_at timestamptz not null default now(),
  unique (session_id, slot_at)
);

-- 4) RLS(SELECTのみ・施設アクセス保持者。書き込みは security definer RPC 経由)
alter table nap_sessions enable row level security;
create policy nap_sessions_select on nap_sessions
  for select using (has_childcare_office_access(office_id));

alter table nap_checks enable row level security;
create policy nap_checks_select on nap_checks
  for select using (
    exists (select 1 from nap_sessions s where s.id = session_id and has_childcare_office_access(s.office_id))
  );

-- 5) 監査トリガ
do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'nap_sessions'
  );
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'nap_checks'
  );
end $$;
