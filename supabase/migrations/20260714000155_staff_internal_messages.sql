-- 園内連絡(職員間コミュニケーション)Phase 2: DB。
-- 設計: docs/Ohana_Works_園内連絡_実装設計書_v1_2026-07-31.md(§5・§6・§9)。
-- 判断: §11 は既定値で進行。§6.5 は「下書き+確定の両方を判定対象」で確定(本番分布で
--       confirmed-only へ切替可能な設定を維持)。
--
-- 方針:
--  - 時間帯区分(早番/遅番)は施設別マスタ staff_time_bands。中番はマスタに置かず導出
--    (§5.1)。band 宛ての中番は band_id = null で表す(§6.1 の「どちらの帯にも該当しない」)。
--  - 宛先該当の判定は is_staff_message_addressed_to() 1関数に集約(§6.1)。フロントで再実装しない。
--    band はシフト(draft+confirmed)から動的解決=シフト差替に追従(§6.3)。
--  - 閲覧は自施設全職員、確認義務(acknowledge)は宛先該当者のみ(§6.2)。
--  - 物理削除しない=論理削除のみ(§5.2)。

-- ============================================================
-- 5.1 時間帯区分マスタ(施設別・人は登録しない)
-- ============================================================
create table staff_time_bands (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id),
  name text not null,
  sort_order int not null default 0,
  start_from time, start_until time,   -- シフト開始時刻がこの範囲=該当(早番用)
  end_from time, end_until time,       -- シフト終了時刻がこの範囲=該当(遅番用)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (office_id, name)
);
create trigger trg_staff_time_bands_updated_at before update on staff_time_bands
  for each row execute function set_updated_at();

-- シード(冪等・office_code で解決。早番窓幅30分は仮値=Phase1本番分布で調整可)
-- 中番は「導出帯」= 開始窓・終了窓が両方 NULL の実在行。判定は「他のどの帯にも該当しない
-- シフトがある」(§6.1)。実在行にすることで target_type='band' なら band_id NOT NULL を張れる。
insert into staff_time_bands (office_id, name, sort_order, start_from, start_until, end_from, end_until)
select o.id, v.name, v.so, v.sf, v.su, v.ef, v.eu
from (values
  ('O','早番',10,time '07:00',time '07:30',null::time,null::time),
  ('O','中番',20,null::time,null::time,null::time,null::time),
  ('O','遅番',30,null::time,null::time,time '19:00',time '23:59'),
  ('M','早番',10,time '07:00',time '07:30',null::time,null::time),
  ('M','中番',20,null::time,null::time,null::time,null::time),
  ('M','遅番',30,null::time,null::time,time '20:00',time '23:59'),
  ('H','早番',10,time '08:00',time '08:30',null::time,null::time),
  ('H','中番',20,null::time,null::time,null::time,null::time),
  ('H','遅番',30,null::time,null::time,time '19:00',time '23:59'),
  ('S','早番',10,time '08:00',time '08:30',null::time,null::time),
  ('S','中番',20,null::time,null::time,null::time,null::time),
  ('S','遅番',30,null::time,null::time,time '19:00',time '23:59')
) as v(office_code,name,so,sf,su,ef,eu)
join offices o on o.office_code = v.office_code
on conflict (office_id, name) do nothing;

-- ============================================================
-- 5.4 クラス担任(職員マスタから設定。人を帯に置かない原則の例外=日々変わらないため)
-- ============================================================
create table class_homeroom_assignments (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references childcare_classes(id),
  employee_id uuid not null references employees(id),
  assigned_at timestamptz not null default now(),
  unassigned_at timestamptz
);
create index idx_cha_class on class_homeroom_assignments (class_id) where unassigned_at is null;
create index idx_cha_employee on class_homeroom_assignments (employee_id) where unassigned_at is null;

-- ============================================================
-- 5.2 連絡本体 / 5.3 宛先 / 5.5 確認 / 5.6 コメント(作成のみ)
-- ============================================================
create table staff_messages (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id),
  author_employee_id uuid not null references employees(id),
  body text not null check (length(trim(body)) > 0),
  target_date date,   -- 時間帯宛て・クラス宛てで必須(「明日の早番へ」の"明日")
  deleted_at timestamptz,  -- 論理削除のみ(物理削除しない)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_staff_messages_updated_at before update on staff_messages
  for each row execute function set_updated_at();
create index idx_staff_messages_office on staff_messages (office_id, created_at desc) where deleted_at is null;

