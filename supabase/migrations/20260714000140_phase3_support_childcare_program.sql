-- 追加機能 Phase 3: 支援保育事業。
-- 参照: docs/Ohana_Works_追加機能_実装指示書_v1_2026-07-28.md §5 Phase 3、
--       docs/Ohana_Works_追加機能_個別目標・架け橋・支援保育_設計指示書案.md §6。
-- 様式1・様式2の技術検証(document_templates登録・Excel出力)はユーザー確認済み(合格)。
-- 本マイグレーションはその技術検証を土台に、データモデル・権限・RPC本体を構築する。
--
-- 権限マッピング(D1/D2踏襲):
--   作成・編集(担任・支援担当者) = has_childcare_office_access(office_id) を再利用
--     (保育業務職員側ドメイン。個別目標シートのようなHR系権限とは分離する)
--   主任確認(chief_check) = is_support_childcare_chief(office_id)
--     (chief/office_manager/director/system_adminの職員ロール。Phase2と同じロール対応表)
--   複数名確認(multi_person_confirm) = is_support_childcare_chief(office_id)
--     または is_support_childcare_confirmer(program_office_id)(支援児童確認担当者)
--   最終承認 = is_support_childcare_office_approver(office_id)
--     (support_childcare_office_approversで施設ごとに直接指定。初期データは今回投入しない
--      — 実在職員の指定はPhase2と同様、事前確認を得てから別途投入する)
--
-- AI下書き(generate_support_childcare_form2_term_draft)はモック実装。ai_runs.providerに
-- 'mock' を記録し、Anthropic Console契約完了までは実API接続を行わない。
-- 様式2の「子どもの姿」は様式1の項目4(チェック結果)を根拠として必ず参照し、
-- ai_run_evidence_linksでそのチェック行へリンクする(ユーザー確認済み要件)。
-- 様式1側が未入力の場合は生成を拒否せず、出力に明示的な注記を付与する。
--
-- record_ai_run_decision はai_runs全体で共有できる汎用RPC(D3の共通基盤方針に準拠)。

-- ============================================================
-- 1) チェック項目マスタ(様式1の方針・補助金使途・子どもの姿。原本xlsxの文言をそのまま使用)
-- ============================================================
create table support_childcare_form1_check_items (
  id uuid primary key default gen_random_uuid(),
  check_group text not null check (check_group in ('policy_stance', 'subsidy_use', 'child_behavior')),
  category text,
  label text not null,
  is_other_option boolean not null default false,
  sort_order int not null,
  created_at timestamptz not null default now()
);

insert into support_childcare_form1_check_items (check_group, category, label, is_other_option, sort_order) values
  ('policy_stance', null, '加配保育士を配置し、支援を行う予定', false, 1),
  ('policy_stance', null, '加配保育士の配置はできないが、相談や療育につなげる予定', false, 2),
  ('policy_stance', null, '相談や療育につながっているが、加配保育士の配置はできていない', false, 3),
  ('policy_stance', null, '保育士配置は行っているが、加配申請していない', false, 4),
  ('subsidy_use', null, '保育にあたる保育士や、保育補助員が増えることで、対象児童に個別に寄り添った保育ができる。', false, 1),
  ('subsidy_use', null, '保育にあたる保育士をサポートするための職員等が増え、対象児童の保育にかける時間が増える。', false, 2),
  ('subsidy_use', null, '必要な物品等の購入ができ、より対象児童に適した環境を確保できる。', false, 3),
  ('subsidy_use', null, '施設内での研修や、保護者面談の機会の確保のために使われる等、関係機関との連携強化ができる。', false, 4),
  ('subsidy_use', null, 'その他', true, 5),
  ('child_behavior', '人間関係', '相手が泣いて嫌がったり怒っていても自分の行動をやめようとせず、トラブルになる。', false, 1),
  ('child_behavior', '人間関係', '一斉保育など集団活動に誘っても関心を示さず参加しない。（例：活動の意味がわからない、集団が苦手、今の遊びがやめられないなど）', false, 2),
  ('child_behavior', '人間関係', '危険な事をしないように何度伝えても繰り返す。', false, 3),
  ('child_behavior', '人間関係', '力の加減が難しかったり、手足や体の動きが不自然で物や人にぶつかりやすく、危険を伴ったりトラブルになる。', false, 4),
  ('child_behavior', '言葉・表現', '発語がみられない、言葉の数が極端に少ないなどコミュニケーションがとりづらい。', false, 5),
  ('child_behavior', '言葉・表現', '「やめて」「貸して」など自分の気持ちをうまく言葉で伝えられない。（例：言葉のかわりに、黙り込む、その場からいなくなる又はかみつく、押すなどの衝動的な行動をとるなど）', false, 6),
  ('child_behavior', '言葉・表現', 'たたく、蹴るなど、周囲の人を傷つけたり物を壊したりする。', false, 7),
  ('child_behavior', '言葉・表現', '壁に頭をぶつける、髪の毛を抜くなど、自分の体を傷つけることがある。', false, 8),
  ('child_behavior', '言葉・表現', '言葉だけの指示では理解できないため、集団生活に支障がある。', false, 9),
  ('child_behavior', '環境', '毎日の生活の流れを繰り返し伝えても身につかなかったり、集中して取り組めないため、集団生活に支障がある。', false, 10),
  ('child_behavior', '環境', '自分が興味や関心を持ったことだけに熱中する（数字や文字、形、車、電車など）ため、集団生活に支障がある。', false, 11),
  ('child_behavior', '環境', '関心が強い物や人に対して、突発的な行動をとるので、危険を伴う。', false, 12),
  ('child_behavior', '環境', '自分の好きな場所や物、やり方にこだわりがあり、切り替えができず次の行動に移れない。', false, 13),
  ('child_behavior', '環境', '急な予定変更や予想に反した状況になると、不安になったり興奮するなどのパニックになる。', false, 14),
  ('child_behavior', '環境', '音や光、臭いなどに敏感で執着したり、嫌がったりすることがあり、集団活動に参加できない。', false, 15),
  ('child_behavior', '環境', '周囲からの刺激が入りやすく、遊びや活動に集中できない。', false, 16);

