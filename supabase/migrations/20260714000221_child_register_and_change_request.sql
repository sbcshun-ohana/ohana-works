-- 221: 入園時基本情報(M6) Phase 3a = 園児台帳RPC+変更申請開始RPC。
-- 1) fetch_child_register: 職員向け台帳(children正本+世帯住所+承認済みフォームスナップショット)。
--    権限=施設の全職員(has_childcare_office_access)。閲覧専用(書き込みRPCなし)。
-- 2) start_enrollment_change_request: 保護者の変更申請開始(草案§11.1)。
--    承認済みフォームの最新承認スナップショットを下書きへコピーして status='approved'→'draft'。
--    以後は既存の 下書き保存→提出(版+1)→園の差分確認・承認(正本反映) をそのまま再利用する。
-- 冪等: create or replace のみ。

-- 1) 園児台帳(職員向け)
create or replace function fetch_child_register(p_child_id uuid)
returns table (
  child_id uuid,
  full_name text,
  name_kana text,
  display_name text,
  honorific_suffix text,
  gender text,
  birth_date date,
  enrollment_date date,
  enrollment_status text,
  child_kind text,
  class_name text,
  household jsonb,
  register_data jsonb,
  register_version int,
  register_approved_at timestamptz
)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_office_id uuid;
begin
  select c.office_id into v_office_id from children c where c.id = p_child_id;
  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  return query
  select
    c.id, c.full_name, c.name_kana, c.display_name, c.honorific_suffix_resolved,
    c.gender, c.birth_date, c.enrollment_date, c.enrollment_status, c.child_kind,
    cc.class_name,
    case when h.id is null then null else jsonb_build_object(
      'postal_code', h.postal_code, 'prefecture', h.prefecture, 'city', h.city,
      'town', h.town, 'address_line', h.address_line, 'building', h.building
    ) end,
    s.data, s.version, s.reviewed_at
  from children c
  left join child_class_enrollments cce on cce.child_id = c.id and cce.effective_end_date is null
  left join childcare_classes cc on cc.id = cce.class_id
  left join households h on h.id = c.household_id
  left join lateral (
    select efs.data, efs.version, efs.reviewed_at
    from enrollment_form_submissions efs
    join enrollment_forms ef on ef.id = efs.form_id
    where ef.child_id = c.id and efs.review_status = 'approved'
    order by efs.version desc limit 1
  ) s on true
  where c.id = p_child_id;
end;
$$;

-- 2) 変更申請の開始(保護者)
create or replace function start_enrollment_change_request(p_child_id uuid)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_form record;
  v_data jsonb;
begin
  if not is_enrollment_form_enabled_for_child(p_child_id) then
    raise exception 'not authorized';
  end if;

  select * into v_form from enrollment_forms where child_id = p_child_id;
  if v_form.id is null then
    raise exception 'form not found';
  end if;
  if v_form.status <> 'approved' then
    raise exception 'change request is only available for approved forms';
  end if;

  select efs.data into v_data
  from enrollment_form_submissions efs
  where efs.form_id = v_form.id and efs.review_status = 'approved'
  order by efs.version desc limit 1;
  if v_data is null then
    raise exception 'no approved submission';
  end if;

  update enrollment_forms
  set status = 'draft', form_data = v_data, current_step = 1, last_saved_at = now()
  where id = v_form.id;

  return v_form.id;
end;
$$;
