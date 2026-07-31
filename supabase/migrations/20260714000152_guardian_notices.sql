-- お知らせ(保護者向け一斉配信)Phase B: DB。
-- 設計: docs/お知らせ_保護者向け一斉配信_調査設計_2026-07-30.md(判断#1〜#6・確認ダイアログ反映)。
--
-- 方針:
--  - 宛先「意図」(targets)と配信時「スナップショット」(recipients)を分離。recipients.child_id で
--    園児文脈を保持(null=園全体バッジ、非null=園児名バッジ)。
--  - 作成=主任以上(manages_childcare)。全施設作成=system_admin または統括園長(判断#5)。
--    承認=園長以上(director自施設/executive_director全施設/system_admin)。承認=送信。
--  - 保護者は自分がrecipientのapproved通知のみ閲覧・自分の既読のみINSERT(RLS)。
--  - staff_pins同様、pin等の機微は無いが、書き込みは全てRPC経由(RLSはSELECTのみ)。
--  - 監査は guardian_notices(id列あり)に log_event_change(recipients等は件数多で対象外)。
--  - プッシュ(outbox生成・園児名タイトル)は Phase E。本Bは承認=recipients確定まで。

-- ============================================================
-- テーブル
-- ============================================================
create table guardian_notices (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(trim(title)) > 0),
  body text not null check (length(trim(body)) > 0),
  status text not null default 'draft' check (status in ('draft', 'in_review', 'returned', 'approved')),
  created_by uuid not null references employees(id),
  approver_id uuid references employees(id),
  approved_at timestamptz,
  returned_reason text,
  -- 誤送信の取り消し(承認=送信後にアプリ内一覧から消す。既送信プッシュは取り消せない)。
  revoked_at timestamptz,
  revoked_by uuid references employees(id),
  revoke_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  sent_at timestamptz
);
create trigger trg_guardian_notices_updated_at before update on guardian_notices
  for each row execute function set_updated_at();
create trigger trg_audit_guardian_notices after insert or update or delete on guardian_notices
  for each row execute function log_event_change();

create table guardian_notice_targets (
  id uuid primary key default gen_random_uuid(),
  notice_id uuid not null references guardian_notices(id) on delete cascade,
  target_type text not null check (target_type in ('all', 'office', 'class', 'child')),
  office_id uuid references offices(id),
  class_id uuid references childcare_classes(id),
  child_id uuid references children(id),
  created_at timestamptz not null default now()
);
create index idx_gnt_notice on guardian_notice_targets (notice_id);

create table guardian_notice_recipients (
  id uuid primary key default gen_random_uuid(),
  notice_id uuid not null references guardian_notices(id) on delete cascade,
  guardian_id uuid not null references guardians(id),
  child_id uuid references children(id),
  created_at timestamptz not null default now()
);
-- 同一お知らせ×保護者×園児文脈の重複防止(child_id が null 同士も同一扱い=NULLS NOT DISTINCT)。
create unique index uq_gnr_unique on guardian_notice_recipients (notice_id, guardian_id, child_id) nulls not distinct;
create index idx_gnr_notice on guardian_notice_recipients (notice_id);
create index idx_gnr_guardian on guardian_notice_recipients (guardian_id);
create index idx_gnr_notice_child on guardian_notice_recipients (notice_id, child_id);

create table guardian_notice_reads (
  id uuid primary key default gen_random_uuid(),
  notice_id uuid not null references guardian_notices(id) on delete cascade,
  guardian_id uuid not null references guardians(id),
  read_at timestamptz not null default now(),
  unique (notice_id, guardian_id)
);
create index idx_gnrd_notice on guardian_notice_reads (notice_id);

-- ============================================================
-- RLS: 書き込みは全てRPC経由(直接INSERT/UPDATE/DELETEポリシー無し)。
--   guardian_notices: 保護者は「自分がrecipientのapproved通知」のみSELECT。職員はRPC取得。
--   recipients: 職員はRPC。保護者は自分の行のみSELECT(自分宛の園児文脈確認用)。
--   reads: 保護者は自分の行のみSELECT/INSERT。職員は集計RPC。
-- ============================================================
alter table guardian_notices enable row level security;
create policy guardian_notices_select_guardian on guardian_notices
  for select using (
    status = 'approved'
    and revoked_at is null   -- 取り消し済みは保護者側から見せない
    and exists (select 1 from guardian_notice_recipients r
                where r.notice_id = guardian_notices.id and r.guardian_id = my_guardian_id())
  );

alter table guardian_notice_targets enable row level security;   -- deny-all(RPC経由のみ)

alter table guardian_notice_recipients enable row level security;
create policy guardian_notice_recipients_select_self on guardian_notice_recipients
  for select using (guardian_id = my_guardian_id());

alter table guardian_notice_reads enable row level security;
create policy guardian_notice_reads_select_self on guardian_notice_reads
  for select using (guardian_id = my_guardian_id());
-- INSERT は mark_guardian_notice_read RPC(SECURITY DEFINER)経由のみ。直接INSERTポリシーは設けない。

-- ============================================================
-- 権限ヘルパー
-- ============================================================
create or replace function is_executive_or_system_admin()
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from employee_roles er join roles r on r.id = er.role_id
    where er.employee_id = my_employee_id() and r.code in ('executive_director', 'system_admin')
  );