-- ============================================================
-- 2) 年度・期の開設単位、施設ごとの参加状態+支援児童確認担当者
-- ============================================================
create table support_childcare_programs (
  id uuid primary key default gen_random_uuid(),
  fiscal_year int not null,
  term text not null check (term in ('前期', '後期')),
  jurisdiction text not null default '大和市',
  status text not null default 'draft' check (status in ('draft', 'open', 'closed', 'archived')),
  application_deadline date,
  target_period_start date,
  target_period_end date,
  subsidy_unit_price_per_month numeric(10, 0),
  subsidy_unit_price_special_condition_amount numeric(10, 0),
  notes text,
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (fiscal_year, term, jurisdiction)
);
create trigger trg_support_childcare_programs_updated_at before update on support_childcare_programs
  for each row execute function set_updated_at();

create table support_childcare_program_offices (
  id uuid primary key default gen_random_uuid(),
  program_id uuid not null references support_childcare_programs(id) on delete cascade,
  office_id uuid not null references offices(id),
  confirmer_employee_id uuid references employees(id),
  status text not null default 'not_started' check (status in ('not_started', 'in_progress', 'submitted', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (program_id, office_id)
);
create trigger trg_support_childcare_program_offices_updated_at before update on support_childcare_program_offices
  for each row execute function set_updated_at();

-- ============================================================
-- 3) 対象候補
-- ============================================================
create table support_childcare_candidates (
  id uuid primary key default gen_random_uuid(),
  program_office_id uuid not null references support_childcare_program_offices(id) on delete cascade,
  child_id uuid not null references children(id),
  class_id uuid references childcare_classes(id),
  candidacy_status text not null default 'candidate'
    check (candidacy_status in ('candidate', 'under_review', 'submission_target', 'excluded')),
  exclusion_reason text,
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (program_office_id, child_id)
);
create trigger trg_support_childcare_candidates_updated_at before update on support_childcare_candidates
  for each row execute function set_updated_at();

-- ============================================================
-- 4) 申請本体(様式1・2・提出票をまとめる承認ワークフロー単位)
-- ============================================================
create table support_childcare_applications (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null unique references support_childcare_candidates(id),
  status text not null default 'draft'
    check (status in ('draft', 'ai_draft', 'in_review', 'returned', 'approved', 'finalized', 'released', 'superseded', 'archived')),
  version int not null default 1,
  supersedes_id uuid references support_childcare_applications(id),
  snapshot jsonb,
  author_id uuid references employees(id),
  approver_id uuid references employees(id),
  approved_at timestamptz,
  finalized_at timestamptz,
  released_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_support_childcare_applications_updated_at before update on support_childcare_applications
  for each row execute function set_updated_at();

-- 主任確認・複数名確認(園長含む)の記録。1人1行、複数人が同じ申請に確認を残せる。
create table support_childcare_application_reviews (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references support_childcare_applications(id) on delete cascade,
  reviewer_id uuid not null references employees(id),
  review_type text not null check (review_type in ('chief_check', 'multi_person_confirm')),
  action text not null check (action in ('approved', 'returned')),
  comment text,
  reviewed_at timestamptz not null default now()
);
create index idx_support_childcare_application_reviews_app on support_childcare_application_reviews(application_id);

-- 施設ごとの最終承認者指定(roleを経由しない直接指定。Phase2と同型)
create table support_childcare_office_approvers (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null unique references offices(id),
  approver_employee_id uuid not null references employees(id),
  updated_by uuid references employees(id),
  updated_at timestamptz not null default now()
);
create trigger trg_support_childcare_office_approvers_updated_at before update on support_childcare_office_approvers
  for each row execute function set_updated_at();

-- ============================================================
-- 5) 様式1
-- ============================================================
create table support_childcare_form1 (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null unique references support_childcare_applications(id) on delete cascade,
  recorded_on date,
  class_size_3 int,
  class_size_4 int,
  class_size_5 int,
  extra_staff_count_3 int,
  extra_staff_count_4 int,
  extra_staff_count_5 int,
  staff_count int,
  notes text,
  policy_stance_item_id uuid references support_childcare_form1_check_items(id),
  policy_target_month text,
  policy_no_extra_staff_reason text,
  policy_no_application_reason text,
  subsidy_expected_effect text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_support_childcare_form1_updated_at before update on support_childcare_form1
  for each row execute function set_updated_at();

create table support_childcare_form1_checks (
  id uuid primary key default gen_random_uuid(),
  form1_id uuid not null references support_childcare_form1(id) on delete cascade,
  check_item_id uuid not null references support_childcare_form1_check_items(id),
  created_at timestamptz not null default now(),
  unique (form1_id, check_item_id)
);

create table support_childcare_use_plans (
  id uuid primary key default gen_random_uuid(),
  form1_id uuid not null references support_childcare_form1(id) on delete cascade,
  check_item_id uuid not null references support_childcare_form1_check_items(id),
  other_detail text,
  created_at timestamptz not null default now(),
  unique (form1_id, check_item_id)
);

-- ============================================================
-- 6) 様式2(様式1項目4との連関: form2_termsはform1_idを直接持つ)
-- ============================================================
create table support_childcare_form2 (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null unique references support_childcare_applications(id) on delete cascade,
  annual_goal text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_support_childcare_form2_updated_at before update on support_childcare_form2
  for each row execute function set_updated_at();

create table support_childcare_form2_terms (
  id uuid primary key default gen_random_uuid(),
  form2_id uuid not null references support_childcare_form2(id) on delete cascade,
  form1_id uuid not null references support_childcare_form1(id),
  term_number int not null check (term_number between 1 and 4),
  term_goal text,
  child_behavior text,
  considered_factors text,
  support_measures text,
  evaluation text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (form2_id, term_number)
);
create trigger trg_support_childcare_form2_terms_updated_at before update on support_childcare_form2_terms
  for each row execute function set_updated_at();

-- ============================================================
-- 7) 保護者面談・関係機関連携ログ(複数回記録可能)
-- ============================================================
create table support_childcare_guardian_meetings (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references support_childcare_applications(id) on delete cascade,
  meeting_date date not null,
  meeting_type text not null default 'formal' check (meeting_type in ('formal', 'pickup_dropoff_note')),
  attendee text,
  content text,
  guardian_intention text,
  recorded_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_support_childcare_guardian_meetings_updated_at before update on support_childcare_guardian_meetings
  for each row execute function set_updated_at();

create table support_childcare_agency_links (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references support_childcare_applications(id) on delete cascade,
  agency_type text not null check (agency_type in (
    'patrol_consultation', 'developmental_consultation',
    'child_development_support_office', 'facility_visit_support'
  )),
  contact_person text,
  consultation_date date,
  enrollment_start_date date,
  frequency text,
  content text,
  support_outcome text,
  recorded_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_support_childcare_agency_links_updated_at before update on support_childcare_agency_links
  for each row execute function set_updated_at();

-- ============================================================
-- 8) 提出後追跡(受領確認票・市訪問・対象児数確認表・請求。実様式未確認のため
-- 日付+自由記述+状態のみで統合的に追跡する。実様式判明後に正式テーブルへ差し替える)
-- ============================================================
create table support_childcare_followups (
  id uuid primary key default gen_random_uuid(),
  program_office_id uuid not null references support_childcare_program_offices(id) on delete cascade,
  followup_type text not null check (followup_type in ('receipt', 'city_visit', 'confirmation_sheet', 'claim')),
  event_date date,
  status text not null default 'pending' check (status in ('pending', 'recorded', 'completed')),
  notes text,
  recorded_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_support_childcare_followups_updated_at before update on support_childcare_followups
  for each row execute function set_updated_at();

-- ============================================================
-- 9) 確定時の出力記録(D4のexports系パターン踏襲)
-- ============================================================
create table support_childcare_exports (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references support_childcare_applications(id) on delete cascade,
  export_type text not null check (export_type in ('form1', 'form2', 'submission_form', 'cover_sheet', 'package')),
  template_id uuid references document_templates(id),
  template_version int,
  storage_path text,
  file_hash text,
  generated_by uuid references employees(id),
  generated_at timestamptz not null default now()
);
create index idx_support_childcare_exports_app on support_childcare_exports(application_id);

-- ============================================================
-- 権限判定関数
-- ============================================================
create or replace function is_support_childcare_chief(target_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from employee_roles er
    join roles r on r.id = er.role_id
    where er.employee_id = my_employee_id()
      and r.code in ('chief', 'office_manager', 'director', 'system_admin')
      and (er.office_id is null or er.office_id = target_office_id)
  );
$$;

create or replace function is_support_childcare_confirmer(target_program_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from support_childcare_program_offices po
    where po.id = target_program_office_id and po.confirmer_employee_id = my_employee_id()
  ) or exists (
    select 1 from employee_roles er join roles r on r.id = er.role_id
    where er.employee_id = my_employee_id() and r.code = 'system_admin'
  );
$$;

create or replace function is_support_childcare_office_approver(target_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from support_childcare_office_approvers a
    where a.office_id = target_office_id and a.approver_employee_id = my_employee_id()
  ) or exists (
    select 1 from employee_roles er join roles r on r.id = er.role_id
    where er.employee_id = my_employee_id() and r.code = 'system_admin'
  );
$$;

-- application_id から office_id を解決する内部ヘルパー(RLS・RPCで多用するため)
create or replace function support_childcare_application_office_id(target_application_id uuid)
returns uuid
language sql stable security definer set search_path = public
as $$
  select po.office_id
  from support_childcare_applications a
  join support_childcare_candidates c on c.id = a.candidate_id
  join support_childcare_program_offices po on po.id = c.program_office_id
  where a.id = target_application_id;
$$;

-- ============================================================
-- RLS: deny-all書き込み、SELECTのみポリシー(書き込みはSECURITY DEFINER RPC経由)
-- ============================================================
alter table support_childcare_form1_check_items enable row level security;
create policy support_childcare_form1_check_items_select on support_childcare_form1_check_items
  for select using (true);

alter table support_childcare_programs enable row level security;
create policy support_childcare_programs_select on support_childcare_programs
  for select using (
    exists (
      select 1 from support_childcare_program_offices po
      where po.program_id = support_childcare_programs.id
        and (has_childcare_office_access(po.office_id) or is_support_childcare_office_approver(po.office_id))
    ) or is_system_admin()
  );

alter table support_childcare_program_offices enable row level security;
create policy support_childcare_program_offices_select on support_childcare_program_offices
  for select using (
    has_childcare_office_access(office_id) or is_support_childcare_office_approver(office_id) or is_system_admin()
  );

alter table support_childcare_candidates enable row level security;
create policy support_childcare_candidates_select on support_childcare_candidates
  for select using (
    exists (
      select 1 from support_childcare_program_offices po
      where po.id = support_childcare_candidates.program_office_id
        and (has_childcare_office_access(po.office_id) or is_support_childcare_office_approver(po.office_id))
    )
  );

alter table support_childcare_applications enable row level security;
create policy support_childcare_applications_select on support_childcare_applications
  for select using (
    has_childcare_office_access(support_childcare_application_office_id(id))
    or is_support_childcare_office_approver(support_childcare_application_office_id(id))
  );

alter table support_childcare_application_reviews enable row level security;
create policy support_childcare_application_reviews_select on support_childcare_application_reviews
  for select using (
    has_childcare_office_access(support_childcare_application_office_id(application_id))
    or is_support_childcare_office_approver(support_childcare_application_office_id(application_id))
  );

alter table support_childcare_office_approvers enable row level security;
create policy support_childcare_office_approvers_select on support_childcare_office_approvers
  for select using (has_childcare_office_access(office_id) or is_system_admin());
create policy support_childcare_office_approvers_write_system_admin on support_childcare_office_approvers
  for all using (is_system_admin()) with check (is_system_admin());

alter table support_childcare_form1 enable row level security;
create policy support_childcare_form1_select on support_childcare_form1
  for select using (
    has_childcare_office_access(support_childcare_application_office_id(application_id))
    or is_support_childcare_office_approver(support_childcare_application_office_id(application_id))
  );

alter table support_childcare_form1_checks enable row level security;
create policy support_childcare_form1_checks_select on support_childcare_form1_checks
  for select using (
    exists (
      select 1 from support_childcare_form1 f1
      where f1.id = support_childcare_form1_checks.form1_id
        and (
          has_childcare_office_access(support_childcare_application_office_id(f1.application_id))
          or is_support_childcare_office_approver(support_childcare_application_office_id(f1.application_id))
        )
    )
  );

alter table support_childcare_use_plans enable row level security;
create policy support_childcare_use_plans_select on support_childcare_use_plans
  for select using (
    exists (
      select 1 from support_childcare_form1 f1
      where f1.id = support_childcare_use_plans.form1_id
        and (
          has_childcare_office_access(support_childcare_application_office_id(f1.application_id))
          or is_support_childcare_office_approver(support_childcare_application_office_id(f1.application_id))
        )
    )
  );

alter table support_childcare_form2 enable row level security;
create policy support_childcare_form2_select on support_childcare_form2
  for select using (
    has_childcare_office_access(support_childcare_application_office_id(application_id))
    or is_support_childcare_office_approver(support_childcare_application_office_id(application_id))
  );

alter table support_childcare_form2_terms enable row level security;
create policy support_childcare_form2_terms_select on support_childcare_form2_terms
  for select using (
    exists (
      select 1 from support_childcare_form2 f2
      where f2.id = support_childcare_form2_terms.form2_id
        and (
          has_childcare_office_access(support_childcare_application_office_id(f2.application_id))
          or is_support_childcare_office_approver(support_childcare_application_office_id(f2.application_id))
        )
    )
  );

alter table support_childcare_guardian_meetings enable row level security;
create policy support_childcare_guardian_meetings_select on support_childcare_guardian_meetings
  for select using (
    has_childcare_office_access(support_childcare_application_office_id(application_id))
    or is_support_childcare_office_approver(support_childcare_application_office_id(application_id))
  );

alter table support_childcare_agency_links enable row level security;
create policy support_childcare_agency_links_select on support_childcare_agency_links
  for select using (
    has_childcare_office_access(support_childcare_application_office_id(application_id))
    or is_support_childcare_office_approver(support_childcare_application_office_id(application_id))
  );

alter table support_childcare_followups enable row level security;
create policy support_childcare_followups_select on support_childcare_followups
  for select using (
    exists (
      select 1 from support_childcare_program_offices po
      where po.id = support_childcare_followups.program_office_id
        and (has_childcare_office_access(po.office_id) or is_support_childcare_office_approver(po.office_id))
    )
  );

alter table support_childcare_exports enable row level security;
create policy support_childcare_exports_select on support_childcare_exports
  for select using (
    has_childcare_office_access(support_childcare_application_office_id(application_id))
    or is_support_childcare_office_approver(support_childcare_application_office_id(application_id))
  );

-- ============================================================
-- 監査ログ
-- ============================================================
do $$
declare
  t text;
  audited_tables text[] := array[
    'support_childcare_programs', 'support_childcare_program_offices',
    'support_childcare_candidates', 'support_childcare_applications',
    'support_childcare_application_reviews', 'support_childcare_office_approvers',
    'support_childcare_form1', 'support_childcare_form1_checks', 'support_childcare_use_plans',
    'support_childcare_form2', 'support_childcare_form2_terms',
    'support_childcare_guardian_meetings', 'support_childcare_agency_links',
    'support_childcare_followups', 'support_childcare_exports'
  ];
begin
  foreach t in array audited_tables loop
    execute format(
      'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
      t
    );
  end loop;
end $$;

-- ============================================================
-- RPC: 年度・期の開設(法人単位。system_adminのみ)
-- ============================================================
create or replace function create_support_childcare_program(
  p_fiscal_year int, p_term text, p_jurisdiction text,
  p_application_deadline date, p_target_period_start date, p_target_period_end date,
  p_subsidy_unit_price_per_month numeric, p_subsidy_unit_price_special_condition_amount numeric,
  p_notes text
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_program_id uuid;
begin
  if not is_system_admin() then
    raise exception 'not authorized';
  end if;

  insert into support_childcare_programs (
    fiscal_year, term, jurisdiction, status, application_deadline,
    target_period_start, target_period_end,
    subsidy_unit_price_per_month, subsidy_unit_price_special_condition_amount,
    notes, created_by
  ) values (
    p_fiscal_year, p_term, p_jurisdiction, 'open', p_application_deadline,
    p_target_period_start, p_target_period_end,
    p_subsidy_unit_price_per_month, p_subsidy_unit_price_special_condition_amount,
    p_notes, my_employee_id()
  )
  returning id into v_program_id;

  return v_program_id;
end;
$$;

-- ============================================================
-- RPC: 施設の参加開始+支援児童確認担当者の指定
-- ============================================================
create or replace function assign_support_childcare_program_office(
  p_program_id uuid, p_office_id uuid, p_confirmer_employee_id uuid
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_program_office_id uuid;
begin
  if not is_support_childcare_chief(p_office_id) then
    raise exception 'not authorized';
  end if;

  insert into support_childcare_program_offices (program_id, office_id, confirmer_employee_id, status)
  values (p_program_id, p_office_id, p_confirmer_employee_id, 'in_progress')
  on conflict (program_id, office_id) do update set confirmer_employee_id = excluded.confirmer_employee_id
  returning id into v_program_office_id;

  return v_program_office_id;
end;
$$;

-- ============================================================
-- RPC: 対象候補プール(在籍中の3〜5歳児クラス園児で、まだ候補登録されていない児童)
-- ============================================================
create or replace function fetch_support_childcare_candidate_pool(p_program_office_id uuid)
returns table (child_id uuid, child_name text, class_id uuid, class_name text, age_group text)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_office_id uuid;
begin
  select po.office_id into v_office_id from support_childcare_program_offices po where po.id = p_program_office_id;
  if v_office_id is null then
    raise exception 'program office not found';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  return query
  select c.id, c.display_name, cc.id, cc.class_name, cc.age_group
  from children c
  join child_class_enrollments cce on cce.child_id = c.id and cce.effective_end_date is null
  join childcare_classes cc on cc.id = cce.class_id
  where cc.office_id = v_office_id
    and c.enrollment_status = '在籍中'
    and not exists (
      select 1 from support_childcare_candidates cand
      where cand.program_office_id = p_program_office_id and cand.child_id = c.id
    )
  order by c.display_name;
end;
$$;

-- ============================================================
-- RPC: 対象候補の追加・状態更新
-- ============================================================
create or replace function add_support_childcare_candidate(
  p_program_office_id uuid, p_child_id uuid, p_class_id uuid
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_candidate_id uuid;
begin
  select po.office_id into v_office_id from support_childcare_program_offices po where po.id = p_program_office_id;
  if v_office_id is null then
    raise exception 'program office not found';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  insert into support_childcare_candidates (program_office_id, child_id, class_id, created_by)
  values (p_program_office_id, p_child_id, p_class_id, my_employee_id())
  returning id into v_candidate_id;

  return v_candidate_id;
end;
$$;

create or replace function update_support_childcare_candidate_status(
  p_candidate_id uuid, p_status text, p_exclusion_reason text
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
begin
  select po.office_id into v_office_id
  from support_childcare_candidates c
  join support_childcare_program_offices po on po.id = c.program_office_id
  where c.id = p_candidate_id;
  if v_office_id is null then
    raise exception 'candidate not found';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;
  if p_status not in ('candidate', 'under_review', 'submission_target', 'excluded') then
    raise exception 'invalid status';
  end if;

  update support_childcare_candidates
  set candidacy_status = p_status, exclusion_reason = p_exclusion_reason
  where id = p_candidate_id;
end;
$$;

-- ============================================================
-- RPC: 申請作成(候補1件につき1申請。様式1・2の器を同時作成)
-- ============================================================
create or replace function create_support_childcare_application(p_candidate_id uuid)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_application_id uuid;
  v_form1_id uuid;
  v_form2_id uuid;
  v_term int;
begin
  select po.office_id into v_office_id
  from support_childcare_candidates c
  join support_childcare_program_offices po on po.id = c.program_office_id
  where c.id = p_candidate_id;
  if v_office_id is null then
    raise exception 'candidate not found';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  insert into support_childcare_applications (candidate_id, author_id)
  values (p_candidate_id, my_employee_id())
  returning id into v_application_id;

  insert into support_childcare_form1 (application_id)
  values (v_application_id)
  returning id into v_form1_id;

  insert into support_childcare_form2 (application_id)
  values (v_application_id)
  returning id into v_form2_id;

  for v_term in 1..4 loop
    insert into support_childcare_form2_terms (form2_id, form1_id, term_number)
    values (v_form2_id, v_form1_id, v_term);
  end loop;

  return v_application_id;
end;
$$;

-- ============================================================
-- RPC: 一覧・詳細
-- ============================================================
create or replace function fetch_support_childcare_applications(p_program_office_id uuid)
returns table (
  application_id uuid, child_id uuid, child_name text, candidacy_status text,
  status text, author_name text, approver_name text, finalized_at timestamptz
)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_office_id uuid;
begin
  select po.office_id into v_office_id from support_childcare_program_offices po where po.id = p_program_office_id;
  if v_office_id is null then
    raise exception 'program office not found';
  end if;
  if not (has_childcare_office_access(v_office_id) or is_support_childcare_office_approver(v_office_id)) then
    raise exception 'not authorized';
  end if;

  return query
  select
    a.id, cand.child_id, ch.display_name, cand.candidacy_status,
    a.status, author.name, approver.name, a.finalized_at
  from support_childcare_candidates cand
  join children ch on ch.id = cand.child_id
  left join support_childcare_applications a on a.candidate_id = cand.id
  left join employees author on author.id = a.author_id
  left join employees approver on approver.id = a.approver_id
  where cand.program_office_id = p_program_office_id
  order by ch.display_name;
end;
$$;

create or replace function fetch_support_childcare_application_detail(p_application_id uuid)
returns table (
  application_id uuid, status text, child_name text,
  form1_id uuid, form1_recorded_on date,
  form1_class_size_3 int, form1_class_size_4 int, form1_class_size_5 int,
  form1_extra_staff_count_3 int, form1_extra_staff_count_4 int, form1_extra_staff_count_5 int,
  form1_staff_count int, form1_notes text,
  form1_policy_stance_item_id uuid, form1_policy_target_month text,
  form1_policy_no_extra_staff_reason text, form1_policy_no_application_reason text,
  form1_subsidy_expected_effect text,
  form2_id uuid, form2_annual_goal text
)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_office_id uuid;
begin
  v_office_id := support_childcare_application_office_id(p_application_id);
  if v_office_id is null then
    raise exception 'application not found';
  end if;
  if not (has_childcare_office_access(v_office_id) or is_support_childcare_office_approver(v_office_id)) then
    raise exception 'not authorized';
  end if;

  return query
  select
    a.id, a.status, ch.display_name,
    f1.id, f1.recorded_on,
    f1.class_size_3, f1.class_size_4, f1.class_size_5,
    f1.extra_staff_count_3, f1.extra_staff_count_4, f1.extra_staff_count_5,
    f1.staff_count, f1.notes,
    f1.policy_stance_item_id, f1.policy_target_month,
    f1.policy_no_extra_staff_reason, f1.policy_no_application_reason,
    f1.subsidy_expected_effect,
    f2.id, f2.annual_goal
  from support_childcare_applications a
  join support_childcare_candidates cand on cand.id = a.candidate_id
  join children ch on ch.id = cand.child_id
  left join support_childcare_form1 f1 on f1.application_id = a.id
  left join support_childcare_form2 f2 on f2.application_id = a.id
  where a.id = p_application_id;
end;
$$;

-- ============================================================
-- RPC: 様式1本体更新
-- ============================================================
create or replace function update_support_childcare_form1(
  p_application_id uuid,
  p_recorded_on date,
  p_class_size_3 int, p_class_size_4 int, p_class_size_5 int,
  p_extra_staff_count_3 int, p_extra_staff_count_4 int, p_extra_staff_count_5 int,
  p_staff_count int, p_notes text,
  p_policy_stance_item_id uuid, p_policy_target_month text,
  p_policy_no_extra_staff_reason text, p_policy_no_application_reason text,
  p_subsidy_expected_effect text
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_status text;
begin
  v_office_id := support_childcare_application_office_id(p_application_id);
  if v_office_id is null then
    raise exception 'application not found';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;
  select status into v_status from support_childcare_applications where id = p_application_id;
  if v_status in ('finalized', 'released', 'superseded', 'archived') then
    raise exception 'application is % and cannot be edited', v_status;
  end if;

  update support_childcare_form1 set
    recorded_on = p_recorded_on,
    class_size_3 = p_class_size_3, class_size_4 = p_class_size_4, class_size_5 = p_class_size_5,
    extra_staff_count_3 = p_extra_staff_count_3, extra_staff_count_4 = p_extra_staff_count_4,
    extra_staff_count_5 = p_extra_staff_count_5,
    staff_count = p_staff_count, notes = p_notes,
    policy_stance_item_id = p_policy_stance_item_id, policy_target_month = p_policy_target_month,
    policy_no_extra_staff_reason = p_policy_no_extra_staff_reason,
    policy_no_application_reason = p_policy_no_application_reason,
    subsidy_expected_effect = p_subsidy_expected_effect
  where application_id = p_application_id;
end;
$$;

-- ============================================================
-- RPC: 様式1チェック項目(子どもの姿・補助金使途)の入れ替え
-- ============================================================
create or replace function update_support_childcare_form1_checks(p_form1_id uuid, p_check_item_ids uuid[])
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_application_id uuid;
  v_office_id uuid;
begin
  select application_id into v_application_id from support_childcare_form1 where id = p_form1_id;
  if v_application_id is null then
    raise exception 'form1 not found';
  end if;
  v_office_id := support_childcare_application_office_id(v_application_id);
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  delete from support_childcare_form1_checks where form1_id = p_form1_id;
  insert into support_childcare_form1_checks (form1_id, check_item_id)
  select p_form1_id, unnest(p_check_item_ids);
end;
$$;

create or replace function update_support_childcare_use_plans(
  p_form1_id uuid, p_check_item_ids uuid[], p_other_detail text
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_application_id uuid;
  v_office_id uuid;
begin
  select application_id into v_application_id from support_childcare_form1 where id = p_form1_id;
  if v_application_id is null then
    raise exception 'form1 not found';
  end if;
  v_office_id := support_childcare_application_office_id(v_application_id);
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  delete from support_childcare_use_plans where form1_id = p_form1_id;
  insert into support_childcare_use_plans (form1_id, check_item_id, other_detail)
  select p_form1_id, x.item_id, case when i.is_other_option then p_other_detail else null end
  from unnest(p_check_item_ids) as x(item_id)
  join support_childcare_form1_check_items i on i.id = x.item_id;
end;
$$;

-- ============================================================
-- RPC: 様式2本体・期別更新
-- ============================================================
create or replace function update_support_childcare_form2(p_application_id uuid, p_annual_goal text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_status text;
begin
  v_office_id := support_childcare_application_office_id(p_application_id);
  if v_office_id is null then
    raise exception 'application not found';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;
  select status into v_status from support_childcare_applications where id = p_application_id;
  if v_status in ('finalized', 'released', 'superseded', 'archived') then
    raise exception 'application is % and cannot be edited', v_status;
  end if;

  update support_childcare_form2 set annual_goal = p_annual_goal where application_id = p_application_id;
end;
$$;

create or replace function update_support_childcare_form2_term(
  p_term_id uuid, p_term_goal text, p_child_behavior text,
  p_considered_factors text, p_support_measures text, p_evaluation text
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_application_id uuid;
  v_office_id uuid;
begin
  select f2.application_id into v_application_id
  from support_childcare_form2_terms t
  join support_childcare_form2 f2 on f2.id = t.form2_id
  where t.id = p_term_id;
  if v_application_id is null then
    raise exception 'term not found';
  end if;
  v_office_id := support_childcare_application_office_id(v_application_id);
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  update support_childcare_form2_terms set
    term_goal = p_term_goal, child_behavior = p_child_behavior,
    considered_factors = p_considered_factors, support_measures = p_support_measures,
    evaluation = p_evaluation
  where id = p_term_id;
end;
$$;

-- ============================================================
-- RPC: 保護者面談・関係機関連携の記録
-- ============================================================
create or replace function record_support_childcare_guardian_meeting(
  p_application_id uuid, p_meeting_date date, p_meeting_type text,
  p_attendee text, p_content text, p_guardian_intention text
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_id uuid;
begin
  v_office_id := support_childcare_application_office_id(p_application_id);
  if v_office_id is null then
    raise exception 'application not found';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  insert into support_childcare_guardian_meetings (
    application_id, meeting_date, meeting_type, attendee, content, guardian_intention, recorded_by
  ) values (
    p_application_id, p_meeting_date, p_meeting_type, p_attendee, p_content, p_guardian_intention, my_employee_id()
  )
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function record_support_childcare_agency_link(
  p_application_id uuid, p_agency_type text, p_contact_person text,
  p_consultation_date date, p_enrollment_start_date date, p_frequency text,
  p_content text, p_support_outcome text
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_id uuid;
begin
  v_office_id := support_childcare_application_office_id(p_application_id);
  if v_office_id is null then
    raise exception 'application not found';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  insert into support_childcare_agency_links (
    application_id, agency_type, contact_person, consultation_date, enrollment_start_date,
    frequency, content, support_outcome, recorded_by
  ) values (
    p_application_id, p_agency_type, p_contact_person, p_consultation_date, p_enrollment_start_date,
    p_frequency, p_content, p_support_outcome, my_employee_id()
  )
  returning id into v_id;

  return v_id;
end;
$$;

-- ============================================================
-- RPC: AI下書き生成(様式2の期別項目。モック実装)
-- child_behaviorは様式1項目4のチェック結果を根拠として必ず参照し、
-- ai_run_evidence_linksでそのチェック行(無ければform1行そのもの)へリンクする。
-- 根拠が薄い/様式1未入力でも生成は拒否せず、出力に明示的な注記を付与する。
-- ============================================================
create or replace function generate_support_childcare_form2_term_draft(p_term_id uuid, p_field text)
returns table (ai_run_id uuid, output_text text, evidence_count int, low_evidence boolean)
language plpgsql security definer set search_path = public
as $$
declare
  v_application_id uuid;
  v_office_id uuid;
  v_form1_id uuid;
  v_child_id uuid;
  v_office_name text;
  v_check_labels text[];
  v_check_ids uuid[];
  v_journal_count int := 0;
  v_meeting_count int := 0;
  v_agency_count int := 0;
  v_evidence_count int := 0;
  v_output text;
  v_run_id uuid;
  v_form1_missing boolean := false;
begin
  if p_field not in ('child_behavior', 'considered_factors', 'support_measures', 'evaluation') then
    raise exception 'invalid field';
  end if;

  select t.form1_id, f2.application_id into v_form1_id, v_application_id
  from support_childcare_form2_terms t
  join support_childcare_form2 f2 on f2.id = t.form2_id
  where t.id = p_term_id;
  if v_application_id is null then
    raise exception 'term not found';
  end if;
  v_office_id := support_childcare_application_office_id(v_application_id);
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  select cand.child_id into v_child_id
  from support_childcare_applications a
  join support_childcare_candidates cand on cand.id = a.candidate_id
  where a.id = v_application_id;

  -- 様式1項目4(子どもの姿チェック)を根拠として収集
  select array_agg(i.label), array_agg(fc.id)
  into v_check_labels, v_check_ids
  from support_childcare_form1_checks fc
  join support_childcare_form1_check_items i on i.id = fc.check_item_id
  where fc.form1_id = v_form1_id and i.check_group = 'child_behavior';

  if v_check_labels is null or array_length(v_check_labels, 1) is null then
    v_form1_missing := true;
    v_check_labels := array[]::text[];
    v_check_ids := array[]::uuid[];
  end if;

  select count(*) into v_journal_count
  from child_personal_journals j
  where j.child_id = v_child_id;

  select count(*) into v_meeting_count
  from support_childcare_guardian_meetings m
  where m.application_id = v_application_id;

  select count(*) into v_agency_count
  from support_childcare_agency_links al
  where al.application_id = v_application_id;

  v_evidence_count := coalesce(array_length(v_check_ids, 1), 0) + v_journal_count + v_meeting_count + v_agency_count;

  -- モック応答(Anthropic Console契約完了後、この本文を実API呼び出しに置き換える)
  v_output := '【AI生成(モック)】';
  if p_field = 'child_behavior' then
    if v_form1_missing then
      v_output := v_output || '様式1の記載が無いため参考情報が限定的です。様式1の項目4を先に入力することをおすすめします。';
    else
      v_output := v_output || '様式1でチェックされた項目(' || array_to_string(v_check_labels, '／') || ')を踏まえた子どもの姿の下書きです。';
    end if;
  else
    v_output := v_output || p_field || 'の下書きです。';
  end if;
  if v_evidence_count = 0 then
    v_output := v_output || '参考情報が不足しています。内容は職員による確認・加筆を前提とした暫定的な下書きです。';
  end if;
  v_output := v_output || '(実API未接続のため仮の文章です)';

  insert into ai_runs (
    document_type, document_id, target_field, input_data,
    provider, model, prompt_version, output_text, executed_by
  ) values (
    'support_childcare_form2_term', p_term_id, p_field,
    jsonb_build_object(
      'form1_child_behavior_checks', v_check_labels,
      'journal_count', v_journal_count,
      'guardian_meeting_count', v_meeting_count,
      'agency_link_count', v_agency_count,
      'form1_missing', v_form1_missing
    ),
    'mock', 'mock', 'v0-mock', v_output, my_employee_id()
  )
  returning id into v_run_id;

  if p_field = 'child_behavior' and v_check_ids is not null then
    insert into ai_run_evidence_links (ai_run_id, evidence_table, evidence_id)
    select v_run_id, 'support_childcare_form1_checks', x
    from unnest(v_check_ids) as x;
  end if;

  ai_run_id := v_run_id;
  output_text := v_output;
  evidence_count := v_evidence_count;
  low_evidence := (v_evidence_count = 0);
  return next;
end;
$$;

-- ============================================================
-- RPC: AI下書きの採否記録(採用/編集/再生成/不採用。ai_runs全体で共有する汎用RPC)
-- ============================================================
create or replace function record_ai_run_decision(p_ai_run_id uuid, p_decision text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_document_type text;
  v_document_id uuid;
  v_office_id uuid;
  v_authorized boolean := false;
begin
  if p_decision not in ('adopted', 'edited', 'regenerated', 'discarded') then
    raise exception 'invalid decision';
  end if;

  select document_type, document_id into v_document_type, v_document_id
  from ai_runs where id = p_ai_run_id;
  if v_document_type is null then
    raise exception 'ai run not found';
  end if;

  if v_document_type = 'employee_goal_sheet' then
    select office_id into v_office_id from employee_goal_sheets where id = v_document_id;
    v_authorized := v_office_id is not null and has_goal_sheet_edit_access(v_office_id);
  elsif v_document_type = 'support_childcare_form2_term' then
    select support_childcare_application_office_id(f2.application_id) into v_office_id
    from support_childcare_form2_terms t
    join support_childcare_form2 f2 on f2.id = t.form2_id
    where t.id = v_document_id;
    v_authorized := v_office_id is not null and has_childcare_office_access(v_office_id);
  else
    raise exception 'unsupported document_type: %', v_document_type;
  end if;

  if not v_authorized then
    raise exception 'not authorized';
  end if;

  update ai_runs set decision = p_decision where id = p_ai_run_id;
end;
$$;

-- ============================================================
-- RPC: 主任確認・複数名確認(園長含む)の記録
-- ============================================================
create or replace function record_support_childcare_review(
  p_application_id uuid, p_review_type text, p_action text, p_comment text
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_program_office_id uuid;
  v_status text;
  v_authorized boolean;
begin
  if p_review_type not in ('chief_check', 'multi_person_confirm') then
    raise exception 'invalid review_type';
  end if;
  if p_action not in ('approved', 'returned') then
    raise exception 'invalid action';
  end if;

  v_office_id := support_childcare_application_office_id(p_application_id);
  if v_office_id is null then
    raise exception 'application not found';
  end if;
  select status into v_status from support_childcare_applications where id = p_application_id;
  if v_status <> 'in_review' then
    raise exception 'application is % and cannot be reviewed', v_status;
  end if;

  select cand.program_office_id into v_program_office_id
  from support_childcare_applications a
  join support_childcare_candidates cand on cand.id = a.candidate_id
  where a.id = p_application_id;

  if p_review_type = 'chief_check' then
    v_authorized := is_support_childcare_chief(v_office_id);
  else
    v_authorized := is_support_childcare_chief(v_office_id) or is_support_childcare_confirmer(v_program_office_id);
  end if;
  if not v_authorized then
    raise exception 'not authorized';
  end if;

  insert into support_childcare_application_reviews (application_id, reviewer_id, review_type, action, comment)
  values (p_application_id, my_employee_id(), p_review_type, p_action, p_comment);

  if p_action = 'returned' then
    update support_childcare_applications set status = 'returned' where id = p_application_id;
  end if;
end;
$$;

-- ============================================================
-- RPC: 提出(主任確認待ちへ)
-- ============================================================
create or replace function submit_support_childcare_application_for_review(p_application_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_status text;
begin
  v_office_id := support_childcare_application_office_id(p_application_id);
  if v_office_id is null then
    raise exception 'application not found';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;
  select status into v_status from support_childcare_applications where id = p_application_id;
  if v_status not in ('draft', 'ai_draft', 'returned') then
    raise exception 'application is % and cannot be submitted', v_status;
  end if;

  update support_childcare_applications set status = 'in_review' where id = p_application_id;
end;
$$;

-- ============================================================
-- RPC: 最終承認(施設ごとの承認者指定テーブルで判定)。主任確認+複数名確認の
-- 両方が完了していることを必須とする(原案§6.9の複数名確認要件)。
-- ============================================================
create or replace function approve_support_childcare_application_final(
  p_application_id uuid, p_action text, p_comment text
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_status text;
  v_chief_checked boolean;
  v_multi_confirmed boolean;
begin
  if p_action not in ('approved', 'returned') then
    raise exception 'invalid action';
  end if;
  v_office_id := support_childcare_application_office_id(p_application_id);
  if v_office_id is null then
    raise exception 'application not found';
  end if;
  if not is_support_childcare_office_approver(v_office_id) then
    raise exception 'not authorized';
  end if;
  select status into v_status from support_childcare_applications where id = p_application_id;
  if v_status <> 'in_review' then
    raise exception 'application is % and cannot be finally approved', v_status;
  end if;

  select exists (
    select 1 from support_childcare_application_reviews r
    where r.application_id = p_application_id and r.review_type = 'chief_check' and r.action = 'approved'
  ) into v_chief_checked;
  select exists (
    select 1 from support_childcare_application_reviews r
    where r.application_id = p_application_id and r.review_type = 'multi_person_confirm' and r.action = 'approved'
  ) into v_multi_confirmed;
  if not v_chief_checked then
    raise exception '主任確認が完了していません';
  end if;
  if not v_multi_confirmed then
    raise exception '複数名確認が完了していません';
  end if;

  insert into support_childcare_application_reviews (application_id, reviewer_id, review_type, action, comment)
  values (p_application_id, my_employee_id(), 'multi_person_confirm', p_action, p_comment);

  if p_action = 'returned' then
    update support_childcare_applications set status = 'returned' where id = p_application_id;
  else
    update support_childcare_applications
    set status = 'approved', approver_id = my_employee_id(), approved_at = now()
    where id = p_application_id;
  end if;
end;
$$;

-- ============================================================
-- RPC: 確定(スナップショット凍結)
-- ============================================================
create or replace function finalize_support_childcare_application(p_application_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_status text;
  v_snapshot jsonb;
begin
  v_office_id := support_childcare_application_office_id(p_application_id);
  if v_office_id is null then
    raise exception 'application not found';
  end if;
  if not (has_childcare_office_access(v_office_id) or is_support_childcare_office_approver(v_office_id)) then
    raise exception 'not authorized';
  end if;
  select status into v_status from support_childcare_applications where id = p_application_id;
  if v_status <> 'approved' then
    raise exception 'application is % and cannot be finalized', v_status;
  end if;

  select jsonb_build_object(
    'child_name', ch.display_name,
    'form1', to_jsonb(f1.*),
    'form2', to_jsonb(f2.*),
    'form2_terms', (
      select jsonb_agg(to_jsonb(t.*)) from support_childcare_form2_terms t where t.form2_id = f2.id
    )
  ) into v_snapshot
  from support_childcare_applications a
  join support_childcare_candidates cand on cand.id = a.candidate_id
  join children ch on ch.id = cand.child_id
  left join support_childcare_form1 f1 on f1.application_id = a.id
  left join support_childcare_form2 f2 on f2.application_id = a.id
  where a.id = p_application_id;

  update support_childcare_applications
  set status = 'finalized', finalized_at = now(), snapshot = v_snapshot
  where id = p_application_id;
end;
$$;

-- ============================================================
-- RPC: 提出票の自動集計(読み取り専用、保存はしない)
-- ============================================================
create or replace function fetch_support_childcare_submission_summary(p_program_office_id uuid)
returns table (age_3_count int, age_4_count int, age_5_count int, total_count int)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_office_id uuid;
begin
  select po.office_id into v_office_id from support_childcare_program_offices po where po.id = p_program_office_id;
  if v_office_id is null then
    raise exception 'program office not found';
  end if;
  if not (has_childcare_office_access(v_office_id) or is_support_childcare_office_approver(v_office_id)) then
    raise exception 'not authorized';
  end if;

  return query
  select
    count(*) filter (where substring(cc.age_group from '(\d)歳') = '3')::int,
    count(*) filter (where substring(cc.age_group from '(\d)歳') = '4')::int,
    count(*) filter (where substring(cc.age_group from '(\d)歳') = '5')::int,
    count(*)::int
  from support_childcare_candidates cand
  join support_childcare_applications a on a.candidate_id = cand.id
  left join childcare_classes cc on cc.id = cand.class_id
  where cand.program_office_id = p_program_office_id and cand.candidacy_status = 'submission_target';
end;
$$;

-- ============================================================
-- RPC: 提出後追跡(受領確認票・市訪問・対象児数確認表・請求)
-- ============================================================
create or replace function record_support_childcare_followup(
  p_program_office_id uuid, p_followup_type text, p_event_date date, p_status text, p_notes text
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_id uuid;
begin
  select po.office_id into v_office_id from support_childcare_program_offices po where po.id = p_program_office_id;
  if v_office_id is null then
    raise exception 'program office not found';
  end if;
  if not is_support_childcare_chief(v_office_id) then
    raise exception 'not authorized';
  end if;
  if p_followup_type not in ('receipt', 'city_visit', 'confirmation_sheet', 'claim') then
    raise exception 'invalid followup_type';
  end if;
  if p_status not in ('pending', 'recorded', 'completed') then
    raise exception 'invalid status';
  end if;

  insert into support_childcare_followups (program_office_id, followup_type, event_date, status, notes, recorded_by)
  values (p_program_office_id, p_followup_type, p_event_date, p_status, p_notes, my_employee_id())
  returning id into v_id;

  return v_id;
end;
$$;

-- ============================================================
-- document_templates: 様式1・2の技術検証合格(ユーザー確認済み)につき active へ更新
-- ============================================================
update document_templates
set status = 'active'
where template_key in ('support_childcare_form1', 'support_childcare_form2')
  and fiscal_year = 2026 and term = '前期' and version = 1;

-- ============================================================
-- 施設ごとの最終承認者の初期データ(2026-07-30 ユーザー確認済み。個別目標シートの
-- 承認者指定テーブルと同じ人選。該当職員が存在しない環境では何もしない
-- — マイグレーションを環境非依存に保つため、存在チェックを必須にする)
-- ============================================================
insert into support_childcare_office_approvers (office_id, approver_employee_id)
select o.id, '338b0302-05f1-4c61-99da-755a3ddc8e3b'::uuid -- 大原利奈
from offices o
where o.name = '大和オハナ保育園'
  and exists (select 1 from employees e where e.id = '338b0302-05f1-4c61-99da-755a3ddc8e3b'::uuid)
union all
select o.id, '720133bb-d7b4-4238-a297-ce672f89cec5'::uuid -- 髙木俊
from offices o
where o.name in ('BABY MAHALO', 'Mahalo Station', 'Halelea')
  and exists (select 1 from employees e where e.id = '720133bb-d7b4-4238-a297-ce672f89cec5'::uuid)
on conflict (office_id) do nothing;
