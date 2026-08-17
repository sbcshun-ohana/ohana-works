-- 218: 入園時基本情報(M6) Phase 2a = 世帯(households・請求詳細設計§1準拠)+入園フォーム基盤。
-- 1) is_childcare_admin: 「管理者以上」(director/office_manager/統括系。chiefを含めない=Q&A#5・請求本案§2)
-- 2) households + children/guardians.household_id(段階移行・nullable)。family_group_idは非推奨化
-- 3) enrollment_forms(下書きJSONB・1園児1行) / enrollment_form_submissions(提出スナップショット・版管理)
--    JSONBセクション: basic/address/guardians/emergency/pickup/family/birth_growth/health/medication/checkups/lifestyle/thoughts
-- 4) 機能フラグ enrollment_form_enabled(既定OFF)
-- 5) 保護者RPC: 有効判定/取得/prefill(兄弟複製)/下書き保存/提出
-- 6) 園側RPC(管理者以上): 一覧/確認(差分用の現正本つき)/差し戻し/承認(正本反映+通知)/取消
-- 7) promote_provisional_child: 正式入園(クラス割当・在籍中へ。主任以上=create_childと同線)
-- 正本反映の範囲: children(氏名・かな・愛称→display_name・性別・生年月日)/households(住所)/
--   pickup_persons(代理送迎者upsert・確認済み身分証は保持)。その他セクションは承認済みスナップショットが正本。

-- 1) 管理者以上ヘルパ
create or replace function is_childcare_admin(target_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
      select 1 from employee_roles er
      join roles r on r.id = er.role_id
      where er.employee_id = my_employee_id()
        and (
          r.code in ('system_admin', 'executive_director')
          or (
            r.code in ('director', 'office_manager')
            and (er.office_id is null or er.office_id = target_office_id)
          )
        )
    )
    or exists (
      select 1 from multi_office_authority_grants g
      where g.grantee_employee_id = my_employee_id()
        and g.office_id = target_office_id
        and g.revoked_at is null
    );
$$;

-- 2) 世帯(請求詳細設計§1の定義+M6住所拡張。二重概念禁止=この1本のみ)
create table households (
  id uuid primary key default gen_random_uuid(),
  display_name text,
  representative_guardian_id uuid references guardians(id),
  postal_code text,
  prefecture text,
  city text,
  town text,
  address_line text,
  building text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_households_updated_at before update on households
  for each row execute function set_updated_at();
alter table households enable row level security;

alter table children add column if not exists household_id uuid references households(id);
alter table guardians add column if not exists household_id uuid references households(id);
create index idx_children_household on children(household_id);
create index idx_guardians_household on guardians(household_id);
comment on column children.family_group_id is '非推奨(未使用)。世帯は household_id へ一本化(請求詳細設計§1)';

-- 3) 入園フォーム
create table enrollment_forms (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null unique references children(id) on delete cascade,
  office_id uuid not null references offices(id),
  status text not null default 'draft'
    check (status in ('draft', 'submitted', 'sent_back', 'approved', 'cancelled')),
  current_step int not null default 1,
  form_data jsonb not null default '{}',
  created_by_guardian_id uuid references guardians(id),
  last_saved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_enrollment_forms_updated_at before update on enrollment_forms
  for each row execute function set_updated_at();
create index idx_enrollment_forms_office on enrollment_forms(office_id, status);
alter table enrollment_forms enable row level security;

create table enrollment_form_submissions (
  id uuid primary key default gen_random_uuid(),
  form_id uuid not null references enrollment_forms(id) on delete cascade,
  version int not null,
  data jsonb not null,
  submitted_by_guardian_id uuid references guardians(id),
  submitted_at timestamptz not null default now(),
  review_status text not null default 'pending'
    check (review_status in ('pending', 'sent_back', 'approved', 'superseded')),
  review_message text,
  reviewed_by uuid references employees(id),
  reviewed_at timestamptz,
  unique (form_id, version)
);
create index idx_enrollment_submissions_form on enrollment_form_submissions(form_id);
alter table enrollment_form_submissions enable row level security;

-- 4) 機能フラグ(既定OFF・施設別ON)
insert into feature_flags (feature_key, name, description, default_enabled)
select 'enrollment_form_enabled', '入園時基本情報フォーム',
       '保護者による入園時基本情報の入力・提出・園承認(M6 Phase 2)', false