create table staff_message_targets (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references staff_messages(id) on delete cascade,
  -- 将来の区分追加はこの CHECK への値追加で対応する。
  target_type text not null check (target_type in ('individual', 'band', 'facility', 'class')),
  employee_id uuid references employees(id),  -- individual で必須
  band_id uuid references staff_time_bands(id), -- band で必須(中番も実在行=band_id NOT NULL)
  class_id uuid references childcare_classes(id), -- class で必須
  created_at timestamptz not null default now(),
  -- 種別ごとの必須項目を担保(中番も staff_time_bands 実在行のため band は band_id 必須)
  constraint staff_message_targets_shape check (
    (target_type = 'individual' and employee_id is not null and band_id is null and class_id is null) or
    (target_type = 'band' and band_id is not null and employee_id is null and class_id is null) or
    (target_type = 'facility' and employee_id is null and band_id is null and class_id is null) or
    (target_type = 'class' and class_id is not null and employee_id is null and band_id is null)
  )
);
create index idx_smt_message on staff_message_targets (message_id);

create table staff_message_reads (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references staff_messages(id) on delete cascade,
  employee_id uuid not null references employees(id),
  opened_at timestamptz,        -- 本文を開いた時点
  acknowledged_at timestamptz,  -- 「確認しました」ボタン=管理側が見るのはこちら
  unique (message_id, employee_id)
);
create index idx_smr_message on staff_message_reads (message_id);

-- コメントは作成のみ(RPC・UI・アラート連動は今回実装しない)
create table staff_message_comments (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references staff_messages(id) on delete cascade,
  author_employee_id uuid not null references employees(id),
  body text not null,
  created_at timestamptz not null default now()
);

-- ============================================================
-- 施設の職員母集団(定義の二重化禁止・単一の正)
--   office_assigned_employee_ids: 在籍職員(有効 employee_office_assignments)。園内連絡 facility の母集団。
--   office_accessible_employee_ids: 在籍 + 管理ロール + 統括 + 付与。PINピッカーの母集団。
--     在籍ロジックは office_assigned を土台にして二重化しない。pin-staff-picker はこの関数を呼ぶ形へ
--     寄せる(Edge Function 再デプロイ=別作業。155適用後に移行)。
-- ============================================================
create or replace function office_assigned_employee_ids(p_office_id uuid)
returns setof uuid language sql stable security definer set search_path = public
as $$
  select eoa.employee_id from employee_office_assignments eoa
  where eoa.office_id = p_office_id
    and eoa.start_date <= current_date and (eoa.end_date is null or eoa.end_date >= current_date);
$$;

create or replace function office_accessible_employee_ids(p_office_id uuid)
returns setof uuid language sql stable security definer set search_path = public
as $$
  select t from office_assigned_employee_ids(p_office_id) t
  union
  select er.employee_id from employee_roles er join roles r on r.id = er.role_id
  where r.code in ('system_admin', 'executive_director')
     or (r.code in ('director', 'chief', 'office_manager') and (er.office_id is null or er.office_id = p_office_id))
  union
  select g.grantee_employee_id from multi_office_authority_grants g
  where g.office_id = p_office_id and g.revoked_at is null;
$$;

-- ============================================================
-- 6.1 宛先該当の判定(1関数に集約。band はシフト draft+confirmed から動的解決)
-- ============================================================
create or replace function is_staff_message_addressed_to(p_message_id uuid, p_employee_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from staff_messages m
    join staff_message_targets t on t.message_id = m.id
    where m.id = p_message_id and m.deleted_at is null
      and (
        -- individual
        (t.target_type = 'individual' and t.employee_id = p_employee_id)
        -- facility: 当該施設の在籍職員(単一の正=office_assigned_employee_ids)
        or (t.target_type = 'facility' and p_employee_id in (select office_assigned_employee_ids(m.office_id)))
        -- class: 当該クラスの担任(現任)
        or (t.target_type = 'class' and exists (
              select 1 from class_homeroom_assignments cha
              where cha.class_id = t.class_id and cha.employee_id = p_employee_id and cha.unassigned_at is null))
        -- band: target_date のシフト(draft+confirmed)で判定。中番も実在行(両窓NULL=導出帯)
        or (t.target_type = 'band' and m.target_date is not null and exists (
              select 1 from shifts s join staff_time_bands b on b.id = t.band_id
              where s.employee_id = p_employee_id and s.work_date = m.target_date
                and s.office_id = m.office_id and s.status in ('draft', 'confirmed')
                and (
                  case
                    when b.start_from is not null then s.start_time between b.start_from and b.start_until  -- 早番
                    when b.end_from is not null then s.end_time between b.end_from and b.end_until          -- 遅番
                    else not exists (  -- 中番(導出帯): どの早番/遅番窓にも該当しないシフト
                      select 1 from staff_time_bands b2 where b2.office_id = m.office_id and (
                        (b2.start_from is not null and s.start_time between b2.start_from and b2.start_until) or
                        (b2.end_from is not null and s.end_time between b2.end_from and b2.end_until)))
                  end
                )))
      )
  );
