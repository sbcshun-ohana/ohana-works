-- 202: お迎え者の身分証明書管理(設計承認 2026-08-14 俊確定:
--      ①同一人物判定=園児単位 ②「確認済み✓」=園が実物確認した後 ③確認チェック操作=主任以上 ④画像は無期限保持)
--
-- 概要:
--  (1) pickup_persons(お迎え者マスタ・園児単位)を新設。unique(child_id, name) で同一人物判定。
--      id_verified=園が身分証の実物を確認済みか。直接のテーブルアクセスは行わず全て
--      security definer RPC経由(RLS有効化のみ=既定deny)。
--  (2) parent_requests.id_document_path を追加(申請時にアップロードした身分証の格納パス。
--      pickup_person_change 以外はNULL。保護者の直接insertはRLS既存ポリシーのまま列だけ増える)。
--  (3) storageバケット pickup-id-documents(非公開)。パス規約 {child_id}/{ファイル名}。
--      保護者=自分の関連児フォルダへのみinsert可、職員=読み取り可(class-photos/payslipsと同方針)。
--  (4) approve_parent_request(現行=201)にお迎え変更分岐を追加: 承認時に pickup_persons へ upsert。
--      id_verified は維持(リセットしない)。身分証パスは新しいアップロードがあれば更新。
--  (5) RPC新設/変更:
--      - fetch_pickup_persons_for_child: 保護者フォームの既登録者照合+園側一覧(保護者/職員両用)
--      - set_pickup_person_id_verified: 実物確認済みチェック(主任以上=manages_childcare)
--      - fetch_board_pickup_changes_for_office: ボード表示用(198方式・186は不変)
--      - fetch_pending_parent_requests: id_document_path+確認済み状態を追加
--        (戻り型変更のため drop→create→grant再付与。※適用前に pg_get_functiondef で202直前=201と照合)
--  (6) 機能フラグ pickup_id_document_enabled(既定OFF)+判定RPC(145共通ヘルパー)。
--
-- 冪等: 列追加=if not exists、バケット/フラグ=on conflict/not existsガード、関数=create or replace
--       (fetch_pending のみ drop→create)。テーブル/トリガー/ポリシーは初回適用前提の素create。