where not exists (select 1 from feature_flags where feature_key = 'enrollment_form_enabled');

create or replace function is_enrollment_form_enabled_for_office(p_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select is_feature_enabled_for_office('enrollment_form_enabled', p_office_id);
$$;

-- 5-1) 保護者: 対象園児でフォームが使えるか(リンク+フラグ)
create or replace function is_enrollment_form_enabled_for_child(p_child_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select guardian_has_child_access(p_child_id)
     and is_enrollment_form_enabled_for_office((select office_id from children where id = p_child_id));
$$;

-- 5-2) 保護者: 自分のフォーム取得(無ければ0行)
create or replace function fetch_my_enrollment_form(p_child_id uuid)
returns table (
  form_id uuid,
  status text,
  current_step int,
  form_data jsonb,
  last_saved_at timestamptz,
  latest_version int,
  latest_review_status text,
  latest_review_message text,
  latest_submitted_at timestamptz
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not is_enrollment_form_enabled_for_child(p_child_id) then
    raise exception 'not authorized';
  end if;
  return query
  select ef.id, ef.status, ef.current_step, ef.form_data, ef.last_saved_at,
         s.version, s.review_status, s.review_message, s.submitted_at
  from enrollment_forms ef
  left join lateral (
    select * from enrollment_form_submissions
    where enrollment_form_submissions.form_id = ef.id
    order by version desc limit 1
  ) s on true
  where ef.child_id = p_child_id;
end;
$$;

-- 5-3) 保護者: 初期値(園の仮登録値+兄弟の承認済みフォームから世帯系セクションを複製=草案§7.4)
create or replace function fetch_enrollment_prefill(p_child_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_prev jsonb;
  v_basic jsonb;
begin
  if not is_enrollment_form_enabled_for_child(p_child_id) then
    raise exception 'not authorized';
  end if;

  select jsonb_build_object('full_name', c.full_name, 'name_kana', c.name_kana)
    into v_basic from children c where c.id = p_child_id;

  select s.data into v_prev
  from enrollment_form_submissions s
  join enrollment_forms ef on ef.id = s.form_id
  where s.review_status = 'approved'
    and ef.child_id <> p_child_id
    and ef.child_id in (select child_id from guardian_child_links where guardian_id = my_guardian_id())
  order by s.reviewed_at desc
  limit 1;

  return jsonb_build_object(
    'basic', v_basic,
    'address', coalesce(v_prev->'address', '{}'::jsonb),
    'guardians', coalesce(v_prev->'guardians', '[]'::jsonb),
    'emergency', coalesce(v_prev->'emergency', '[]'::jsonb),
    'family', coalesce(v_prev->'family', '[]'::jsonb)
  );
end;
$$;

-- 5-4) 保護者: 下書き保存(無ければ作成。提出中・承認済み・取消は編集不可)
create or replace function save_enrollment_form_draft(p_child_id uuid, p_form_data jsonb, p_current_step int)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_form_id uuid;
  v_status text;
begin
  if not is_enrollment_form_enabled_for_child(p_child_id) then
    raise exception 'not authorized';
  end if;
  if p_form_data is null then
    raise exception 'form data required';
  end if;

  select id, status into v_form_id, v_status from enrollment_forms where child_id = p_child_id;
  if v_form_id is null then
    insert into enrollment_forms (child_id, office_id, form_data, current_step, created_by_guardian_id, last_saved_at)
    values (p_child_id, (select office_id from children where id = p_child_id),
            p_form_data, coalesce(p_current_step, 1), my_guardian_id(), now())
    returning id into v_form_id;
    return v_form_id;
  end if;

  if v_status not in ('draft', 'sent_back') then
    raise exception 'form is not editable in status %', v_status;
  end if;

  update enrollment_forms
  set form_data = p_form_data,
      current_step = coalesce(p_current_step, current_step),
      last_saved_at = now()
  where id = v_form_id;
  return v_form_id;
