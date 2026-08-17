-- 224: 食材チェック基盤(M6 Phase 4・草案§12-14)。
-- 1) food_items / food_checklist_versions(版・回数要件) / food_checklist_items(段階・必須目安・代替グループ)
-- 2) child_food_records: 食材経験記録(削除しない=履歴原則)。症状詳細・園確認列つき
-- 3) フラグ food_check_enabled(既定OFF)
-- 4) RPC: 保護者=fetch_food_checklist(状態導出つき)/record_food_intake(症状あり→管理職へ重要プッシュ)
--         園側=fetch_food_symptom_queue/confirm_food_symptom(管理者以上)/fetch_child_food_progress(全職員・台帳用)
-- 初期マスター(§13.3/13.4)は別SQLで投入(俊承認後)。冪等: テーブル=素create・関数=create or replace。

-- 1) マスター
create table food_items (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  synonyms text[],
  food_group text not null,
  allergen_code text,
  menu_item_code text,
  created_at timestamptz not null default now()
);
comment on table food_items is '食材マスター(224)。allergen_code/menu_item_codeは将来の献立連携用の予約列';
alter table food_items enable row level security;

create table food_checklist_versions (
  id uuid primary key default gen_random_uuid(),
  version int not null unique,
  status text not null default 'draft' check (status in ('draft', 'published', 'archived')),
  required_times int not null default 2,
  note text,
  published_by uuid references employees(id),
  published_at timestamptz,
  created_at timestamptz not null default now()
);
comment on column food_checklist_versions.required_times is '問題なし完了に必要な家庭での確認回数(§14.3・版ごとに変更可)';
alter table food_checklist_versions enable row level security;

create table food_checklist_items (
  id uuid primary key default gen_random_uuid(),
  version_id uuid not null references food_checklist_versions(id) on delete cascade,
  food_item_id uuid not null references food_items(id),
  stage text not null check (stage in ('初期', '中期', '後期', '完了期')),
  category text not null check (category in ('required', 'reference')),
  alt_group text,
  alt_group_rule text check (alt_group_rule in ('any', 'all')),
  display_order int not null default 0,
  unique (version_id, food_item_id)
);
alter table food_checklist_items enable row level security;

-- 2) 食材経験記録(削除しない)
create table child_food_records (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  food_item_id uuid not null references food_items(id),
  intake_date date not null,
  multiple_confirmed boolean not null default false,
  result text not null check (result in ('ok', 'symptom')),
  symptoms text,
  onset_note text,
  amount_note text,
  medical_status text,
  note text,
  recorded_by_guardian_id uuid references guardians(id),
  staff_confirmed_by uuid references employees(id),
  staff_confirmed_at timestamptz,
  staff_confirm_note text,
  created_at timestamptz not null default now()
);
create index idx_child_food_records_child on child_food_records(child_id, food_item_id);
create index idx_child_food_records_symptom on child_food_records(result) where result = 'symptom' and staff_confirmed_at is null;
alter table child_food_records enable row level security;

-- 3) 機能フラグ
insert into feature_flags (feature_key, name, description, default_enabled)
select 'food_check_enabled', '食材チェック',
       '保護者による家庭での食材経験の記録・症状あり通知・園確認(M6 Phase 4)', false
where not exists (select 1 from feature_flags where feature_key = 'food_check_enabled');

