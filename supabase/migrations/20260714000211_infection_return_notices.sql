-- 211: 感染症 Phase 4 = 電子登園届(保護者記入・アプリ完結)+紙受領記録
--      (設計指示書 2026-08-13 §3.5/§3.7/AC-06〜09/12/16、Phase 3=209/210適用済みが前提)
--
-- 概要:
--  (1) infection_return_notices: 電子登園届。下書き(draft)→提出(submitted)。
--      - 確認項目・日付条件はマスターの rule_definition(案件が参照する「行」=当時の版)から動的生成。
--      - 提出時にサーバー側で条件を再検証(AC-08)。提出後は保護者修正不可・入力とマスター版を
--        不変スナップショットで保存(AC-09/16)。
--      - 提出成立で案件 document_state='submitted_electronically'(園の追加承認は不要)+園側通知。
--  (2) infection_return_notice_revisions: 提出前編集の変更履歴(前後の値・日時・保護者=AC-07)。
--  (3) paper_document_receipts: 紙書類(登園届・登園許可書)の受領記録。一般職員が記録でき、
--      受領者・時刻・方法を保存して案件 document_state='received_on_paper' へ(AC-12)。
--      v1は受領記録のみ(画像保存は§12の将来枠)。
--  (4) RPC:
--      - save_return_notice_draft: 下書き保存(upsert)+変更履歴記録
--      - submit_return_notice: 条件の再検証→提出固定→案件反映→園側通知
--      - record_paper_document_receipt: 紙受領→案件反映(一般職員可・保存失敗時は解除されない=AC-12)
--
-- 検証規則(§3.5・宣言的ルールの評価):
--   master.rule_definition = {"checks": [文言...], "date_condition": {"base_label", "min_hours"}}
--   - checks: 全文言に true のチェックが必要
--   - date_condition: 基準日時(p_date_condition_base_at)の入力必須+ now() >= 基準+min_hours
--   - rule_definition が null(意見書対象等)の登園届提出は拒否(required_document='return_form'のみ提出可)
--
-- 冪等: 関数=create or replace。テーブル/ポリシー/トリガーは初回適用前提の素create。

-- (1) 電子登園届
create table infection_return_notices (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references infection_cases(id) on delete cascade,
  child_id uuid not null references children(id) on delete cascade,
  status text not null default 'draft' check (status in ('draft', 'submitted')),
  -- 入力スナップショット: {"checks":[{"label":..,"checked":true},...],
  --                        "date_condition_base_at":"...","visited_at":"...","note":...}
  inputs jsonb not null default '{}'::jsonb,
  disease_master_id uuid references infectious_disease_masters(id),
  disease_name text,
  disease_version int,
  confirmed_declaration boolean not null default false,  -- 「この内容で提出します」チェック
  submitted_by_guardian_id uuid references guardians(id),
  submitted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (case_id)  -- 案件ごとに届は1枚(下書き→提出)
);

comment on table infection_return_notices is
  '電子登園届(211・保護者記入)。提出時にマスター版(disease_master_id=行参照+名称/版の写し)と入力を凍結(AC-09/16)。'
  ' 提出後は保護者修正不可。園の追加承認は不要(提出成立=書類充足)';

create trigger trg_infection_return_notices_updated_at before update on infection_return_notices
  for each row execute function set_updated_at();
create index idx_irn_child on infection_return_notices (child_id);

alter table infection_return_notices enable row level security;
create policy irn_select on infection_return_notices
  for select using (guardian_has_child_access(child_id) or staff_has_guardian_data_access(child_id));

do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'infection_return_notices'
  );
end $$;

-- (2) 提出前編集の変更履歴(AC-07)
create table infection_return_notice_revisions (
  id uuid primary key default gen_random_uuid(),
  notice_id uuid not null references infection_return_notices(id) on delete cascade,
  before_inputs jsonb,
  after_inputs jsonb not null,
  edited_by_guardian_id uuid references guardians(id),
  created_at timestamptz not null default now()
);

create index idx_irnr_notice on infection_return_notice_revisions (notice_id);
alter table infection_return_notice_revisions enable row level security;
create policy irnr_select on infection_return_notice_revisions
  for select using (
    exists (select 1 from infection_return_notices n
            where n.id = notice_id
              and (guardian_has_child_access(n.child_id) or staff_has_guardian_data_access(n.child_id)))
  );

