-- 222: 園児情報の園側修正(M6 Phase 3a拡張・俊指示 2026-08-17)。
-- 保護者が入力する内容(入園時基本情報)を園側(管理者以上)でも修正できるようにする。
-- 方式: 園側修正=新しい承認済み版としてスナップショットへ追加し、承認時と同じ正本反映を行う
--       (台帳・保護者側の表示は即時更新・履歴は版として残る)。
-- 1) apply_enrollment_register: 承認時の正本反映(children/households/pickup_persons)を共通関数化
-- 2) approve_enrollment_form 再定義: 反映部分を 1) の呼び出しに置換(挙動は不変)
-- 3) update_child_register_by_staff: 園側修正(管理者以上)。保護者の提出が確認待ち(submitted)の間はブロック。
--    フォームが無い園児(紙運用)は承認済みフォームを新規作成してスナップショットを積む。
-- 冪等: create or replace のみ。

-- 1) 正本反映の共通関数(approve と園側修正の両方が使う)
create or replace function apply_enrollment_register(p_child_id uuid, p_data jsonb, p_guardian_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_gender text;
  v_household_id uuid;
  v_rep uuid;
  v_p jsonb;
begin
  -- children 正本反映(コア項目)
  v_gender := nullif(trim(p_data->'basic'->>'gender'), '');
  if v_gender is not null and v_gender not in ('男', '女', 'その他') then
    raise exception 'invalid gender value %', v_gender;
  end if;
  update children set
    full_name = coalesce(nullif(trim(p_data->'basic'->>'full_name'), ''), full_name),
    name_kana = coalesce(nullif(trim(p_data->'basic'->>'name_kana'), ''), name_kana),
    display_name = coalesce(nullif(trim(p_data->'basic'->>'nickname'), ''),
                            nullif(trim(p_data->'basic'->>'full_name'), ''), display_name),
    gender = coalesce(v_gender, gender),
    birth_date = coalesce(nullif(trim(p_data->'basic'->>'birth_date'), '')::date, birth_date)
  where id = p_child_id;

  -- 世帯(無ければ作成・代表=主たる保護者)+住所反映+保護者の世帯リンク補完
  select household_id into v_household_id from children where id = p_child_id;
  if v_household_id is null then
    select guardian_id into v_rep from guardian_child_links
    where child_id = p_child_id and role = 'primary' limit 1;
    insert into households (representative_guardian_id) values (v_rep) returning id into v_household_id;
    update children set household_id = v_household_id where id = p_child_id;
  end if;
  update households set
    postal_code = nullif(trim(p_data->'address'->>'postal_code'), ''),
    prefecture = nullif(trim(p_data->'address'->>'prefecture'), ''),
    city = nullif(trim(p_data->'address'->>'city'), ''),
    town = nullif(trim(p_data->'address'->>'town'), ''),
    address_line = nullif(trim(p_data->'address'->>'address_line'), ''),
    building = nullif(trim(p_data->'address'->>'building'), '')
  where id = v_household_id;
  update guardians g set household_id = v_household_id
  where g.household_id is null
    and exists (select 1 from guardian_child_links gcl
                where gcl.guardian_id = g.id and gcl.child_id = p_child_id);

  -- 代理送迎者 → pickup_persons(202と共通の人物マスタ。確認済み身分証は保持)
  for v_p in select * from jsonb_array_elements(coalesce(p_data->'pickup'->'proxies', '[]'::jsonb)) loop
    if coalesce(trim(v_p->>'name'), '') <> '' then
      insert into pickup_persons (child_id, name, relationship, phone, created_by_guardian_id)
      values (p_child_id, trim(v_p->>'name'), nullif(trim(v_p->>'relationship'), ''),
              nullif(trim(v_p->>'phone'), ''), p_guardian_id)
      on conflict (child_id, name) do update
      set relationship = coalesce(excluded.relationship, pickup_persons.relationship),
          phone = coalesce(excluded.phone, pickup_persons.phone);
    end if;
  end loop;
end;
$$;

-- 2) 承認RPC再定義(反映部分を共通関数へ。挙動は不変)
create or replace function approve_enrollment_form(p_form_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_child_id uuid;
  v_sub record;
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

  perform apply_enrollment_register(v_child_id, v_sub.data, v_sub.submitted_by_guardian_id);

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

-- 3) 園側修正(管理者以上)。新しい承認済み版として積み、正本反映する。
create or replace function update_child_register_by_staff(p_child_id uuid, p_data jsonb)
returns int
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_form record;
  v_version int;
begin
  select office_id into v_office_id from children where id = p_child_id;
  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not is_childcare_admin(v_office_id) then
    raise exception 'not authorized';
  end if;
  if p_data is null then
    raise exception 'data required';
  end if;

  select * into v_form from enrollment_forms where child_id = p_child_id;

  if v_form.id is null then
    -- 紙運用等でフォームが無い園児: 承認済みフォームを新規作成してスナップショットを積む
    insert into enrollment_forms (child_id, office_id, status, form_data, current_step, last_saved_at)
    values (p_child_id, v_office_id, 'approved', p_data, 11, now())
    returning * into v_form;
  else
    if v_form.status = 'submitted' then
      raise exception 'guardian submission is pending review';
    end if;
    -- 承認済みなら form_data も最新化(次回の変更申請の起点を揃える)。保護者の下書き中はそのまま。
    if v_form.status in ('approved', 'cancelled') then
      update enrollment_forms set form_data = p_data, status = 'approved' where id = v_form.id;
    end if;
  end if;

  select coalesce(max(version), 0) + 1 into v_version
  from enrollment_form_submissions where form_id = v_form.id;

  insert into enrollment_form_submissions (
    form_id, version, data, submitted_by_guardian_id, review_status, review_message, reviewed_by, reviewed_at
  ) values (
    v_form.id, v_version, p_data, null, 'approved', '園側修正', my_employee_id(), now()
  );

  perform apply_enrollment_register(p_child_id, p_data, null);
  return v_version;
end;
$$;