end;
$$;

-- 5-5) 保護者: 提出(必須コア項目+平熱37.5℃以上は警告確認必須をサーバ側でも強制)
create or replace function submit_enrollment_form(p_child_id uuid)
returns int
language plpgsql security definer set search_path = public
as $$
declare
  v_form record;
  v_version int;
  v_temp numeric;
begin
  if not is_enrollment_form_enabled_for_child(p_child_id) then
    raise exception 'not authorized';
  end if;

  select * into v_form from enrollment_forms where child_id = p_child_id;
  if v_form.id is null then
    raise exception 'form not found';
  end if;
  if v_form.status not in ('draft', 'sent_back') then
    raise exception 'form is not submittable in status %', v_form.status;
  end if;

  if coalesce(trim(v_form.form_data->'basic'->>'full_name'), '') = ''
     or coalesce(trim(v_form.form_data->'basic'->>'name_kana'), '') = ''
     or coalesce(trim(v_form.form_data->'basic'->>'gender'), '') = ''
     or coalesce(trim(v_form.form_data->'basic'->>'birth_date'), '') = ''
     or coalesce(trim(v_form.form_data->'address'->>'postal_code'), '') = '' then
    raise exception 'required fields missing';
  end if;

  v_temp := nullif(v_form.form_data->'health'->>'normal_temp', '')::numeric;
  if v_temp is not null and v_temp >= 37.5
     and coalesce(v_form.form_data->'health'->>'high_temp_acknowledged', 'false') <> 'true' then
    raise exception 'high normal temperature must be acknowledged';
  end if;

  select coalesce(max(version), 0) + 1 into v_version
  from enrollment_form_submissions where form_id = v_form.id;

  update enrollment_form_submissions
  set review_status = 'superseded'
  where form_id = v_form.id and review_status = 'pending';

  insert into enrollment_form_submissions (form_id, version, data, submitted_by_guardian_id)
  values (v_form.id, v_version, v_form.form_data, my_guardian_id());

  update enrollment_forms set status = 'submitted' where id = v_form.id;
  return v_version;
end;
$$;

-- 6-1) 園側: 一覧(管理者以上)
create or replace function fetch_enrollment_forms_for_office(p_office_id uuid)
returns table (
  form_id uuid,
  child_id uuid,
  child_full_name text,
  child_name_kana text,
  status text,
  current_step int,
  last_saved_at timestamptz,
  latest_version int,
  latest_submitted_at timestamptz,
  latest_review_status text
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not is_childcare_admin(p_office_id) then
    raise exception 'not authorized';
  end if;
  return query
  select ef.id, c.id, c.full_name, c.name_kana, ef.status, ef.current_step, ef.last_saved_at,
         s.version, s.submitted_at, s.review_status
  from enrollment_forms ef
  join children c on c.id = ef.child_id
  left join lateral (
    select * from enrollment_form_submissions
    where enrollment_form_submissions.form_id = ef.id
    order by version desc limit 1
  ) s on true
  where ef.office_id = p_office_id
  order by (ef.status = 'submitted') desc, s.submitted_at desc nulls last, ef.updated_at desc;
end;
$$;

-- 6-2) 園側: 確認用詳細(最新提出+差分用の現正本。管理者以上)
create or replace function fetch_enrollment_form_review(p_form_id uuid)
returns table (
  form_id uuid,
  child_id uuid,
  form_status text,
  version int,
  submitted_at timestamptz,
  review_status text,
  review_message text,
  data jsonb,
  current_full_name text,
  current_name_kana text,
  current_display_name text,
  current_gender text,
  current_birth_date date,
  current_household jsonb
)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_office_id uuid;
begin
  select ef.office_id into v_office_id from enrollment_forms ef where ef.id = p_form_id;
  if v_office_id is null then
    raise exception 'form not found';
  end if;
  if not is_childcare_admin(v_office_id) then
    raise exception 'not authorized';
  end if;
  return query
  select ef.id, c.id, ef.status, s.version, s.submitted_at, s.review_status, s.review_message, s.data,
         c.full_name, c.name_kana, c.display_name, c.gender, c.birth_date,
         case when h.id is null then null else jsonb_build_object(
           'postal_code', h.postal_code, 'prefecture', h.prefecture, 'city', h.city,
           'town', h.town, 'address_line', h.address_line, 'building', h.building
         ) end
  from enrollment_forms ef
  join children c on c.id = ef.child_id
  left join households h on h.id = c.household_id
  left join lateral (
    select * from enrollment_form_submissions
    where enrollment_form_submissions.form_id = ef.id
    order by version desc limit 1
  ) s on true
  where ef.id = p_form_id;
