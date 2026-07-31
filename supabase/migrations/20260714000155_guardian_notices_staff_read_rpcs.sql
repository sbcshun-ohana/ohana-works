-- お知らせ(保護者向け一斉配信)Phase C: 職員(admin_web)閲覧系RPC。
-- 設計: docs/お知らせ_保護者向け一斉配信_調査設計_2026-07-30.md(§4.2 / §6.5b / §6.7)。
--
-- 背景: guardian_notices には職員向けの SELECT ポリシーが無い(保護者は自分がrecipientの
--   approved のみ・152)。職員側の一覧/詳細/未読世帯一覧は SECURITY DEFINER RPC で提供する
--   (書き込みは152のRPC群を使用。ここは読み取りのみ)。
--   認可はRPC内で担保: 一覧/宛先は当該施設アクセス or 作成/承認権限、未読集計は editor 権限。
--
-- 追加RPC:
--   fetch_guardian_notices_for_staff(office)         -- 一覧(状態・既読数・宛先ラベル・権限フラグ)
--   fetch_guardian_notice_targets(notice_id)         -- 詳細/編集用の宛先(名称解決)
--   fetch_guardian_notice_unread_recipients(notice_id) -- 未読世帯一覧(§6.7)

-- ============================================================
-- 1. 職員向けお知らせ一覧
--    当該施設(p_office_id)に関係するお知らせ(target が all もしくは当該施設に解決)を返す。
--    自施設アクセス(has_childcare_office_access)を認可の前提とする。
--    can_edit/can_approve は152のヘルパーそのものを返し、クライアントのボタン出し分けと
--    RPCの実際の認可を一致させる(クライアント判定を再実装しない)。
-- ============================================================
create or replace function fetch_guardian_notices_for_staff(p_office_id uuid)
returns table (
  id uuid,
  title text,
  body text,
  status text,
  returned_reason text,
  revoked_at timestamptz,
  revoke_reason text,
  created_at timestamptz,
  sent_at timestamptz,
  approved_at timestamptz,
  created_by_name text,
  approver_name text,
  target_labels text[],
  total_guardians int,
  read_guardians int,
  can_edit boolean,
  can_approve boolean
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not has_childcare_office_access(p_office_id) then
    raise exception 'not authorized';
  end if;

  return query
  select
    n.id, n.title, n.body, n.status, n.returned_reason, n.revoked_at, n.revoke_reason,
    n.created_at, n.sent_at, n.approved_at,
    ce.name,
    ae.name,
    (
      select array_agg(lbl order by lbl)
      from (
        select distinct case t.target_type
          when 'all' then '全施設'
          when 'office' then (select o.name from offices o where o.id = t.office_id)
          when 'class' then (select cc.class_name from childcare_classes cc where cc.id = t.class_id)
          when 'child' then (select c.display_name from children c where c.id = t.child_id)
        end as lbl
        from guardian_notice_targets t
        where t.notice_id = n.id
      ) s
    ),
    (select count(distinct r.guardian_id)::int from guardian_notice_recipients r where r.notice_id = n.id),
    (select count(distinct rd.guardian_id)::int from guardian_notice_reads rd where rd.notice_id = n.id),
    is_guardian_notice_editor(n.id),
    is_guardian_notice_approver(n.id)
  from guardian_notices n
  join employees ce on ce.id = n.created_by
  left join employees ae on ae.id = n.approver_id
  where exists (
    select 1 from guardian_notice_targets t
    where t.notice_id = n.id
      and (
        t.target_type = 'all'
        or guardian_notice_target_office(t.target_type, t.office_id, t.class_id, t.child_id) = p_office_id
      )
  )
  order by n.created_at desc;
end;
$$;

-- ============================================================
-- 2. お知らせの宛先(詳細表示・下書き/差戻しの編集で使用)
--    認可: 作成者本人 or 当該お知らせの編集権限(editor) or 承認権限(approver)。
-- ============================================================
create or replace function fetch_guardian_notice_targets(p_notice_id uuid)
returns table (
  target_type text,
  office_id uuid,
  class_id uuid,
  child_id uuid,
  label text
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not exists (select 1 from guardian_notices n where n.id = p_notice_id and n.created_by = my_employee_id())
     and not is_guardian_notice_editor(p_notice_id)
     and not is_guardian_notice_approver(p_notice_id) then
    raise exception 'not authorized';
  end if;

  return query
  select
    t.target_type, t.office_id, t.class_id, t.child_id,
    case t.target_type
      when 'all' then '全施設'
      when 'office' then (select o.name from offices o where o.id = t.office_id)
      when 'class' then (select cc.class_name from childcare_classes cc where cc.id = t.class_id)
      when 'child' then (select c.display_name from children c where c.id = t.child_id)
    end
  from guardian_notice_targets t
  where t.notice_id = p_notice_id
  order by t.target_type, t.created_at;
end;
$$;

-- ============================================================
-- 3. 未読世帯一覧(§6.7・判断#3)
--    child文脈あり(class/child): 園児(世帯)単位。any=その園児のいずれの保護者も未読なら未読。
--    child文脈なし(all/office): 保護者アカウント単位。当該保護者が未読なら未読。
--    認可: editor(=当該お知らせを作成できる=管理権限)。
-- ============================================================
create or replace function fetch_guardian_notice_unread_recipients(p_notice_id uuid)
returns table (
  kind text,          -- 'child' | 'guardian'
  child_id uuid,
  child_name text,
  class_name text,
  guardian_id uuid,
  guardian_name text
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not is_guardian_notice_editor(p_notice_id) then
    raise exception 'not authorized';
  end if;

  return query
  -- 園児(世帯)単位: その園児に紐づくどの保護者も既読が無い
  select
    'child'::text, c.id, c.display_name,
    (select cc.class_name
       from child_class_enrollments e
       join childcare_classes cc on cc.id = e.class_id
       where e.child_id = c.id and e.effective_end_date is null
       limit 1),
    null::uuid, null::text
  from (
    select distinct r.child_id
    from guardian_notice_recipients r
    where r.notice_id = p_notice_id and r.child_id is not null
      and not exists (
        select 1 from guardian_child_links gcl
        join guardian_notice_reads rd on rd.guardian_id = gcl.guardian_id and rd.notice_id = p_notice_id
        where gcl.child_id = r.child_id
      )
  ) uc
  join children c on c.id = uc.child_id
  union all
  -- 保護者単位(園全体お知らせ): 当該保護者が未読
  select
    'guardian'::text, null::uuid, null::text, null::text,
    g.id, g.name
  from (
    select distinct r.guardian_id
    from guardian_notice_recipients r
    where r.notice_id = p_notice_id and r.child_id is null
      and not exists (
        select 1 from guardian_notice_reads rd
        where rd.notice_id = p_notice_id and rd.guardian_id = r.guardian_id
      )
  ) ug
  join guardians g on g.id = ug.guardian_id
  order by 1, 3, 6;
end;
$$;
