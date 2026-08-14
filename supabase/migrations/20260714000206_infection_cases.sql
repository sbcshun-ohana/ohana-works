-- 206: 感染症 Phase 2 = 案件(infection_cases)+欠席連絡の感染症構造化+自動作成+必要書類判定
--      (設計指示書 2026-08-13 §2起点B/§3.3/§5/§6、Phase 1=205適用済みが前提)
--
-- 概要:
--  (1) parent_requests に infectious_disease_master_id を追加(欠席連絡の感染症選択の構造化。
--      従来の details 日本語キー(感染症により欠席/感染症の種類)は承認画面の汎用表示用に併存)。
--  (2) 案件テーブル infection_cases を新設(§5の中心エンティティ)。
--      - origin: handover(起点A=園内発症・Phase 3)/absence(起点B=自宅発症)
--      - status: awaiting_medical_result(起点Aの受診結果待ち)/infection_confirmed/closed
--      - closed_reason: auto_attended(§3.6)/no_infection/returned/cancelled
--      - disease_master_id は感染症マスターの「行」を参照=当時の版で凍結(AC-16)
--      - required_document/document_state は確定時に判定して凍結(none/opinion_letter/return_form ×
--        not_required/required_not_submitted/submitted_electronically/received_on_paper)
--  (3) 自動作成トリガー(§2起点B「選択時点で感染症確定」= 申請の提出(insert)時に案件を作成。
--      承認を待たない。AC-04)。挙動:
--      - absence かつ master_id あり かつ 施設の infection_control_enabled=ON のとき作成
--      - pending編集で病名変更→未クローズ案件を追随更新 / 選択解除→自動取消
--      - 申請が差し戻し(rejected)→未クローズ案件を自動取消
--      - フラグOFF施設・旧アプリ(master_id無し)は何もしない(従来どおり)
--  (4) RPC:
--      - cancel_infection_case: 案件取消(主任以上・理由必須・監査=AC-17)
--      - fetch_my_child_infection_cases: 保護者の手続き表示用(病名/めやす/必要書類/様式PDFパス)
--      - fetch_board_infection_cases_for_office: 両ボードのバッジ用(198方式)
--
-- 冪等: 列追加=if not exists、テーブル/トリガー/ポリシー=初回適用前提の素create(関数はcreate or replace)。

-- (1) 欠席連絡の感染症選択の構造化
alter table parent_requests add column if not exists infectious_disease_master_id uuid
  references infectious_disease_masters(id);

comment on column parent_requests.infectious_disease_master_id is
  '感染症により欠席の場合に選択されたマスター行(206)。選択時点で感染症確定=案件が自動作成される。旧アプリはNULL';

-- (2) 感染症・体調不良案件
create table infection_cases (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  office_id uuid not null references offices(id),
  origin text not null check (origin in ('handover', 'absence')),
  status text not null default 'infection_confirmed'
    check (status in ('awaiting_medical_result', 'infection_confirmed', 'closed')),
  closed_reason text check (closed_reason in ('auto_attended', 'no_infection', 'returned', 'cancelled')),
  close_note text,
  disease_master_id uuid references infectious_disease_masters(id),
  required_document text not null default 'none'
    check (required_document in ('none', 'opinion_letter', 'return_form')),
  document_state text not null default 'not_required'
    check (document_state in ('not_required', 'required_not_submitted', 'submitted_electronically', 'received_on_paper')),
  source_request_id uuid references parent_requests(id) on delete set null,
  confirmed_at timestamptz,
  closed_at timestamptz,
  closed_by uuid references employees(id),
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table infection_cases is
  '感染症・体調不良案件(206・設計書§5)。起点A=引き継ぎカード(Phase3)/起点B=欠席連絡。書類充足の判定源。'
  ' disease_master_id はマスターの行(=当時の版)を指し、改訂後も当時の判定を再現できる(AC-16)';

create trigger trg_infection_cases_updated_at before update on infection_cases
  for each row execute function set_updated_at();
create index idx_infection_cases_office_status on infection_cases(office_id, status);
create index idx_infection_cases_child on infection_cases(child_id);
create index idx_infection_cases_source_request on infection_cases(source_request_id);

-- RLS: 閲覧=保護者(自分の子)+職員(施設アクセス)。書き込みはトリガー/RPC(definer)のみ=ポリシーを置かない。
alter table infection_cases enable row level security;
create policy infection_cases_select on infection_cases
  for select using (guardian_has_child_access(child_id) or staff_has_guardian_data_access(child_id));

do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'infection_cases'
  );
end $$;

-- (3) 欠席連絡→案件の自動作成/追随/取消(§2起点B・AC-04)
create or replace function handle_parent_request_infection()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_office uuid;
  v_master infectious_disease_masters%rowtype;
  v_required text;
  v_case_id uuid;
