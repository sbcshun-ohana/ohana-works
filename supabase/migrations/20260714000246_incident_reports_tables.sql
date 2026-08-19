-- 246: ヒヤリハット・事故報告 Phase A ①(データモデル)。設計指示書v2 §2/§6準拠。
-- 3区分(hiyari/minor/hospital)を1テーブルで扱い、種別で使う子テーブル/欄が変わる。
-- 受診記録は俊回答§7①に従い「v1の選択式」を採用 → incident_lookup_options に med_* 種別を持たせる。
-- RLS・機能フラグ・RPC・seed は後続migration(②③④)。本migrationは表と索引のみ。

-- ルックアップ選択肢(施設共通・kind別。管理は管理者以上=③のRPC)
create table incident_lookup_options (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in (
    'place',            -- 発生場所
    'injury_site',      -- 受傷部位
    'med_department',   -- 診察科(受診記録・選択式)
    'med_exam',         -- 受診内容
    'med_treatment',    -- 処置内容
    'med_prescription'  -- 処方薬
  )),
  label text not null,
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_incident_lookup_options_kind on incident_lookup_options(kind, sort_order) where is_active;
create trigger trg_incident_lookup_options_updated_at
  before update on incident_lookup_options for each row execute function set_updated_at();

-- 報告書本体
create table incident_reports (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id),
  report_type text not null check (report_type in ('hiyari', 'minor', 'hospital')),
  status text not null default 'draft'
    check (status in ('draft', 'submitted', 'chief_approved', 'approved')),

  -- 基本情報
  occurred_on date not null,
  occurred_at time,  -- 発生時間(申請時に必須化=RPC側で検証)
  place_option_id uuid references incident_lookup_options(id),
  place_other text check (char_length(place_other) <= 100),

  -- 発生状況(4分割・各200字)
  situation_when   text check (char_length(situation_when)   <= 200),
  situation_where  text check (char_length(situation_where)  <= 200),
  situation_what   text check (char_length(situation_what)   <= 200),
  situation_result text check (char_length(situation_result) <= 200),

  -- 現場の人員(jsonb: hoiku/jido/witness)
  staff_counts jsonb not null default '{}'::jsonb,

  -- 原因・問題点(jsonb 4キー: child_behavior/environment/objects/care_rules・各300字)
  causes jsonb not null default '{}'::jsonb,

  -- 発生後の対応(事故報告書のみ)
  injury_site_option_id uuid references incident_lookup_options(id),
  injury_detail text check (char_length(injury_detail) <= 200),
  first_aid     text check (char_length(first_aid)     <= 200),

  -- 再発防止(必須)/その他(任意)
  prevention_text text check (char_length(prevention_text) <= 300),
  note_text       text check (char_length(note_text)       <= 300),

  -- 承認フロー(2段階)
  created_by uuid not null references employees(id),
  submitted_at timestamptz,
  chief_approved_by uuid references employees(id),
  chief_approved_at timestamptz,
  approved_by uuid references employees(id),
  approved_at timestamptz,
  rejected_reason text,

  -- クロージング追跡(Phase Bで運用。作成時: 事故報告書2種のみ open)
  closure_status text check (closure_status in ('open', 'closed')),
  closed_by uuid references employees(id),
  closed_at timestamptz,
  closure_note text,
  closure_reopened_by uuid references employees(id),
  closure_reopened_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_incident_reports_office_status on incident_reports(office_id, status);
create index idx_incident_reports_approved_at on incident_reports(approved_at);          -- 週次抽出(C)
create index idx_incident_reports_closure on incident_reports(closure_status, occurred_on); -- 未クローズ検出(B)
create trigger trg_incident_reports_updated_at
  before update on incident_reports for each row execute function set_updated_at();