$$;

-- 園長以上(director自施設 / executive_director・system_admin 全施設)か
create or replace function is_director_plus_over_office(target_office_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from employee_roles er join roles r on r.id = er.role_id
    where er.employee_id = my_employee_id()
      and (
        r.code in ('system_admin', 'executive_director')
        or (r.code = 'director' and (er.office_id is null or er.office_id = target_office_id))
      )
  );
$$;

-- target 1件の施設IDを解決(all は null を返す)
create or replace function guardian_notice_target_office(p_target_type text, p_office_id uuid, p_class_id uuid, p_child_id uuid)
returns uuid language sql stable security definer set search_path = public
as $$
  select case p_target_type
    when 'office' then p_office_id
    when 'class' then (select office_id from childcare_classes where id = p_class_id)
    when 'child' then (select cc.office_id from child_class_enrollments e
                       join childcare_classes cc on cc.id = e.class_id
                       where e.child_id = p_child_id and e.effective_end_date is null limit 1)
    else null end;
$$;

-- 作成/編集権限: 全targetを作成できるか(all=exec/system、他=manages_childcare(office))
create or replace function is_guardian_notice_editor(p_notice_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select not exists (
    select 1 from guardian_notice_targets t
    where t.notice_id = p_notice_id
      and not (
        case t.target_type
          when 'all' then is_executive_or_system_admin()
          else manages_childcare(guardian_notice_target_office(t.target_type, t.office_id, t.class_id, t.child_id))
        end
      )
  );
$$;

-- 承認権限: 全targetに園長以上か(all=exec/system、他=is_director_plus_over_office)
create or replace function is_guardian_notice_approver(p_notice_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select not exists (
    select 1 from guardian_notice_targets t
    where t.notice_id = p_notice_id
      and not (
        case t.target_type
          when 'all' then is_executive_or_system_admin()
          else is_director_plus_over_office(guardian_notice_target_office(t.target_type, t.office_id, t.class_id, t.child_id))
        end
      )
  );
$$;

-- 宛先の解決(配信時スナップショット・プレビュー共通)。guardian_id × child_id(null=園全体)。
create or replace function resolve_guardian_notice_recipients(p_notice_id uuid)
returns table (guardian_id uuid, child_id uuid)
language sql stable security definer set search_path = public
as $$
  -- all: 全施設の在籍児の保護者(園全体=child_id null)
  select distinct gcl.guardian_id, null::uuid
  from guardian_notice_targets t
  join children c on c.enrollment_status in ('在籍中', '退園予定')
  join guardian_child_links gcl on gcl.child_id = c.id
  where t.notice_id = p_notice_id and t.target_type = 'all'
  union
  -- office: 当該施設の在籍児の保護者(園全体=child_id null)
  select distinct gcl.guardian_id, null::uuid
  from guardian_notice_targets t
  join children c on c.office_id = t.office_id and c.enrollment_status in ('在籍中', '退園予定')
  join guardian_child_links gcl on gcl.child_id = c.id
  where t.notice_id = p_notice_id and t.target_type = 'office'
  union
  -- class: 当該クラス在籍児 × 保護者(child_id=園児)
  select distinct gcl.guardian_id, e.child_id
  from guardian_notice_targets t
  join child_class_enrollments e on e.class_id = t.class_id and e.effective_end_date is null
  join guardian_child_links gcl on gcl.child_id = e.child_id
  where t.notice_id = p_notice_id and t.target_type = 'class'
  union
  -- child: 当該園児 × 保護者(child_id=園児)
  select distinct gcl.guardian_id, t.child_id
  from guardian_notice_targets t
  join guardian_child_links gcl on gcl.child_id = t.child_id
  where t.notice_id = p_notice_id and t.target_type = 'child';
$$;

-- ============================================================
-- 作成・申請・承認(=送信)・差戻し
-- ============================================================
create or replace function create_guardian_notice(p_title text, p_body text, p_targets jsonb)
returns uuid language plpgsql security definer set search_path = public
as $$
declare v_id uuid; v_t jsonb;
begin
  if my_employee_id() is null then raise exception 'not authenticated'; end if;
  if coalesce(trim(p_title), '') = '' or coalesce(trim(p_body), '') = '' then
    raise exception 'title and body are required';
  end if;
  if p_targets is null or jsonb_array_length(p_targets) = 0 then
    raise exception 'at least one target is required';
  end if;

  insert into guardian_notices (title, body, status, created_by)
  values (p_title, p_body, 'draft', my_employee_id()) returning id into v_id;

  for v_t in select * from jsonb_array_elements(p_targets) loop
    insert into guardian_notice_targets (notice_id, target_type, office_id, class_id, child_id)
    values (v_id, v_t->>'type',
            nullif(v_t->>'office_id', '')::uuid,
            nullif(v_t->>'class_id', '')::uuid,
            nullif(v_t->>'child_id', '')::uuid);
  end loop;

  -- 全宛先を作成できる権限があること(1つでも権限外なら例外=ロールバック)
  if not is_guardian_notice_editor(v_id) then
    raise exception 'not authorized to target one or more of the selected audiences';
  end if;
  return v_id;
end;
$$;

create or replace function submit_guardian_notice(p_notice_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare v_status text; v_creator uuid;
begin
  select status, created_by into v_status, v_creator from guardian_notices where id = p_notice_id;
  if v_status is null then raise exception 'not found'; end if;
  if v_status not in ('draft', 'returned') then raise exception 'invalid state'; end if;
  if v_creator <> my_employee_id() and not is_guardian_notice_editor(p_notice_id) then
    raise exception 'not authorized';
  end if;
  update guardian_notices set status = 'in_review', returned_reason = null where id = p_notice_id;
end;
$$;

create or replace function approve_guardian_notice(p_notice_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare v_status text;
begin
  select status into v_status from guardian_notices where id = p_notice_id;
  if v_status is null then raise exception 'not found'; end if;
  if v_status not in ('draft', 'in_review') then raise exception 'invalid state'; end if;
  if not is_guardian_notice_approver(p_notice_id) then
    raise exception 'not authorized to approve';
  end if;

  -- 配信時スナップショットを確定(Phase Eでこのrecipientsからoutbox生成・園児名タイトル付与)
  insert into guardian_notice_recipients (notice_id, guardian_id, child_id)
  select p_notice_id, r.guardian_id, r.child_id
  from resolve_guardian_notice_recipients(p_notice_id) r
  on conflict on constraint uq_gnr_unique do nothing;

  update guardian_notices
  set status = 'approved', approver_id = my_employee_id(), approved_at = now(), sent_at = now()
  where id = p_notice_id;
end;
$$;

create or replace function return_guardian_notice(p_notice_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public
as $$
declare v_status text;
begin
  select status into v_status from guardian_notices where id = p_notice_id;
  if v_status <> 'in_review' then raise exception 'invalid state'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'reason is required'; end if;
  if not is_guardian_notice_approver(p_notice_id) then raise exception 'not authorized'; end if;
  update guardian_notices set status = 'returned', returned_reason = p_reason where id = p_notice_id;
end;
$$;

-- 誤送信の取り消し(承認=送信済みのお知らせをアプリ内一覧から消す)。実行権限は承認者と同じ
-- (director自施設/executive_director全施設/system_admin)。理由必須・監査記録。
-- 既に配信済みのプッシュ通知は取り消せない(実行時の確認ダイアログで明示する=§6.5b・Phase C)。
create or replace function revoke_guardian_notice(p_notice_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public
as $$
declare v_status text; v_revoked timestamptz;
begin
  select status, revoked_at into v_status, v_revoked from guardian_notices where id = p_notice_id;
  if v_status is null then raise exception 'not found'; end if;
  if v_status <> 'approved' then raise exception 'only sent (approved) notices can be revoked'; end if;
  if v_revoked is not null then raise exception 'already revoked'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'reason is required'; end if;
  if not is_guardian_notice_approver(p_notice_id) then raise exception 'not authorized to revoke'; end if;
  update guardian_notices
  set revoked_at = now(), revoked_by = my_employee_id(), revoke_reason = p_reason
  where id = p_notice_id;
end;
$$;

-- 送信前確認ダイアログ用: 施設名・保護者数・園児数を送信せずに算出(§6.5b)
create or replace function preview_guardian_notice(p_notice_id uuid)
returns table (office_names text[], guardian_count int, child_count int)
language plpgsql stable security definer set search_path = public
as $$
declare v_has_all boolean;
begin
  if not is_guardian_notice_editor(p_notice_id) then raise exception 'not authorized'; end if;
  select exists (select 1 from guardian_notice_targets where notice_id = p_notice_id and target_type = 'all')
  into v_has_all;
  return query
  select
    case when v_has_all then (select array_agg(name order by name) from offices)
      else (
        select array_agg(distinct o.name order by o.name)
        from guardian_notice_targets t
        join offices o on o.id = guardian_notice_target_office(t.target_type, t.office_id, t.class_id, t.child_id)
        where t.notice_id = p_notice_id
      ) end,
    (select count(distinct guardian_id)::int from resolve_guardian_notice_recipients(p_notice_id)),
    (select count(distinct child_id)::int from resolve_guardian_notice_recipients(p_notice_id) where child_id is not null);
end;
$$;

-- 保護者が既読にする(自分がrecipientのお知らせのみ)。保護者単位で1回。
create or replace function mark_guardian_notice_read(p_notice_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if my_guardian_id() is null then raise exception 'not a guardian'; end if;
  if not exists (select 1 from guardian_notice_recipients
                 where notice_id = p_notice_id and guardian_id = my_guardian_id()) then
    raise exception 'not a recipient';
  end if;
  insert into guardian_notice_reads (notice_id, guardian_id)
  values (p_notice_id, my_guardian_id())
  on conflict (notice_id, guardian_id) do nothing;
end;
$$;

-- 職員側の既読集計(判断#3: 未読は世帯=園児単位。any=1人でも読めば既読)。
create or replace function fetch_guardian_notice_read_summary(p_notice_id uuid)
returns table (
  total_guardians int, read_guardians int,
  total_children int, unread_children int
)
language sql stable security definer set search_path = public
as $$
  select
    (select count(distinct guardian_id)::int from guardian_notice_recipients where notice_id = p_notice_id
       and is_guardian_notice_editor(p_notice_id)),
    (select count(distinct guardian_id)::int from guardian_notice_reads where notice_id = p_notice_id
       and is_guardian_notice_editor(p_notice_id)),
    (select count(distinct child_id)::int from guardian_notice_recipients where notice_id = p_notice_id and child_id is not null
       and is_guardian_notice_editor(p_notice_id)),
    -- 未読園児: その園児のいずれの保護者も既読が無い(any=1人でも読めば既読)
    (select count(*)::int from (
       select r.child_id
       from guardian_notice_recipients r
       where r.notice_id = p_notice_id and r.child_id is not null
       group by r.child_id
       having not exists (
         select 1 from guardian_child_links gcl
         join guardian_notice_reads rd on rd.guardian_id = gcl.guardian_id and rd.notice_id = p_notice_id
         where gcl.child_id = r.child_id
       )
     ) unread where is_guardian_notice_editor(p_notice_id));
$$;
