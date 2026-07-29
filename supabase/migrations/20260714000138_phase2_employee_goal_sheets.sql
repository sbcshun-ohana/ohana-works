-- 追加機能 Phase 2: 個別目標シート。
-- 参照: docs/Ohana_Works_追加機能_実装指示書_v1_2026-07-28.md §5 Phase 2, D2, D4。
-- 原案§4が要件の正。承認フロー・権限はこの機能専用に実装する(D3、汎用エンジンなし)。
--
-- 権限マッピング(2026-07-29 ユーザー確認済み):
--   作成・編集・主任確認 = 対象施設の chief/office_manager/director/system_admin
--     (BABY MAHALO・Mahalo Station・Haleleaには「主任」ロールが存在せず、
--      office_managerが主任確認を兼ねる。大和オハナ保育園のみ chief=竹内奈津子 が別途存在)
--   最終承認 = employee_goal_sheet_office_approvers で施設ごとに直接指定
--     (roleを経由しない。施設長=髙木俊は3施設分をoffice_managerで編集権限も別途保有)
--   本人閲覧 = 対象職員本人のみ、release済みのみ
--   経営層(施設長・園長)自身は目標シートの作成対象にしない(承認者側のみ)。
--
-- AI下書き(generate_employee_goal_section_draft)はモック実装。ai_runs.providerに
-- 'mock' を記録し、Anthropic Console契約完了までは実API接続を行わない
-- (docs/Ohana_Works_開発計画_改訂版_2026-07-17.md にTODO追記済み)。

-- ============================================================
-- 1) 承認者指定テーブル(施設ごとの最終承認者。roleを経由しない直接指定)
-- ============================================================
create table employee_goal_sheet_office_approvers (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null unique references offices(id),
  approver_employee_id uuid not null references employees(id),
  updated_by uuid references employees(id),
  updated_at timestamptz not null default now()
);
create trigger trg_employee_goal_sheet_office_approvers_updated_at
  before update on employee_goal_sheet_office_approvers
  for each row execute function set_updated_at();

-- ============================================================
-- 2) 本体
-- ============================================================
create table employee_goal_sheets (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id),
  office_id uuid not null references offices(id),
  fiscal_year int not null,
  evaluation_start_date date not null,
  evaluation_end_date date not null,
  status text not null default 'draft'
    check (status in ('draft', 'ai_draft', 'in_review', 'returned', 'approved', 'finalized', 'released', 'superseded', 'archived')),
  intake_notes jsonb not null default '{}',
  author_id uuid references employees(id),
  reviewer_id uuid references employees(id),
  approver_id uuid references employees(id),
  approved_at timestamptz,
  finalized_at timestamptz,
  released_at timestamptz,
  version int not null default 1,
  supersedes_id uuid references employee_goal_sheets(id),
  snapshot jsonb,
  template_id uuid references document_templates(id),
  pdf_storage_path text,
  pdf_file_hash text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_employee_goal_sheets_updated_at before update on employee_goal_sheets
  for each row execute function set_updated_at();
create index idx_employee_goal_sheets_office_fy on employee_goal_sheets(office_id, fiscal_year);
create index idx_employee_goal_sheets_employee on employee_goal_sheets(employee_id);

-- ============================================================
-- 3) 必須5項目(原案§4.5 の1〜5。6〜9は四半期目標として別テーブル)
-- ============================================================
create table employee_goal_sheet_sections (
  id uuid primary key default gen_random_uuid(),
  sheet_id uuid not null references employee_goal_sheets(id) on delete cascade,
  section_key text not null
    check (section_key in ('relationship_understanding', 'strengths', 'values_connection', 'growth_direction', 'precautions')),
  content text,
  ai_run_id uuid references ai_runs(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (sheet_id, section_key)
);
create trigger trg_employee_goal_sheet_sections_updated_at before update on employee_goal_sheet_sections
  for each row execute function set_updated_at();

-- ============================================================
-- 4) 四半期目標(原案§4.5の6〜9)
-- ============================================================
create table employee_goal_quarterly_targets (
  id uuid primary key default gen_random_uuid(),
  sheet_id uuid not null references employee_goal_sheets(id) on delete cascade,
  quarter int not null check (quarter between 1 and 4),
  period_label text,
  target_content text,
  background_content text,
  ai_run_id uuid references ai_runs(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (sheet_id, quarter)
);
create trigger trg_employee_goal_quarterly_targets_updated_at before update on employee_goal_quarterly_targets
  for each row execute function set_updated_at();

-- ============================================================
-- 5) 主任確認・最終承認の履歴
-- ============================================================
create table employee_goal_reviews (
  id uuid primary key default gen_random_uuid(),
  sheet_id uuid not null references employee_goal_sheets(id) on delete cascade,
  reviewer_id uuid not null references employees(id),
  review_type text not null check (review_type in ('chief_check', 'final_approval')),
  action text not null check (action in ('approved', 'returned')),
  comment text,
  reviewed_at timestamptz not null default now()
);
create index idx_employee_goal_reviews_sheet on employee_goal_reviews(sheet_id);