-- 対象園児(複数)。氏名・クラスは作成時点のスナップショット(退園後の表示崩れ防止)
create table incident_report_children (
  id uuid primary key default gen_random_uuid(),
  incident_report_id uuid not null references incident_reports(id) on delete cascade,
  child_id uuid not null references children(id),
  child_name_snapshot text,
  class_name_snapshot text,
  created_at timestamptz not null default now(),
  unique (incident_report_id, child_id)
);
create index idx_incident_report_children_report on incident_report_children(incident_report_id);

-- 現場写真(privateバケット+署名URL。keyのみ保持)
create table incident_report_photos (
  id uuid primary key default gen_random_uuid(),
  incident_report_id uuid not null references incident_reports(id) on delete cascade,
  storage_key text not null,
  sort_order int not null default 0,
  uploaded_by uuid references employees(id),
  created_at timestamptz not null default now()
);
create index idx_incident_report_photos_report on incident_report_photos(incident_report_id);

-- 経過と観察記録(複数行)
create table incident_report_progress_logs (
  id uuid primary key default gen_random_uuid(),
  incident_report_id uuid not null references incident_reports(id) on delete cascade,
  logged_at timestamptz not null,
  staff_employee_id uuid references employees(id),
  report_kind text check (report_kind in ('ok', 'other')),  -- 大丈夫です / その他
  report_text text check (char_length(report_text) <= 200),
  created_by uuid references employees(id),
  created_at timestamptz not null default now()
);
create index idx_incident_report_progress_report on incident_report_progress_logs(incident_report_id, logged_at);

-- 保護者連絡(複数行・クロージング追跡の一次データ)
create table incident_report_guardian_contacts (
  id uuid primary key default gen_random_uuid(),
  incident_report_id uuid not null references incident_reports(id) on delete cascade,
  contacted_at timestamptz not null,
  staff_employee_id uuid references employees(id),
  contact_book_written boolean,                              -- 連絡帳の記入(有/無)
  reaction_kind text check (reaction_kind in ('understood', 'other')), -- ご理解いただけた / その他
  reaction_text text check (char_length(reaction_text) <= 200),
  created_by uuid references employees(id),
  created_at timestamptz not null default now()
);
create index idx_incident_report_guardian_report on incident_report_guardian_contacts(incident_report_id, contacted_at);

-- 受診記録(病院搬送のみ・複数追加可・選択式=§7①)
create table incident_report_medical_visits (
  id uuid primary key default gen_random_uuid(),
  incident_report_id uuid not null references incident_reports(id) on delete cascade,
  medical_institution text,
  doctor_name text,
  department_option_id uuid references incident_lookup_options(id),  -- 診察科(単一)
  exam_option_ids uuid[] not null default '{}',                     -- 受診内容(複数)
  treatment_option_ids uuid[] not null default '{}',                -- 処置内容(複数)
  exam_detail text check (char_length(exam_detail) <= 400),         -- 診察・処置の補足自由記述
  doctor_instruction text check (doctor_instruction in ('can_attend', 'cannot_attend')), -- 登園可/不可
  prescription_present boolean,
  prescription_option_ids uuid[] not null default '{}',            -- 処方薬(複数)
  prescription_detail text,
  treatment_period text,
  created_by uuid references employees(id),
  created_at timestamptz not null default now()
);
create index idx_incident_report_medical_report on incident_report_medical_visits(incident_report_id);

-- 保育課連絡(病院搬送・任意。将来の行政様式の一次情報)
create table incident_report_childcare_dept_contacts (
  id uuid primary key default gen_random_uuid(),
  incident_report_id uuid not null references incident_reports(id) on delete cascade,
  contacted_at timestamptz not null,
  contacted_to text,
  content text,
  created_by uuid references employees(id),
  created_at timestamptz not null default now()
);
create index idx_incident_report_dept_report on incident_report_childcare_dept_contacts(incident_report_id);

comment on table incident_reports is
  'ヒヤリハット・事故報告(246・設計v2)。3区分1テーブル。承認2段階(status)とクロージング(closure_status)は独立軸。保護者非表示。';