-- (1) お迎え者マスタ(園児単位)
create table pickup_persons (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  name text not null,
  relationship text,
  phone text,
  id_document_path text,
  id_verified boolean not null default false,
  verified_by uuid references employees(id),
  verified_at timestamptz,
  created_by_guardian_id uuid references guardians(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (child_id, name)
);

comment on table pickup_persons is
  'お迎え者マスタ(202・園児単位)。お迎えの方の変更申請の承認時に自動登録。id_verified=園が身分証の実物確認済み(主任以上が操作)';

create trigger trg_pickup_persons_updated_at before update on pickup_persons
  for each row execute function set_updated_at();
create index idx_pickup_persons_child on pickup_persons(child_id);

-- 直接アクセスは想定しない(全てsecurity definer RPC経由)。RLS有効化のみ=既定deny。
alter table pickup_persons enable row level security;

-- (2) 申請への身分証パス(保護者がアップロード後にinsert時セット)
alter table parent_requests add column if not exists id_document_path text;

comment on column parent_requests.id_document_path is
  'お迎え者身分証(202)のstorageパス(pickup-id-documentsバケット)。pickup_person_change以外はNULL';

-- (3) storageバケット+ポリシー(パス規約: {child_id}/{ファイル名})
insert into storage.buckets (id, name, public)
values ('pickup-id-documents', 'pickup-id-documents', false)
on conflict (id) do nothing;

create policy pickup_id_docs_insert on storage.objects
  for insert with check (
    bucket_id = 'pickup-id-documents'
    and guardian_has_child_access(((storage.foldername(name))[1])::uuid)
  );

create policy pickup_id_docs_select_staff on storage.objects
  for select using (
    bucket_id = 'pickup-id-documents' and my_employee_id() is not null
  );

-- (4) 承認: 201の全文をベースにお迎え変更分岐を追加(照合は適用前に実施)
create or replace function approve_parent_request(p_request_id uuid, p_decision_reason text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request parent_requests%rowtype;
  v_enroll_start date;
  v_enroll_end date;
  v_day date;
  v_end date;
  v_kind text;
  v_is_absent boolean;
  v_reason text;
  -- 201: 服薬承認時の午睡自動追加用
  v_nap_office uuid;
  v_nap_class uuid;
  v_nap_required boolean;
  -- 202: お迎え変更承認時のお迎え者マスタ登録用
  v_pickup_name text;
begin
  select * into v_request from parent_requests where id = p_request_id for update;
  if v_request.id is null then
    raise exception 'request not found';
  end if;
  if not staff_manages_guardian_data(v_request.child_id) then
    raise exception 'not authorized';
  end if;
  if v_request.status <> 'pending' then
    raise exception 'request is % and cannot be approved', v_request.status;
  end if;

  update parent_requests
  set status = 'approved', approved_by = my_employee_id(), approved_at = now(), decision_reason = p_decision_reason
  where id = p_request_id;

  -- 欠席の承認は、対象期間の各日を欠席としてデイリーボードへ自動反映。
  -- (感染症は106でabsenceのdetailsに統合済み=absenceで一括。遅刻/早退/お迎え変更/その他は対象外)。
  -- absence_kind=NULL(旧アプリ等)は反映をスキップ(既存の手動欠席を上書き破壊しない)。
  if v_request.request_type = 'absence' then
    v_kind := v_request.absence_kind;
    if v_kind is not null then
      v_is_absent := coalesce(v_kind in ('sick_absence', 'personal_absence'), false);  -- 185と同一の同期規則
      v_reason := case v_kind
        when 'sick_absence' then '保護者申請（病欠）'
        when 'personal_absence' then '保護者申請（都合欠）'
        else '保護者申請による欠席' end;

      -- 在籍期間(children マスタ)でクリップ: 在籍外の日には行を作らない。
      select enrollment_date, withdrawal_date into v_enroll_start, v_enroll_end
      from children where id = v_request.child_id;

      v_day := greatest(v_request.target_date, v_enroll_start);
      v_end := coalesce(v_request.end_date, v_request.target_date);
      if v_enroll_end is not null then
        v_end := least(v_end, v_enroll_end);
      end if;

      while v_day <= v_end loop
        insert into child_daily_attendance (child_id, business_date, is_absent, attendance_kind, absence_reason, changed_by, changed_at)
        values (v_request.child_id, v_day, v_is_absent, v_kind, v_reason, my_employee_id(), now())
        on conflict (child_id, business_date) do update set
          is_absent       = excluded.is_absent,
          attendance_kind = excluded.attendance_kind,
          absence_reason  = excluded.absence_reason,
          changed_by      = excluded.changed_by,
          changed_at      = excluded.changed_at;
        perform refresh_daily_child_status(v_request.child_id, v_day);
        v_day := v_day + 1;
      end loop;
    end if;
  end if;

  -- 201: 服薬連絡の承認。3歳以上(対象日の在籍クラスの nap_check_required=false)の園児を
  -- 対象日の午睡チェックへ自動追加(既存の任意追加機構=nap_sessions行。冪等)。
  -- kinds NULL/空(旧アプリ等)は反映スキップ(承認自体は成立)。在籍クラスが解決できない日も
  -- スキップ(承認をブロックしない)。ボードの服薬表示は読み取りRPC(fetch_board_medication_for_office)
  -- が parent_requests から直接引くため、承認時に立てるデータは無い。
  if v_request.request_type = 'medication'
     and v_request.medication_kinds is not null
     and array_length(v_request.medication_kinds, 1) > 0 then
    select c.office_id, cce.class_id, cc.nap_check_required
      into v_nap_office, v_nap_class, v_nap_required
    from children c
    join child_class_enrollments cce on cce.child_id = c.id
      and cce.effective_start_date <= v_request.target_date
      and (cce.effective_end_date is null or cce.effective_end_date >= v_request.target_date)
    join childcare_classes cc on cc.id = cce.class_id
    where c.id = v_request.child_id
    order by cce.effective_start_date desc
    limit 1;

    if v_nap_class is not null and v_nap_required = false then
      insert into nap_sessions (child_id, office_id, class_id, session_date, is_required, added_by)
      values (v_request.child_id, v_nap_office, v_nap_class, v_request.target_date, false, my_employee_id())
      on conflict (child_id, session_date) do nothing;
    end if;
  end if;

  -- 202: お迎えの方の変更の承認。お迎え者マスタ(園児単位)へ upsert。
  -- 同一人物判定は unique(child_id, name)。id_verified(実物確認済み)は維持しリセットしない。
  -- 続柄・電話・身分証パスは新しい値があるときだけ更新(NULLで既存値を消さない)。
  -- 氏名が空(旧アプリ等)は登録スキップ(承認自体は成立)。
  if v_request.request_type = 'pickup_person_change' then
    v_pickup_name := nullif(trim(coalesce(v_request.details->>'お迎えの方の氏名', '')), '');
    if v_pickup_name is not null then
      insert into pickup_persons (child_id, name, relationship, phone, id_document_path, created_by_guardian_id)
      values (
        v_request.child_id,
        v_pickup_name,
        nullif(trim(coalesce(v_request.details->>'続柄', '')), ''),
        nullif(trim(coalesce(v_request.details->>'電話番号', '')), ''),
        v_request.id_document_path,
        v_request.guardian_id
      )
      on conflict (child_id, name) do update set
        relationship     = coalesce(excluded.relationship, pickup_persons.relationship),
        phone            = coalesce(excluded.phone, pickup_persons.phone),
        id_document_path = coalesce(excluded.id_document_path, pickup_persons.id_document_path);
    end if;
  end if;
end;
$$;

-- (5-1) 保護者フォームの既登録者照合+園側一覧(保護者=自分の関連児のみ/職員=施設アクセス)
create or replace function fetch_pickup_persons_for_child(p_child_id uuid)
returns table (
  person_id uuid,
  name text,
  relationship text,
  phone text,
  has_document boolean,
  id_verified boolean,
  verified_at timestamptz
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
  select pp.id, pp.name, pp.relationship, pp.phone,
         pp.id_document_path is not null, pp.id_verified, pp.verified_at
  from pickup_persons pp
  where pp.child_id = p_child_id
  order by pp.name;
end;
$$;

grant execute on function fetch_pickup_persons_for_child(uuid) to anon, authenticated, service_role;

-- (5-2) 実物確認済みチェック(主任以上)。外すとき(p_verified=false)は確認者・日時もクリア。
create or replace function set_pickup_person_id_verified(p_person_id uuid, p_verified boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_office uuid;
begin
  select c.office_id into v_office
  from pickup_persons pp
  join children c on c.id = pp.child_id
  where pp.id = p_person_id;
  if v_office is null then
    raise exception 'pickup person not found';
  end if;
  if not manages_childcare(v_office) then
    raise exception 'not authorized';
  end if;

  update pickup_persons
  set id_verified = p_verified,
      verified_by = case when p_verified then my_employee_id() else null end,
      verified_at = case when p_verified then now() else null end
  where id = p_person_id;
end;
$$;

grant execute on function set_pickup_person_id_verified(uuid, boolean) to anon, authenticated, service_role;

-- (5-3) ボード表示用: 対象日の承認済みお迎え変更+確認済み状態(198方式・186は不変)
create or replace function fetch_board_pickup_changes_for_office(p_office_id uuid, p_business_date date)
returns table (
  child_id uuid,
  person_name text,
  relationship text,
  arrive_time text,
  leave_time text,
  id_verified boolean,
  has_document boolean
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
  select
    pr.child_id,
    nullif(trim(coalesce(pr.details->>'お迎えの方の氏名', '')), ''),
    nullif(trim(coalesce(pr.details->>'続柄', '')), ''),
    pr.details->>'登園時間',
    pr.details->>'お迎え時間',
    coalesce(pp.id_verified, false),
    (coalesce(pp.id_document_path, pr.id_document_path) is not null)
  from parent_requests pr
  join children c on c.id = pr.child_id
  left join pickup_persons pp on pp.child_id = pr.child_id
    and pp.name = nullif(trim(coalesce(pr.details->>'お迎えの方の氏名', '')), '')
  where c.office_id = p_office_id
    and pr.request_type = 'pickup_person_change'
    and pr.status = 'approved'
    and pr.target_date = p_business_date;
end;
$$;

grant execute on function fetch_board_pickup_changes_for_office(uuid, date) to anon, authenticated, service_role;

-- (5-4) 承認画面一覧に 身分証パス+確認済み状態 を追加。戻り型変更のため drop→create→grant再付与。
--       ※ pg_get_functiondef による201照合は、この drop より前に実施すること。
drop function if exists fetch_pending_parent_requests(uuid);

create function fetch_pending_parent_requests(p_office_id uuid)
returns table (
  request_id uuid,
  child_id uuid,
  child_display_name text,
  guardian_name text,
  request_type text,
  target_date date,
  end_date date,
  absence_kind text,
  medication_kinds text[],
  details jsonb,
  created_at timestamptz,
  id_document_path text,
  pickup_id_verified boolean
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
  select
    pr.id, c.id, c.display_name, g.name, pr.request_type,
    pr.target_date, pr.end_date, pr.absence_kind, pr.medication_kinds, pr.details, pr.created_at,
    pr.id_document_path,
    coalesce(pp.id_verified, false)
  from parent_requests pr
  join children c on c.id = pr.child_id
  join guardians g on g.id = pr.guardian_id
  left join pickup_persons pp on pr.request_type = 'pickup_person_change'
    and pp.child_id = pr.child_id
    and pp.name = nullif(trim(coalesce(pr.details->>'お迎えの方の氏名', '')), '')
  where c.office_id = p_office_id and pr.status = 'pending'
  order by pr.created_at;
end;
$$;

grant execute on function fetch_pending_parent_requests(uuid) to anon, authenticated, service_role;

-- (6) 機能フラグ(既定OFF・施設別ONはフラグ画面/SQLから)
insert into feature_flags (feature_key, name, description, default_enabled)
select 'pickup_id_document_enabled', 'お迎え者身分証明書',
       'お迎えの方の変更時の身分証アップロード(初回のみ)と実物確認済み管理', false
where not exists (select 1 from feature_flags where feature_key = 'pickup_id_document_enabled');

create or replace function is_pickup_id_document_enabled_for_office(p_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select is_feature_enabled_for_office('pickup_id_document_enabled', p_office_id);
$$;

grant execute on function is_pickup_id_document_enabled_for_office(uuid) to anon, authenticated, service_role;