end;
$$;

-- 6-3) 園側: 差し戻し(管理者以上・保護者へプッシュ)
create or replace function send_back_enrollment_form(p_form_id uuid, p_message text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_sub record;
begin
  select office_id into v_office_id from enrollment_forms where id = p_form_id;
  if v_office_id is null then
    raise exception 'form not found';
  end if;
  if not is_childcare_admin(v_office_id) then
    raise exception 'not authorized';
  end if;
  if coalesce(trim(p_message), '') = '' then
    raise exception 'message required';
  end if;

  select * into v_sub from enrollment_form_submissions
  where form_id = p_form_id and review_status = 'pending'
  order by version desc limit 1;
  if v_sub.id is null then
    raise exception 'no pending submission';
  end if;

  update enrollment_form_submissions
  set review_status = 'sent_back', review_message = p_message,
      reviewed_by = my_employee_id(), reviewed_at = now()
  where id = v_sub.id;

  update enrollment_forms set status = 'sent_back' where id = p_form_id;

  insert into notifications (notification_type, title, body, channels, target_guardian_id, payload, status)
  values ('enrollment_form', '【入園手続き】内容確認のお願い',
          '園から入園時基本情報の確認依頼があります。アプリからご確認ください。',
          array['push'], v_sub.submitted_by_guardian_id,
          jsonb_build_object('form_id', p_form_id::text), 'pending');
end;
$$;

-- 6-4) 園側: 承認(管理者以上)。正本反映: children/households/pickup_persons+保護者へ通知
create or replace function approve_enrollment_form(p_form_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_child_id uuid;
  v_sub record;
  v_data jsonb;
  v_gender text;
  v_household_id uuid;
  v_rep uuid;
  v_p jsonb;
begin
  select office_id, child_id into v_office_id, v_child_id from enrollment_forms where id = p_form_id;
  if v_office_id is null then
    raise exception 'form not found';
  end if;
  if not is_childcare_admin(v_office_id) then
    raise exception 'not authorized';
  end if;

  select * into v_sub from enrollment_form_submissions
  where form_id = p_form_id and review_status = 'pending'
  order by version desc limit 1;
  if v_sub.id is null then
    raise exception 'no pending submission';
  end if;
  v_data := v_sub.data;

  -- children 正本反映(コア項目)
  v_gender := nullif(trim(v_data->'basic'->>'gender'), '');
  if v_gender is not null and v_gender not in ('男', '女', 'その他') then
    raise exception 'invalid gender value %', v_gender;
  end if;
  update children set
    full_name = coalesce(nullif(trim(v_data->'basic'->>'full_name'), ''), full_name),
    name_kana = coalesce(nullif(trim(v_data->'basic'->>'name_kana'), ''), name_kana),
    display_name = coalesce(nullif(trim(v_data->'basic'->>'nickname'), ''),
                            nullif(trim(v_data->'basic'->>'full_name'), ''), display_name),
    gender = coalesce(v_gender, gender),
    birth_date = coalesce(nullif(trim(v_data->'basic'->>'birth_date'), '')::date, birth_date)
  where id = v_child_id;

  -- 世帯(無ければ作成・代表=主たる保護者)+住所反映+保護者の世帯リンク補完
  select household_id into v_household_id from children where id = v_child_id;
  if v_household_id is null then
    select guardian_id into v_rep from guardian_child_links
    where child_id = v_child_id and role = 'primary' limit 1;
    insert into households (representative_guardian_id) values (v_rep) returning id into v_household_id;
    update children set household_id = v_household_id where id = v_child_id;
  end if;
  update households set
    postal_code = nullif(trim(v_data->'address'->>'postal_code'), ''),
    prefecture = nullif(trim(v_data->'address'->>'prefecture'), ''),
    city = nullif(trim(v_data->'address'->>'city'), ''),
    town = nullif(trim(v_data->'address'->>'town'), ''),
    address_line = nullif(trim(v_data->'address'->>'address_line'), ''),
    building = nullif(trim(v_data->'address'->>'building'), '')
  where id = v_household_id;
  update guardians g set household_id = v_household_id
  where g.household_id is null
    and exists (select 1 from guardian_child_links gcl
                where gcl.guardian_id = g.id and gcl.child_id = v_child_id);

  -- 代理送迎者 → pickup_persons(202と共通の人物マスタ。確認済み身分証は保持)
  for v_p in select * from jsonb_array_elements(coalesce(v_data->'pickup'->'proxies', '[]'::jsonb)) loop
    if coalesce(trim(v_p->>'name'), '') <> '' then
      insert into pickup_persons (child_id, name, relationship, phone, created_by_guardian_id)
      values (v_child_id, trim(v_p->>'name'), nullif(trim(v_p->>'relationship'), ''),
              nullif(trim(v_p->>'phone'), ''), v_sub.submitted_by_guardian_id)
      on conflict (child_id, name) do update
      set relationship = coalesce(excluded.relationship, pickup_persons.relationship),
          phone = coalesce(excluded.phone, pickup_persons.phone);
    end if;
  end loop;

  update enrollment_form_submissions
  set review_status = 'approved', reviewed_by = my_employee_id(), reviewed_at = now()
  where id = v_sub.id;
  update enrollment_forms set status = 'approved' where id = p_form_id;

  insert into notifications (notification_type, title, body, channels, target_guardian_id, payload, status)
  values ('enrollment_form', '【入園手続き】登録が完了しました',
          '入園時基本情報が園に承認されました。ありがとうございました。',
          array['push'], v_sub.submitted_by_guardian_id,
          jsonb_build_object('form_id', p_form_id::text), 'pending');
end;
$$;

-- 6-5) 園側: 取消(管理者以上・承認済みは取消不可)
create or replace function cancel_enrollment_form(p_form_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_status text;
begin
  select office_id, status into v_office_id, v_status from enrollment_forms where id = p_form_id;
  if v_office_id is null then
    raise exception 'form not found';
  end if;
  if not is_childcare_admin(v_office_id) then
    raise exception 'not authorized';
  end if;
  if v_status = 'approved' then
    raise exception 'approved form cannot be cancelled';
  end if;
  update enrollment_forms set status = 'cancelled' where id = p_form_id;
end;
$$;

-- 7) 正式入園(仮登録→在籍中+クラス割当。主任以上=create_childと同線)
create or replace function promote_provisional_child(p_child_id uuid, p_class_id uuid, p_start_date date)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_status text;
  v_class_office_id uuid;
begin
  select office_id, enrollment_status into v_office_id, v_status from children where id = p_child_id;
  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not manages_childcare(v_office_id) then
    raise exception 'not authorized';
  end if;
  if v_status <> '入園予定' then
    raise exception 'child is not provisional';
  end if;
  if p_class_id is null or p_start_date is null then
    raise exception 'class and start date required';
  end if;
  select office_id into v_class_office_id from childcare_classes where id = p_class_id;
  if v_class_office_id is null or v_class_office_id <> v_office_id then
    raise exception 'class does not belong to this office';
  end if;

  update children
  set enrollment_status = '在籍中', enrollment_date = p_start_date
  where id = p_child_id;

  insert into child_class_enrollments (child_id, class_id, effective_start_date, effective_end_date)
  values (p_child_id, p_class_id, p_start_date, null);
end;
$$;
