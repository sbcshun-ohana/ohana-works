-- Phase 3(支援保育事業): 様式1のクラス別欄(人数・加配児童数・職員数・備考)を
-- 園児ごとの個別入力から「施設×年度期」単位へ変更(ユーザー確認済み設計)。
--
-- 背景: これらの値は同一施設・同一年度期の全申請で同じになるべきもので、
-- 園児ごとに入力させると入力の手間だけでなく申請間で値が矛盾するリスクがある。
--
-- 決定事項(2026-07-30 ユーザー確認済み):
--   - クラス人数(在籍数)は保存しない。各申請の様式1「記入日」(recorded_on)を
--     基準日として、child_class_enrollments×childcare_classes.age_groupから
--     都度集計する(記入日を変更すると連動して再集計される)
--   - 加配児童数・職員数・備考は施設×年度期(support_childcare_program_offices)
--     単位で1回だけ設定する。3・4・5歳児それぞれ持つ
--   - 加配児童数は手入力を基本とし、その年度期でsubmission_target状態の
--     候補数を参考表示する(自動集計はしない)
--   - migration 142で様式1に追加したextra_staff_count_3/4/5・staff_count_3/4/5・
--     notes_3/4/5は本変更で不要になるため廃止する(確定時のスナップショットが
--     既に値凍結の役割を担うため、二重に持たない)
--   - 様式1画面ではこれらの値を読み取り専用で引用表示するのみ。編集は
--     別パネル「クラス構成の設定」(主任以上)で行う

-- ============================================================
-- 1) 施設×年度期×年齢のクラス設定
-- ============================================================
create table support_childcare_class_settings (
  id uuid primary key default gen_random_uuid(),
  program_office_id uuid not null references support_childcare_program_offices(id) on delete cascade,
  age int not null check (age in (3, 4, 5)),
  extra_staff_count int,
  staff_count int,
  notes text,
  updated_by uuid references employees(id),
  updated_at timestamptz not null default now(),
  unique (program_office_id, age)
);
create trigger trg_support_childcare_class_settings_updated_at before update on support_childcare_class_settings
  for each row execute function set_updated_at();
create trigger trg_audit_support_childcare_class_settings
  after insert or update or delete on support_childcare_class_settings
  for each row execute function log_event_change();

alter table support_childcare_class_settings enable row level security;
create policy support_childcare_class_settings_select on support_childcare_class_settings
  for select using (
    exists (
      select 1 from support_childcare_program_offices po
      where po.id = support_childcare_class_settings.program_office_id
        and (has_childcare_office_access(po.office_id) or is_support_childcare_office_approver(po.office_id))
    )
  );

-- ============================================================
-- 2) 様式1側のクラス別欄を廃止(施設×年度期単位の設定へ一本化)
-- ============================================================
alter table support_childcare_form1
  drop column extra_staff_count_3,
  drop column extra_staff_count_4,
  drop column extra_staff_count_5,
  drop column staff_count_3,
  drop column staff_count_4,
  drop column staff_count_5,
  drop column notes_3,
  drop column notes_4,
  drop column notes_5;