$$;

-- ============================================================
-- RLS: 閲覧は自施設の全職員(§6.2)。書き込みは全てRPC経由(SELECTのみポリシー)。
-- ============================================================
alter table staff_messages enable row level security;
create policy staff_messages_select_office on staff_messages
  for select using (deleted_at is null and has_childcare_office_access(office_id));
alter table staff_message_targets enable row level security;
create policy staff_message_targets_select on staff_message_targets
  for select using (exists (select 1 from staff_messages m where m.id = message_id and m.deleted_at is null and has_childcare_office_access(m.office_id)));
alter table staff_message_reads enable row level security;
create policy staff_message_reads_select on staff_message_reads
  for select using (exists (select 1 from staff_messages m where m.id = message_id and has_childcare_office_access(m.office_id)));
alter table staff_message_comments enable row level security;
create policy staff_message_comments_select on staff_message_comments
  for select using (exists (select 1 from staff_messages m where m.id = message_id and m.deleted_at is null and has_childcare_office_access(m.office_id)));
alter table staff_time_bands enable row level security;
create policy staff_time_bands_select on staff_time_bands
  for select using (has_childcare_office_access(office_id));
alter table class_homeroom_assignments enable row level security;
create policy class_homeroom_assignments_select on class_homeroom_assignments
  for select using (exists (select 1 from childcare_classes cc where cc.id = class_id and has_childcare_office_access(cc.office_id)));

-- ============================================================
-- RPC
-- ============================================================
-- 作成: 自施設の職員が、自施設内の宛先へ送る。band/class 宛ては target_date 必須。
create or replace function create_staff_message(p_office_id uuid, p_body text, p_target_date date, p_targets jsonb)
returns uuid language plpgsql security definer set search_path = public
as $$
declare v_id uuid; v_t jsonb; v_type text;
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  if coalesce(trim(p_body),'')='' then raise exception 'body required'; end if;
  if p_targets is null or jsonb_array_length(p_targets)=0 then raise exception 'target required'; end if;

  insert into staff_messages (office_id, author_employee_id, body, target_date)
  values (p_office_id, my_employee_id(), p_body, p_target_date) returning id into v_id;

  for v_t in select * from jsonb_array_elements(p_targets) loop
    v_type := v_t->>'type';
    if v_type in ('band','class') and p_target_date is null then
      raise exception 'target_date is required for band/class targets';
    end if;
    insert into staff_message_targets (message_id, target_type, employee_id, band_id, class_id)
    values (v_id, v_type,
      nullif(v_t->>'employee_id','')::uuid, nullif(v_t->>'band_id','')::uuid, nullif(v_t->>'class_id','')::uuid);
  end loop;
  return v_id;
end;
$$;