-- (3) 紙書類の受領記録(AC-12・v1は記録のみ)
create table paper_document_receipts (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references infection_cases(id) on delete cascade,
  child_id uuid not null references children(id) on delete cascade,
  document_kind text not null check (document_kind in ('opinion_letter', 'return_form')),
  received_method text not null default 'paper' check (received_method in ('paper', 'photo', 'other')),
  note text,
  received_by uuid references employees(id),
  received_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

comment on table paper_document_receipts is
  '紙書類の受領記録(211・AC-12)。一般職員が記録可。記録成立で案件の書類状態=received_on_paper';

create index idx_pdr_case on paper_document_receipts (case_id);
alter table paper_document_receipts enable row level security;
create policy pdr_select on paper_document_receipts
  for select using (staff_has_guardian_data_access(child_id));

do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'paper_document_receipts'
  );
end $$;

-- (4-1) 下書き保存(upsert)+変更履歴(AC-07)
create or replace function save_return_notice_draft(p_case_id uuid, p_inputs jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_case infection_cases%rowtype;
  v_notice infection_return_notices%rowtype;
  v_id uuid;
begin
  select * into v_case from infection_cases where id = p_case_id for update;
  if v_case.id is null then
    raise exception 'case not found';
  end if;
  if not guardian_has_child_access(v_case.child_id) then
    raise exception 'not authorized';
  end if;
  if v_case.status = 'closed' then
    raise exception 'case is closed';
  end if;
  if v_case.required_document <> 'return_form' then
    raise exception 'this case does not require a return form';
  end if;

  select * into v_notice from infection_return_notices where case_id = p_case_id for update;
  if v_notice.id is not null and v_notice.status = 'submitted' then
    raise exception 'return notice is already submitted';  -- 提出後は保護者修正不可(AC-09)
  end if;

  if v_notice.id is null then
    insert into infection_return_notices (case_id, child_id, inputs)
    values (p_case_id, v_case.child_id, coalesce(p_inputs, '{}'::jsonb))
    returning id into v_id;
    insert into infection_return_notice_revisions (notice_id, before_inputs, after_inputs, edited_by_guardian_id)
    values (v_id, null, coalesce(p_inputs, '{}'::jsonb), my_guardian_id());
  else
    insert into infection_return_notice_revisions (notice_id, before_inputs, after_inputs, edited_by_guardian_id)
    values (v_notice.id, v_notice.inputs, coalesce(p_inputs, '{}'::jsonb), my_guardian_id());
    update infection_return_notices set inputs = coalesce(p_inputs, '{}'::jsonb)
    where id = v_notice.id;
    v_id := v_notice.id;
  end if;
  return v_id;
end;
$$;

grant execute on function save_return_notice_draft(uuid, jsonb) to anon, authenticated, service_role;

-- (4-2) 提出: 宣言的ルールをサーバー側で再検証し、提出固定+案件反映+園側通知(AC-06/08/09)
create or replace function submit_return_notice(
  p_case_id uuid,
  p_inputs jsonb,
  p_confirmed boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_case infection_cases%rowtype;
  v_master infectious_disease_masters%rowtype;
  v_notice_id uuid;
  v_check text;
  v_checked boolean;
  v_base_at timestamptz;
  v_min_hours int;
  v_child_name text;
begin
  select * into v_case from infection_cases where id = p_case_id for update;
  if v_case.id is null then
    raise exception 'case not found';
  end if;
  if not guardian_has_child_access(v_case.child_id) then
    raise exception 'not authorized';
  end if;
  if v_case.status = 'closed' then
    raise exception 'case is closed';
  end if;
  if v_case.required_document <> 'return_form' then
    raise exception 'this case does not require a return form';
  end if;
  if coalesce(p_confirmed, false) = false then
    raise exception 'confirmation declaration is required';  -- 本人確認チェック必須(§3.5)
  end if;

  select * into v_master from infectious_disease_masters where id = v_case.disease_master_id;
  if v_master.id is null or v_master.rule_definition is null then
    raise exception 'rule definition not found for this disease';
  end if;

  -- 症状確認チェック: マスターの全文言が checked=true であること(AC-06)
  for v_check in select jsonb_array_elements_text(v_master.rule_definition->'checks')
  loop
    select bool_or((c->>'checked')::boolean) into v_checked
    from jsonb_array_elements(coalesce(p_inputs->'checks', '[]'::jsonb)) c
    where c->>'label' = v_check;
    if coalesce(v_checked, false) = false then
      raise exception '確認項目が未達です: %', v_check;
    end if;
  end loop;

  -- 日付条件(溶連菌: 抗菌薬内服開始から min_hours 経過)(AC-06)
  if v_master.rule_definition ? 'date_condition' then
    v_min_hours := (v_master.rule_definition->'date_condition'->>'min_hours')::int;
    v_base_at := (p_inputs->>'date_condition_base_at')::timestamptz;
    if v_base_at is null then
      raise exception '基準日時(%)が入力されていません', v_master.rule_definition->'date_condition'->>'base_label';
    end if;
    if now() < v_base_at + make_interval(hours => v_min_hours) then
      raise exception '条件未達: %から%時間が経過していません',
        v_master.rule_definition->'date_condition'->>'base_label', v_min_hours;
    end if;
  end if;

  -- 提出固定(下書きがあれば昇格・なければ作成)。マスター版の写しも保存(AC-09/16)
  insert into infection_return_notices (
    case_id, child_id, status, inputs, disease_master_id, disease_name, disease_version,
    confirmed_declaration, submitted_by_guardian_id, submitted_at
  ) values (
    p_case_id, v_case.child_id, 'submitted', coalesce(p_inputs, '{}'::jsonb),
    v_master.id, v_master.name, v_master.version,
    true, my_guardian_id(), now()
  )
  on conflict (case_id) do update set
    status = 'submitted',
    inputs = excluded.inputs,
    disease_master_id = excluded.disease_master_id,
    disease_name = excluded.disease_name,
    disease_version = excluded.disease_version,
    confirmed_declaration = true,
    submitted_by_guardian_id = excluded.submitted_by_guardian_id,
    submitted_at = excluded.submitted_at
  returning id into v_notice_id;

  -- 提出成立=書類充足(園の追加承認は不要)。ゲートへ即時反映(AC-08)
  update infection_cases set document_state = 'submitted_electronically' where id = p_case_id;

  -- 園側(管理者層)へ通知
  select display_name || coalesce(honorific_suffix_resolved, '') into v_child_name
  from children where id = v_case.child_id;

  insert into notifications (notification_type, title, body, channels, target_employee_id, payload, status)
  select distinct
    'infection_return_notice',
    '登園届が提出されました',
    v_child_name || 'の登園届(' || v_master.name || ')が提出されました',
    array['push', 'in_app'],
    er.employee_id,
    jsonb_build_object('child_id', v_case.child_id::text, 'case_id', p_case_id::text),
    'pending'
  from employee_roles er
  join roles r on r.id = er.role_id
  where r.code in ('director', 'chief', 'office_manager')
    and (er.office_id is null or er.office_id = v_case.office_id);

  return v_notice_id;
end;
$$;

grant execute on function submit_return_notice(uuid, jsonb, boolean) to anon, authenticated, service_role;

-- (4-3) 紙受領記録(一般職員可)。記録の保存が成立した時だけ書類状態を解除(AC-12)。
create or replace function record_paper_document_receipt(
  p_case_id uuid,
  p_received_method text default 'paper',
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_case infection_cases%rowtype;
  v_id uuid;
begin
  select * into v_case from infection_cases where id = p_case_id for update;
  if v_case.id is null then
    raise exception 'case not found';
  end if;
  if not has_childcare_office_access(v_case.office_id) then
    raise exception 'not authorized';
  end if;
  if v_case.status = 'closed' then
    raise exception 'case is closed';
  end if;
  if v_case.required_document = 'none' then
    raise exception 'this case does not require a document';
  end if;

  insert into paper_document_receipts (case_id, child_id, document_kind, received_method, note, received_by)
  values (p_case_id, v_case.child_id, v_case.required_document, coalesce(p_received_method, 'paper'),
          p_note, my_employee_id())
  returning id into v_id;

  update infection_cases set document_state = 'received_on_paper' where id = p_case_id;
  return v_id;
end;
$$;

grant execute on function record_paper_document_receipt(uuid, text, text) to anon, authenticated, service_role;