-- ============================================================
-- 6) 配布・本人閲覧確認
-- ============================================================
create table employee_goal_releases (
  id uuid primary key default gen_random_uuid(),
  sheet_id uuid not null references employee_goal_sheets(id) on delete cascade,
  released_by uuid references employees(id),
  released_at timestamptz not null default now(),
  first_viewed_at timestamptz,
  unique (sheet_id)
);

-- ============================================================
-- 権限判定関数
-- ============================================================
create or replace function has_goal_sheet_edit_access(target_office_id uuid)
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

create or replace function is_goal_sheet_office_approver(target_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from employee_goal_sheet_office_approvers a
    where a.office_id = target_office_id and a.approver_employee_id = my_employee_id()
  ) or exists (
    select 1 from employee_roles er
    join roles r on r.id = er.role_id
    where er.employee_id = my_employee_id() and r.code = 'system_admin'
  );
$$;

-- ============================================================
-- RLS: 直接のINSERT/UPDATE/DELETEポリシーは設けず(deny-all)、
-- 全ての書き込みはこの後のセキュリティ定義RPC経由のみで行う。
-- SELECTのみポリシーで許可する。
-- ============================================================
alter table employee_goal_sheet_office_approvers enable row level security;
create policy egs_approvers_select on employee_goal_sheet_office_approvers
  for select using (has_goal_sheet_edit_access(office_id) or is_system_admin());
create policy egs_approvers_write_system_admin on employee_goal_sheet_office_approvers
  for all using (is_system_admin()) with check (is_system_admin());

alter table employee_goal_sheets enable row level security;
create policy employee_goal_sheets_select on employee_goal_sheets
  for select using (
    has_goal_sheet_edit_access(office_id)
    or is_goal_sheet_office_approver(office_id)
    or (employee_id = my_employee_id() and status = 'released')
  );

alter table employee_goal_sheet_sections enable row level security;
create policy employee_goal_sheet_sections_select on employee_goal_sheet_sections
  for select using (
    exists (
      select 1 from employee_goal_sheets s
      where s.id = employee_goal_sheet_sections.sheet_id
        and (
          has_goal_sheet_edit_access(s.office_id)
          or is_goal_sheet_office_approver(s.office_id)
          or (s.employee_id = my_employee_id() and s.status = 'released')
        )
    )
  );

alter table employee_goal_quarterly_targets enable row level security;
create policy employee_goal_quarterly_targets_select on employee_goal_quarterly_targets
  for select using (
    exists (
      select 1 from employee_goal_sheets s
      where s.id = employee_goal_quarterly_targets.sheet_id
        and (
          has_goal_sheet_edit_access(s.office_id)
          or is_goal_sheet_office_approver(s.office_id)
          or (s.employee_id = my_employee_id() and s.status = 'released')
        )
    )
  );

alter table employee_goal_reviews enable row level security;
create policy employee_goal_reviews_select on employee_goal_reviews
  for select using (
    exists (
      select 1 from employee_goal_sheets s
      where s.id = employee_goal_reviews.sheet_id
        and (has_goal_sheet_edit_access(s.office_id) or is_goal_sheet_office_approver(s.office_id))
    )
  );

alter table employee_goal_releases enable row level security;
create policy employee_goal_releases_select on employee_goal_releases
  for select using (
    exists (
      select 1 from employee_goal_sheets s
      where s.id = employee_goal_releases.sheet_id
        and (
          has_goal_sheet_edit_access(s.office_id)
          or is_goal_sheet_office_approver(s.office_id)
          or (s.employee_id = my_employee_id() and s.status = 'released')
        )
    )
  );