begin
  if new.request_type <> 'absence' then
    return new;
  end if;

  -- 差し戻し→未クローズ案件を自動取消
  if tg_op = 'UPDATE' and new.status = 'rejected' and old.status <> 'rejected' then
    update infection_cases
    set status = 'closed', closed_reason = 'cancelled',
        close_note = '欠席連絡が差し戻されたため自動取消', closed_at = now()
    where source_request_id = new.id and status <> 'closed';
    return new;
  end if;

  -- 感染症選択の解除(pending編集)→未クローズ案件を自動取消
  if tg_op = 'UPDATE'
     and new.infectious_disease_master_id is null
     and old.infectious_disease_master_id is not null then
    update infection_cases
    set status = 'closed', closed_reason = 'cancelled',
        close_note = '感染症の選択が取り消されたため自動取消', closed_at = now()
    where source_request_id = new.id and status <> 'closed';
    return new;
  end if;

  if new.infectious_disease_master_id is null then
    return new;
  end if;

  select office_id into v_office from children where id = new.child_id;
  if v_office is null or not is_infection_control_enabled_for_office(v_office) then
    return new;  -- フラグOFF施設では従来どおり(案件を作らない)
  end if;

  select * into v_master from infectious_disease_masters where id = new.infectious_disease_master_id;
  if v_master.id is null then
    return new;
  end if;

  -- 必要書類判定(確定時に凍結)
  v_required := case
    when v_master.requires_opinion_letter then 'opinion_letter'
    when v_master.requires_return_form then 'return_form'
    else 'none' end;

  -- 同一申請由来の未クローズ案件があれば追随更新(pending編集での病名変更)、なければ作成
  update infection_cases
  set disease_master_id = v_master.id,
      required_document = v_required,
      document_state = case when v_required = 'none' then 'not_required' else 'required_not_submitted' end
  where source_request_id = new.id and status <> 'closed'
  returning id into v_case_id;

  if v_case_id is null then
    insert into infection_cases (
      child_id, office_id, origin, status, disease_master_id,
      required_document, document_state, source_request_id, confirmed_at
    ) values (
      new.child_id, v_office, 'absence', 'infection_confirmed', v_master.id,
      v_required,
      case when v_required = 'none' then 'not_required' else 'required_not_submitted' end,
      new.id, now()
    );
  end if;

  return new;
end;
$$;

create trigger trg_parent_requests_infection
  after insert or update on parent_requests
  for each row execute function handle_parent_request_infection();

-- (4-1) 案件取消(主任以上・理由必須・監査=AC-17)。取消でゲート対象から外れる(§3.8の正規の例外)。
create or replace function cancel_infection_case(p_case_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_case infection_cases%rowtype;
begin
  if p_reason is null or trim(p_reason) = '' then
    raise exception 'reason is required';
  end if;
  select * into v_case from infection_cases where id = p_case_id for update;
  if v_case.id is null then
    raise exception 'case not found';
  end if;
  if not manages_childcare(v_case.office_id) then
    raise exception 'not authorized';
  end if;
  if v_case.status = 'closed' then
    raise exception 'case is already closed';
  end if;

  update infection_cases
  set status = 'closed', closed_reason = 'cancelled', close_note = trim(p_reason),
      closed_at = now(), closed_by = my_employee_id()
  where id = p_case_id;
end;
$$;

grant execute on function cancel_infection_case(uuid, text) to anon, authenticated, service_role;

-- (4-2) 保護者の手続き表示(parent_app)。病名・めやす・必要書類・様式PDF(有効版)を返す。
create or replace function fetch_my_child_infection_cases(p_child_id uuid)
returns table (
  case_id uuid,
  origin text,
  status text,
  disease_name text,
  return_criteria text,
  infectious_period text,
  required_document text,
  document_state text,
  confirmed_at timestamptz,
  form_template_path text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_office uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then
    raise exception 'child not found';
  end if;
  if not (guardian_has_child_access(p_child_id) or has_childcare_office_access(v_office)) then
    raise exception 'not authorized';
  end if;

  return query
  select
    ic.id, ic.origin, ic.status,
    m.name, m.return_criteria, m.infectious_period,
    ic.required_document, ic.document_state, ic.confirmed_at,
    (select dt.file_path from document_templates dt
      where dt.template_key = case ic.required_document
                                when 'return_form' then 'infection_return_notice_form'
                                when 'opinion_letter' then 'infection_permission_form'
                              end
        and dt.status = 'active' and dt.file_path is not null
      order by dt.version desc limit 1)
  from infection_cases ic
  left join infectious_disease_masters m on m.id = ic.disease_master_id
  where ic.child_id = p_child_id and ic.status <> 'closed'
  order by ic.created_at desc;
end;
$$;

grant execute on function fetch_my_child_infection_cases(uuid) to anon, authenticated, service_role;

-- (4-3) ボードのバッジ用(198方式・進行中案件のみ)
create or replace function fetch_board_infection_cases_for_office(p_office_id uuid)
returns table (
  child_id uuid,
  case_id uuid,
  status text,
  disease_name text,
  required_document text,
  document_state text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not has_childcare_office_access(p_office_id) then
    raise exception 'not authorized';
  end if;

  return query
  select ic.child_id, ic.id, ic.status, m.name, ic.required_document, ic.document_state
  from infection_cases ic
  left join infectious_disease_masters m on m.id = ic.disease_master_id
  where ic.office_id = p_office_id and ic.status <> 'closed'
  order by ic.created_at;
end;
$$;

grant execute on function fetch_board_infection_cases_for_office(uuid) to anon, authenticated, service_role;