create or replace function is_food_check_enabled_for_office(p_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select is_feature_enabled_for_office('food_check_enabled', p_office_id);
$$;

create or replace function is_food_check_enabled_for_child(p_child_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select guardian_has_child_access(p_child_id)
     and is_food_check_enabled_for_office((select office_id from children where id = p_child_id));
$$;

-- 4-1) 保護者: チェックリスト取得(公開中の最新版+項目ごとの状態導出)
create or replace function fetch_food_checklist(p_child_id uuid)
returns table (
  food_item_id uuid,
  name text,
  food_group text,
  stage text,
  category text,
  alt_group text,
  alt_group_rule text,
  display_order int,
  required_times int,
  ok_count bigint,
  multiple_confirmed boolean,
  has_unconfirmed_symptom boolean,
  has_confirmed_symptom boolean,
  item_status text
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not is_food_check_enabled_for_child(p_child_id) then
    raise exception 'not authorized';
  end if;
  return query
  with v as (
    select id, food_checklist_versions.required_times from food_checklist_versions
    where status = 'published' order by version desc limit 1
  ),
  rec as (
    select r.food_item_id as fid,
      count(*) filter (where r.result = 'ok') as ok_count,
      bool_or(r.result = 'ok' and r.multiple_confirmed) as multi_ok,
      bool_or(r.result = 'symptom' and r.staff_confirmed_at is null) as sym_open,
      bool_or(r.result = 'symptom' and r.staff_confirmed_at is not null) as sym_done
    from child_food_records r
    where r.child_id = p_child_id
    group by r.food_item_id
  )
  select fi.id, fi.name, fi.food_group, ci.stage, ci.category, ci.alt_group, ci.alt_group_rule,
    ci.display_order, v.required_times,
    coalesce(rec.ok_count, 0), coalesce(rec.multi_ok, false),
    coalesce(rec.sym_open, false), coalesce(rec.sym_done, false),
    case
      when coalesce(rec.sym_open, false) then '症状あり・園確認待ち'
      when coalesce(rec.sym_done, false) then '医療確認中'
      when coalesce(rec.multi_ok, false) or coalesce(rec.ok_count, 0) >= v.required_times then '問題なし登録済み'
      when coalesce(rec.ok_count, 0) > 0 then '家庭で確認中'
      else '未確認'
    end
  from v
  join food_checklist_items ci on ci.version_id = v.id
  join food_items fi on fi.id = ci.food_item_id
  left join rec on rec.fid = fi.id
  order by ci.stage, ci.display_order;
end;
$$;

-- 4-2) 保護者: 食材経験の登録(症状あり→施設の管理職へ重要プッシュ)
create or replace function record_food_intake(
  p_child_id uuid,
  p_food_item_id uuid,
  p_intake_date date,
  p_multiple_confirmed boolean,
  p_result text,
  p_symptoms text default null,
  p_onset_note text default null,
  p_amount_note text default null,
  p_medical_status text default null,
  p_note text default null
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid;
  v_office_id uuid;
  v_child_name text;
  v_food_name text;
begin
  if not is_food_check_enabled_for_child(p_child_id) then
    raise exception 'not authorized';
  end if;
  if p_result not in ('ok', 'symptom') then
    raise exception 'invalid result';
  end if;
  if p_intake_date is null or p_intake_date > current_date then
    raise exception 'invalid intake date';
  end if;
  if p_result = 'symptom' and coalesce(trim(p_symptoms), '') = '' then
    raise exception 'symptoms required';
  end if;

  insert into child_food_records (
    child_id, food_item_id, intake_date, multiple_confirmed, result,
    symptoms, onset_note, amount_note, medical_status, note, recorded_by_guardian_id
  ) values (
    p_child_id, p_food_item_id, p_intake_date, coalesce(p_multiple_confirmed, false), p_result,
    p_symptoms, p_onset_note, p_amount_note, p_medical_status, p_note, my_guardian_id()
  ) returning id into v_id;

  if p_result = 'symptom' then
    select c.office_id, c.display_name into v_office_id, v_child_name from children c where c.id = p_child_id;
    select name into v_food_name from food_items where id = p_food_item_id;
    insert into notifications (notification_type, title, body, channels, target_employee_id, payload, status)
    select 'food_symptom',
      '【食材チェック】症状ありの報告',
      v_child_name || 'さん: ' || v_food_name || ' で症状の報告がありました。内容を確認してください。',
      array['push'], emp,
      jsonb_build_object('record_id', v_id::text, 'child_id', p_child_id::text), 'pending'
    from childcare_office_manager_employee_ids(v_office_id) emp;
  end if;

  return v_id;
end;
$$;

-- 4-3) 園側: 症状あり未処理一覧(管理者以上)
create or replace function fetch_food_symptom_queue(p_office_id uuid)
returns table (
  record_id uuid,
  child_id uuid,
  child_name text,
  food_name text,
  intake_date date,
  symptoms text,
  onset_note text,
  amount_note text,
  medical_status text,
  note text,
  created_at timestamptz,
  confirmed boolean,
  confirmed_at timestamptz,
  confirm_note text
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not is_childcare_admin(p_office_id) then
    raise exception 'not authorized';
  end if;
  return query
  select r.id, c.id, c.display_name, fi.name, r.intake_date,
    r.symptoms, r.onset_note, r.amount_note, r.medical_status, r.note, r.created_at,
    r.staff_confirmed_at is not null, r.staff_confirmed_at, r.staff_confirm_note
  from child_food_records r
  join children c on c.id = r.child_id and c.office_id = p_office_id
  join food_items fi on fi.id = r.food_item_id
  where r.result = 'symptom'
  order by (r.staff_confirmed_at is null) desc, r.created_at desc;
end;
$$;

-- 4-4) 園側: 症状の園確認(管理者以上)
create or replace function confirm_food_symptom(p_record_id uuid, p_note text default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
begin
  select c.office_id into v_office_id
  from child_food_records r join children c on c.id = r.child_id
  where r.id = p_record_id and r.result = 'symptom';
  if v_office_id is null then
    raise exception 'symptom record not found';
  end if;
  if not is_childcare_admin(v_office_id) then
    raise exception 'not authorized';
  end if;
  update child_food_records
  set staff_confirmed_by = my_employee_id(), staff_confirmed_at = now(), staff_confirm_note = p_note
  where id = p_record_id and staff_confirmed_at is null;
end;
$$;

-- 4-5) 園側: 台帳用の進捗(全職員)。段階ごとの必須項目の完了数(代替グループはいずれかでOKとして集計)
create or replace function fetch_child_food_progress(p_child_id uuid)
returns table (
  stage text,
  required_total bigint,
  required_done bigint,
  symptom_count bigint
)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_office_id uuid;
begin
  select office_id into v_office_id from children where id = p_child_id;
  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;
  return query
  with v as (
    select id, food_checklist_versions.required_times from food_checklist_versions
    where status = 'published' order by version desc limit 1
  ),
  items as (
    select ci.stage as st, ci.food_item_id, coalesce(ci.alt_group, ci.food_item_id::text) as grp,
      ci.alt_group_rule, v.required_times
    from v join food_checklist_items ci on ci.version_id = v.id
    where ci.category = 'required'
  ),
  done_items as (
    select i.st, i.grp, i.food_item_id,
      (select count(*) filter (where r.result = 'ok') >= i.required_times
              or bool_or(r.result = 'ok' and r.multiple_confirmed)
       from child_food_records r
       where r.child_id = p_child_id and r.food_item_id = i.food_item_id) as is_done,
      (select count(*) from child_food_records r
       where r.child_id = p_child_id and r.food_item_id = i.food_item_id and r.result = 'symptom') as sym
    from items i
  ),
  grp_agg as (
    select st, grp,
      case when max(coalesce((select alt_group_rule from items i2 where i2.grp = done_items.grp limit 1), 'any')) = 'all'
        then bool_and(coalesce(is_done, false))
        else bool_or(coalesce(is_done, false))
      end as grp_done,
      sum(coalesce(sym, 0)) as sym_sum
    from done_items
    group by st, grp
  )
  select st, count(*), count(*) filter (where grp_done), coalesce(sum(sym_sum), 0)
  from grp_agg
  group by st
  order by array_position(array['初期','中期','後期','完了期'], st);
end;
$$;