-- ============================================================
-- 監査ログ
-- ============================================================
do $$
declare
  t text;
  audited_tables text[] := array[
    'employee_goal_sheet_office_approvers', 'employee_goal_sheets',
    'employee_goal_sheet_sections', 'employee_goal_quarterly_targets',
    'employee_goal_reviews', 'employee_goal_releases'
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
-- 承認者指定テーブルの初期データ(2026-07-29 ユーザー確認済み、本番の実在職員)。
-- 該当職員が存在しない環境(ステージング等、まだ職員データが無い新規環境)では
-- 何もしない(環境ごとのシードスクリプトが別途担当する)。マイグレーションを
-- 環境非依存に保つため、存在チェックを必須にする。
-- ============================================================
insert into employee_goal_sheet_office_approvers (office_id, approver_employee_id)
select o.id, '338b0302-05f1-4c61-99da-755a3ddc8e3b'::uuid -- 大原利奈
from offices o
where o.name = '大和オハナ保育園'
  and exists (select 1 from employees e where e.id = '338b0302-05f1-4c61-99da-755a3ddc8e3b'::uuid)
union all
select o.id, '720133bb-d7b4-4238-a297-ce672f89cec5'::uuid -- 髙木俊
from offices o
where o.name in ('BABY MAHALO', 'Mahalo Station', 'Halelea')
  and exists (select 1 from employees e where e.id = '720133bb-d7b4-4238-a297-ce672f89cec5'::uuid);

-- ============================================================
-- RPC: 対象職員候補(経営層=承認者指定テーブル登録者を除外)
-- ============================================================
create or replace function fetch_employee_goal_sheet_candidates(p_office_id uuid)
returns table (employee_id uuid, employee_name text, employee_number text)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not has_goal_sheet_edit_access(p_office_id) then
    raise exception 'not authorized';
  end if;

  return query
  select e.id, e.name, e.employee_number
  from employees e
  where e.home_office_id = p_office_id
    and e.resignation_date is null
    and not exists (
      select 1 from employee_goal_sheet_office_approvers a where a.approver_employee_id = e.id
    )
  order by e.name;
end;
$$;

-- ============================================================
-- RPC: 新規作成
-- ============================================================
create or replace function create_employee_goal_sheet(
  p_employee_id uuid,
  p_office_id uuid,
  p_fiscal_year int,
  p_evaluation_start_date date,
  p_evaluation_end_date date
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_sheet_id uuid;
begin
  if not has_goal_sheet_edit_access(p_office_id) then
    raise exception 'not authorized';
  end if;
  if exists (select 1 from employee_goal_sheet_office_approvers a where a.approver_employee_id = p_employee_id) then
    raise exception 'この職員は承認者側のため目標シートを作成できません';
  end if;
  if p_evaluation_end_date < p_evaluation_start_date then
    raise exception 'end date must be on or after start date';
  end if;

  insert into employee_goal_sheets (
    employee_id, office_id, fiscal_year, evaluation_start_date, evaluation_end_date, author_id
  ) values (
    p_employee_id, p_office_id, p_fiscal_year, p_evaluation_start_date, p_evaluation_end_date, my_employee_id()
  )
  returning id into v_sheet_id;

  return v_sheet_id;
end;
$$;

-- ============================================================
-- RPC: 一覧
-- ============================================================
create or replace function fetch_employee_goal_sheets(p_office_id uuid, p_fiscal_year int)
returns table (
  sheet_id uuid, employee_name text, fiscal_year int, status text,
  author_name text, reviewer_name text, approver_name text,
  finalized_at timestamptz, released_at timestamptz
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not (has_goal_sheet_edit_access(p_office_id) or is_goal_sheet_office_approver(p_office_id)) then
    raise exception 'not authorized';
  end if;

  return query
  select
    s.id, e.name, s.fiscal_year, s.status,
    author.name, reviewer.name, approver.name,
    s.finalized_at, s.released_at
  from employee_goal_sheets s
  join employees e on e.id = s.employee_id
  left join employees author on author.id = s.author_id
  left join employees reviewer on reviewer.id = s.reviewer_id
  left join employees approver on approver.id = s.approver_id
  where s.office_id = p_office_id and s.fiscal_year = p_fiscal_year
  order by e.name;
end;
$$;

-- ============================================================
-- RPC: 詳細(本体+セクション+四半期目標)
-- ============================================================
create or replace function fetch_employee_goal_sheet_detail(p_sheet_id uuid)
returns table (
  sheet_id uuid, employee_id uuid, employee_name text, office_id uuid, fiscal_year int,
  evaluation_start_date date, evaluation_end_date date, status text, intake_notes jsonb,
  section_key text, section_content text,
  quarter int, quarter_target text, quarter_background text
)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_employee_id uuid;
  v_status text;
begin
  select s.office_id, s.employee_id, s.status into v_office_id, v_employee_id, v_status
  from employee_goal_sheets s where s.id = p_sheet_id;
  if v_office_id is null then
    raise exception 'sheet not found';
  end if;
  if not (
    has_goal_sheet_edit_access(v_office_id)
    or is_goal_sheet_office_approver(v_office_id)
    or (v_employee_id = my_employee_id() and v_status = 'released')
  ) then
    raise exception 'not authorized';
  end if;

  return query
  select
    s.id, s.employee_id, e.name, s.office_id, s.fiscal_year,
    s.evaluation_start_date, s.evaluation_end_date, s.status, s.intake_notes,
    sec.section_key, sec.content,
    qt.quarter, qt.target_content, qt.background_content
  from employee_goal_sheets s
  join employees e on e.id = s.employee_id
  left join employee_goal_sheet_sections sec on sec.sheet_id = s.id
  left join employee_goal_quarterly_targets qt on qt.sheet_id = s.id and qt.quarter is not null
  where s.id = p_sheet_id;
end;
$$;

-- ============================================================
-- RPC: セクション更新
-- ============================================================
create or replace function update_employee_goal_sheet_section(
  p_sheet_id uuid, p_section_key text, p_content text
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_status text;
begin
  select s.office_id, s.status into v_office_id, v_status from employee_goal_sheets s where s.id = p_sheet_id;
  if v_office_id is null then
    raise exception 'sheet not found';
  end if;
  if not has_goal_sheet_edit_access(v_office_id) then
    raise exception 'not authorized';
  end if;
  if v_status in ('finalized', 'released', 'superseded', 'archived') then
    raise exception 'sheet is % and cannot be edited', v_status;
  end if;

  insert into employee_goal_sheet_sections (sheet_id, section_key, content)
  values (p_sheet_id, p_section_key, p_content)
  on conflict (sheet_id, section_key) do update set content = excluded.content;
end;
$$;

-- ============================================================
-- RPC: 四半期目標更新
-- ============================================================
create or replace function update_employee_goal_quarterly_target(
  p_sheet_id uuid, p_quarter int, p_period_label text, p_target_content text, p_background_content text
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_status text;
begin
  select s.office_id, s.status into v_office_id, v_status from employee_goal_sheets s where s.id = p_sheet_id;
  if v_office_id is null then
    raise exception 'sheet not found';
  end if;
  if not has_goal_sheet_edit_access(v_office_id) then
    raise exception 'not authorized';
  end if;
  if v_status in ('finalized', 'released', 'superseded', 'archived') then
    raise exception 'sheet is % and cannot be edited', v_status;
  end if;

  insert into employee_goal_quarterly_targets (sheet_id, quarter, period_label, target_content, background_content)
  values (p_sheet_id, p_quarter, p_period_label, p_target_content, p_background_content)
  on conflict (sheet_id, quarter) do update set
    period_label = excluded.period_label,
    target_content = excluded.target_content,
    background_content = excluded.background_content;
end;
$$;

-- ============================================================
-- RPC: AI下書き生成(モック実装)
-- Anthropic Console契約完了までは実API接続を行わない。provider='mock'で
-- モック応答であることを機械的に判別できるようにする(ユーザー確認済み条件1)。
-- ============================================================
create or replace function generate_employee_goal_section_draft(
  p_sheet_id uuid, p_section_key text, p_bullet_points text[]
)
returns table (ai_run_id uuid, output_text text)
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_run_id uuid;
  v_output text;
begin
  select s.office_id into v_office_id from employee_goal_sheets s where s.id = p_sheet_id;
  if v_office_id is null then
    raise exception 'sheet not found';
  end if;
  if not has_goal_sheet_edit_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  -- モック応答(Anthropic Console契約完了後、この本文を実API呼び出しに置き換える)
  v_output := '【AI生成(モック)】' || array_to_string(p_bullet_points, '。') || '。(実API未接続のため仮の文章です)';

  insert into ai_runs (
    document_type, document_id, target_field, input_data,
    provider, model, prompt_version, output_text, executed_by
  ) values (
    'employee_goal_sheet', p_sheet_id, p_section_key,
    jsonb_build_object('bullet_points', p_bullet_points),
    'mock', 'mock', 'v0-mock', v_output, my_employee_id()
  )
  returning id into v_run_id;

  ai_run_id := v_run_id;
  output_text := v_output;
  return next;
end;
$$;

-- ============================================================
-- RPC: 提出(主任確認待ちへ)
-- ============================================================
create or replace function submit_employee_goal_sheet_for_review(p_sheet_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_status text;
begin
  select s.office_id, s.status into v_office_id, v_status from employee_goal_sheets s where s.id = p_sheet_id;
  if v_office_id is null then
    raise exception 'sheet not found';
  end if;
  if not has_goal_sheet_edit_access(v_office_id) then
    raise exception 'not authorized';
  end if;
  if v_status not in ('draft', 'ai_draft', 'returned') then
    raise exception 'sheet is % and cannot be submitted', v_status;
  end if;
  if (select count(*) from employee_goal_sheet_sections sec where sec.sheet_id = p_sheet_id and coalesce(trim(sec.content), '') <> '') < 5 then
    raise exception '必須項目が未入力です';
  end if;
  if (select count(*) from employee_goal_quarterly_targets qt where qt.sheet_id = p_sheet_id and coalesce(trim(qt.target_content), '') <> '') < 4 then
    raise exception '4四半期目標が未入力です';
  end if;

  update employee_goal_sheets set status = 'in_review' where id = p_sheet_id;
end;
$$;

-- ============================================================
-- RPC: 主任確認
-- ============================================================
create or replace function review_employee_goal_sheet(p_sheet_id uuid, p_action text, p_comment text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_status text;
begin
  if p_action not in ('approved', 'returned') then
    raise exception 'invalid action';
  end if;
  select s.office_id, s.status into v_office_id, v_status from employee_goal_sheets s where s.id = p_sheet_id;
  if v_office_id is null then
    raise exception 'sheet not found';
  end if;
  if not has_goal_sheet_edit_access(v_office_id) then
    raise exception 'not authorized';
  end if;
  if v_status <> 'in_review' then
    raise exception 'sheet is % and cannot be chief-checked', v_status;
  end if;

  insert into employee_goal_reviews (sheet_id, reviewer_id, review_type, action, comment)
  values (p_sheet_id, my_employee_id(), 'chief_check', p_action, p_comment);

  if p_action = 'returned' then
    update employee_goal_sheets set status = 'returned' where id = p_sheet_id;
  else
    update employee_goal_sheets set status = 'in_review', reviewer_id = my_employee_id() where id = p_sheet_id;
  end if;
end;
$$;

-- ============================================================
-- RPC: 最終承認(承認者指定テーブルで判定、roleを経由しない)
-- ============================================================
create or replace function approve_employee_goal_sheet_final(p_sheet_id uuid, p_action text, p_comment text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_status text;
  v_chief_checked boolean;
begin
  if p_action not in ('approved', 'returned') then
    raise exception 'invalid action';
  end if;
  select s.office_id, s.status into v_office_id, v_status from employee_goal_sheets s where s.id = p_sheet_id;
  if v_office_id is null then
    raise exception 'sheet not found';
  end if;
  if not is_goal_sheet_office_approver(v_office_id) then
    raise exception 'not authorized';
  end if;
  if v_status <> 'in_review' then
    raise exception 'sheet is % and cannot be finally approved', v_status;
  end if;

  select exists (
    select 1 from employee_goal_reviews r
    where r.sheet_id = p_sheet_id and r.review_type = 'chief_check'
    order by r.reviewed_at desc limit 1
  ) into v_chief_checked;
  if not v_chief_checked then
    raise exception '主任確認が完了していません';
  end if;

  insert into employee_goal_reviews (sheet_id, reviewer_id, review_type, action, comment)
  values (p_sheet_id, my_employee_id(), 'final_approval', p_action, p_comment);

  if p_action = 'returned' then
    update employee_goal_sheets set status = 'returned' where id = p_sheet_id;
  else
    update employee_goal_sheets
    set status = 'approved', approver_id = my_employee_id(), approved_at = now()
    where id = p_sheet_id;
  end if;
end;
$$;

-- ============================================================
-- RPC: 確定(スナップショット凍結)。PDFバイト生成はadmin_web側(Next.js API Route)で行う。
-- ============================================================
create or replace function finalize_employee_goal_sheet(p_sheet_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_status text;
  v_snapshot jsonb;
begin
  select s.office_id, s.status into v_office_id, v_status from employee_goal_sheets s where s.id = p_sheet_id;
  if v_office_id is null then
    raise exception 'sheet not found';
  end if;
  if not (has_goal_sheet_edit_access(v_office_id) or is_goal_sheet_office_approver(v_office_id)) then
    raise exception 'not authorized';
  end if;
  if v_status <> 'approved' then
    raise exception 'sheet is % and cannot be finalized', v_status;
  end if;

  select jsonb_build_object(
    'employee_name', e.name,
    'office_name', o.name,
    'fiscal_year', s.fiscal_year,
    'evaluation_start_date', s.evaluation_start_date,
    'evaluation_end_date', s.evaluation_end_date,
    'sections', (
      select jsonb_agg(jsonb_build_object('section_key', sec.section_key, 'content', sec.content))
      from employee_goal_sheet_sections sec where sec.sheet_id = s.id
    ),
    'quarterly_targets', (
      select jsonb_agg(jsonb_build_object(
        'quarter', qt.quarter, 'period_label', qt.period_label,
        'target_content', qt.target_content, 'background_content', qt.background_content
      ))
      from employee_goal_quarterly_targets qt where qt.sheet_id = s.id
    )
  ) into v_snapshot
  from employee_goal_sheets s
  join employees e on e.id = s.employee_id
  join offices o on o.id = s.office_id
  where s.id = p_sheet_id;

  update employee_goal_sheets
  set status = 'finalized', finalized_at = now(), snapshot = v_snapshot
  where id = p_sheet_id;
end;
$$;

-- ============================================================
-- RPC: 配布
-- ============================================================
create or replace function release_employee_goal_sheet(p_sheet_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_status text;
begin
  select s.office_id, s.status into v_office_id, v_status from employee_goal_sheets s where s.id = p_sheet_id;
  if v_office_id is null then
    raise exception 'sheet not found';
  end if;
  if not (has_goal_sheet_edit_access(v_office_id) or is_goal_sheet_office_approver(v_office_id)) then
    raise exception 'not authorized';
  end if;
  if v_status <> 'finalized' then
    raise exception 'sheet is % and cannot be released', v_status;
  end if;

  update employee_goal_sheets set status = 'released', released_at = now() where id = p_sheet_id;

  insert into employee_goal_releases (sheet_id, released_by)
  values (p_sheet_id, my_employee_id())
  on conflict (sheet_id) do nothing;
end;
$$;

-- ============================================================
-- RPC: 本人閲覧(Ohana Staff、released分のみ)
-- ============================================================
create or replace function fetch_my_goal_sheets()
returns table (
  sheet_id uuid, fiscal_year int, evaluation_start_date date, evaluation_end_date date,
  released_at timestamptz, pdf_storage_path text
)
language plpgsql stable security definer set search_path = public
as $$
begin
  return query
  select s.id, s.fiscal_year, s.evaluation_start_date, s.evaluation_end_date, s.released_at, s.pdf_storage_path
  from employee_goal_sheets s
  where s.employee_id = my_employee_id() and s.status = 'released'
  order by s.fiscal_year desc;
end;
$$;

-- ============================================================
-- RPC: 本人閲覧確認の記録
-- ============================================================
create or replace function record_goal_sheet_viewed(p_sheet_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_employee_id uuid;
  v_status text;
begin
  select s.employee_id, s.status into v_employee_id, v_status from employee_goal_sheets s where s.id = p_sheet_id;
  if v_employee_id is null or v_employee_id <> my_employee_id() or v_status <> 'released' then
    raise exception 'not authorized';
  end if;

  update employee_goal_releases
  set first_viewed_at = coalesce(first_viewed_at, now())
  where sheet_id = p_sheet_id;
end;
$$;