-- ============================================================
-- RPC: クラス構成の設定(施設×年度期単位、主任以上)
-- ============================================================
create or replace function upsert_support_childcare_class_setting(
  p_program_office_id uuid, p_age int,
  p_extra_staff_count int, p_staff_count int, p_notes text
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
begin
  select po.office_id into v_office_id from support_childcare_program_offices po where po.id = p_program_office_id;
  if v_office_id is null then
    raise exception 'program office not found';
  end if;
  if not is_support_childcare_chief(v_office_id) then
    raise exception 'not authorized';
  end if;
  if p_age not in (3, 4, 5) then
    raise exception 'invalid age';
  end if;

  insert into support_childcare_class_settings (program_office_id, age, extra_staff_count, staff_count, notes, updated_by)
  values (p_program_office_id, p_age, p_extra_staff_count, p_staff_count, p_notes, my_employee_id())
  on conflict (program_office_id, age) do update set
    extra_staff_count = excluded.extra_staff_count,
    staff_count = excluded.staff_count,
    notes = excluded.notes,
    updated_by = excluded.updated_by;
end;
$$;

-- ============================================================
-- RPC: クラス設定の取得(手入力値+参考表示用の提出対象候補数)
-- ============================================================
create or replace function fetch_support_childcare_class_settings(p_program_office_id uuid)
returns table (
  age int, extra_staff_count int, staff_count int, notes text, submission_target_candidate_count int
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
    ages.age,
    s.extra_staff_count, s.staff_count, s.notes,
    (
      select count(*)::int
      from support_childcare_candidates cand
      left join childcare_classes cc on cc.id = cand.class_id
      where cand.program_office_id = p_program_office_id
        and cand.candidacy_status = 'submission_target'
        and substring(cc.age_group from '(\d)歳') = ages.age::text
    )
  from (select unnest(array[3, 4, 5]) as age) ages
  left join support_childcare_class_settings s
    on s.program_office_id = p_program_office_id and s.age = ages.age
  order by ages.age;
end;
$$;

-- ============================================================
-- RPC: 基準日時点のクラス在籍数(様式1「記入日」を基準日として使う。保存しない)
-- ============================================================
create or replace function fetch_support_childcare_class_headcount_as_of(p_office_id uuid, p_as_of_date date)
returns table (age int, headcount int)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not (has_childcare_office_access(p_office_id) or is_support_childcare_office_approver(p_office_id)) then
    raise exception 'not authorized';
  end if;
  if p_as_of_date is null then
    raise exception 'as_of_date is required';
  end if;

  return query
  select
    ages.age,
    (
      select count(distinct c.id)::int
      from children c
      join child_class_enrollments cce on cce.child_id = c.id
        and cce.effective_start_date <= p_as_of_date
        and (cce.effective_end_date is null or cce.effective_end_date >= p_as_of_date)
      join childcare_classes cc on cc.id = cce.class_id
      where cc.office_id = p_office_id
        and substring(cc.age_group from '(\d)歳') = ages.age::text
    )
  from (select unnest(array[3, 4, 5]) as age) ages
  order by ages.age;
end;
$$;

-- ============================================================
-- update_support_childcare_form1: クラス別欄のパラメータを削除するため再作成
-- ============================================================
drop function if exists update_support_childcare_form1(
  uuid, date, int, int, int, int, int, int, text, text, text, uuid, text, text, text, text
);

create or replace function update_support_childcare_form1(
  p_application_id uuid,
  p_recorded_on date,
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
    policy_stance_item_id = p_policy_stance_item_id, policy_target_month = p_policy_target_month,
    policy_no_extra_staff_reason = p_policy_no_extra_staff_reason,
    policy_no_application_reason = p_policy_no_application_reason,
    subsidy_expected_effect = p_subsidy_expected_effect
  where application_id = p_application_id;
end;
$$;

-- ============================================================
-- fetch_support_childcare_application_detail: 戻り値からクラス別欄を削除
-- ============================================================
drop function if exists fetch_support_childcare_application_detail(uuid);

create or replace function fetch_support_childcare_application_detail(p_application_id uuid)
returns table (
  application_id uuid, status text, child_name text,
  form1_id uuid, form1_recorded_on date,
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
-- finalize_support_childcare_application: スナップショットにクラス設定+
-- 記入日時点の在籍数を埋め込む(D4規約: 確定後の在籍変動から独立して再現可能にする)
-- ============================================================
create or replace function finalize_support_childcare_application(p_application_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_status text;
  v_program_office_id uuid;
  v_recorded_on date;
  v_snapshot jsonb;
  v_class_settings jsonb;
  v_headcounts jsonb;
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

  select cand.program_office_id, f1.recorded_on into v_program_office_id, v_recorded_on
  from support_childcare_applications a
  join support_childcare_candidates cand on cand.id = a.candidate_id
  left join support_childcare_form1 f1 on f1.application_id = a.id
  where a.id = p_application_id;

  select jsonb_agg(jsonb_build_object(
    'age', s.age, 'extra_staff_count', s.extra_staff_count,
    'staff_count', s.staff_count, 'notes', s.notes
  ))
  into v_class_settings
  from support_childcare_class_settings s
  where s.program_office_id = v_program_office_id;

  if v_recorded_on is not null then
    select jsonb_agg(jsonb_build_object('age', h.age, 'headcount', h.headcount))
    into v_headcounts
    from fetch_support_childcare_class_headcount_as_of(v_office_id, v_recorded_on) h;
  end if;

  select jsonb_build_object(
    'child_name', ch.display_name,
    'form1', to_jsonb(f1.*),
    'form1_class_settings', v_class_settings,
    'form1_class_headcounts_as_of', v_recorded_on,
    'form1_class_headcounts', v_headcounts,
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