-- 論理削除(送信者 or 主任以上)
create or replace function delete_staff_message(p_message_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare v_office uuid; v_author uuid;
begin
  select office_id, author_employee_id into v_office, v_author from staff_messages where id = p_message_id and deleted_at is null;
  if v_office is null then raise exception 'not found'; end if;
  if v_author <> my_employee_id() and not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  update staff_messages set deleted_at = now() where id = p_message_id;
end;
$$;

-- 開封(自施設の閲覧者)/ 確認(宛先該当者のみ)
create or replace function mark_staff_message_opened(p_message_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
begin
  insert into staff_message_reads (message_id, employee_id, opened_at)
  values (p_message_id, my_employee_id(), now())
  on conflict (message_id, employee_id) do update set opened_at = coalesce(staff_message_reads.opened_at, now());
end;
$$;

create or replace function acknowledge_staff_message(p_message_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if not is_staff_message_addressed_to(p_message_id, my_employee_id()) then
    raise exception 'not addressed to you';
  end if;
  insert into staff_message_reads (message_id, employee_id, opened_at, acknowledged_at)
  values (p_message_id, my_employee_id(), now(), now())
  on conflict (message_id, employee_id) do update
    set acknowledged_at = coalesce(staff_message_reads.acknowledged_at, now()),
        opened_at = coalesce(staff_message_reads.opened_at, now());
end;
$$;

-- ログイン中本人の未確認(宛先該当かつ acknowledged 無し)件数=アラート用
create or replace function fetch_my_unacknowledged_staff_message_count(p_office_id uuid)
returns int language sql stable security definer set search_path = public
as $$
  select count(*)::int from staff_messages m
  where m.office_id = p_office_id and m.deleted_at is null
    and is_staff_message_addressed_to(m.id, my_employee_id())
    and not exists (select 1 from staff_message_reads r
                    where r.message_id = m.id and r.employee_id = my_employee_id() and r.acknowledged_at is not null);
$$;

-- 送信者・主任以上向け: 宛先該当者の確認状況(確認済み/未確認)
create or replace function fetch_staff_message_ack_summary(p_message_id uuid)
returns table (employee_id uuid, acknowledged boolean)
language sql stable security definer set search_path = public
as $$
  select e.id,
    exists (select 1 from staff_message_reads r where r.message_id = p_message_id and r.employee_id = e.id and r.acknowledged_at is not null)
  from staff_messages m
  join employees e on is_staff_message_addressed_to(m.id, e.id)
  where m.id = p_message_id
    and (m.author_employee_id = my_employee_id() or manages_childcare(m.office_id));
$$;

-- 担任の設定/解除(職員マスタから。主任以上)
create or replace function set_class_homeroom(p_class_id uuid, p_employee_id uuid, p_assign boolean)
returns void language plpgsql security definer set search_path = public
as $$
declare v_office uuid;
begin
  select office_id into v_office from childcare_classes where id = p_class_id;
  if v_office is null or not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  if p_assign then
    if not exists (select 1 from class_homeroom_assignments where class_id=p_class_id and employee_id=p_employee_id and unassigned_at is null) then
      insert into class_homeroom_assignments (class_id, employee_id) values (p_class_id, p_employee_id);
    end if;
  else
    update class_homeroom_assignments set unassigned_at = now()
    where class_id=p_class_id and employee_id=p_employee_id and unassigned_at is null;
  end if;
end;
$$;

-- ============================================================
-- 6.4 クラス連絡の機能フラグ(施設別。大和のみONは seed_staging.ts で投入)
-- ============================================================
insert into feature_flags (feature_key, name, description, default_enabled) values
  ('class_messaging_enabled', 'クラス宛て園内連絡', '園内連絡のクラス宛て機能(合同保育の施設ではOFF)', false)
on conflict (feature_key) do nothing;

-- ============================================================
-- 9. 園内記録の「申し送り」区分を廃止し園内連絡へ移す
-- ============================================================
-- 既存の handover 行を other へ変換(本番は145未適用で0件・ステージングのテストデータのみ)
update child_internal_notes
set category = 'other', body = '【旧:申し送り】' || body
where category = 'handover';
-- CHECK から handover を除去(4区分へ)
alter table child_internal_notes drop constraint child_internal_notes_category_check;
alter table child_internal_notes add constraint child_internal_notes_category_check
  check (category in ('observation', 'guardian_contact', 'external_agency', 'other'));
-- AI参照の許可区分を observation のみに
create or replace function fetch_child_internal_notes_for_ai(p_child_id uuid, p_from date, p_to date)
returns table (id uuid, body text)
language plpgsql security definer set search_path = public
as $$
declare v_office_id uuid;
begin
  select cc.office_id into v_office_id
  from child_class_enrollments cce join childcare_classes cc on cc.id = cce.class_id
  where cce.child_id = p_child_id and cce.effective_end_date is null limit 1;
  if v_office_id is null then raise exception 'child not found or not currently enrolled'; end if;
  if not is_child_internal_notes_enabled_for_office(v_office_id) then raise exception 'feature not enabled for this office'; end if;
  if not is_child_internal_notes_chief(v_office_id) then raise exception 'not authorized'; end if;
  if p_from is null or p_to is null then raise exception 'p_from and p_to are required'; end if;

  perform log_sensitive_access(
    '園内記録AI参照(fetch_child_internal_notes_for_ai)', null,
    format('child_id=%s, from=%s, to=%s', p_child_id, p_from, p_to));

  return query
  select n.id, n.body from child_internal_notes n
  where n.child_id = p_child_id and n.category = 'observation'
    and n.ai_excluded = false and n.deleted_at is null and n.note_date between p_from and p_to
  order by n.note_date;
end;
$$;
