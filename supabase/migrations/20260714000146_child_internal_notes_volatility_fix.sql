-- 園内記録機能: E2E検証(設計書§10 #9)で発覚した不具合の修正。
--
-- fetch_child_internal_notes / fetch_child_internal_notes_for_ai を stable として
-- 定義していたが、両関数は log_sensitive_access() を呼び出しており、これは
-- sensitive_access_logs への INSERT(書き込み)を伴う。PostgRESTはstable/immutableな
-- 関数呼び出しを読み取り専用トランザクションとして実行するため、実際に
-- 「STG-EMP-02(主任)がfetch_child_internal_notes_for_aiを呼ぶ」実機E2Eで
-- 「cannot execute INSERT in a read-only transaction」エラーが発生した。
--
-- 既存の同種関数(fetch_payroll_transfer_recipients・
-- fetch_employees_tax_withholding_status)はいずれもvolatile(既定)で定義されており、
-- 今回もその流儀に合わせる。stable指定を外すのみで、ロジック自体は変更しない。

drop function if exists fetch_child_internal_notes(uuid, date, date, text[], int, int);

create or replace function fetch_child_internal_notes(
  p_child_id uuid, p_from date default null, p_to date default null,
  p_categories text[] default null, p_limit int default 50, p_offset int default 0
)
returns setof child_internal_notes
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
begin
  select cc.office_id into v_office_id
  from child_class_enrollments cce
  join childcare_classes cc on cc.id = cce.class_id
  where cce.child_id = p_child_id and cce.effective_end_date is null
  limit 1;
  if v_office_id is null then
    raise exception 'child not found or not currently enrolled';
  end if;
  if not is_child_internal_notes_enabled_for_office(v_office_id) then
    raise exception 'feature not enabled for this office';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  perform log_sensitive_access(
    '園内記録閲覧(fetch_child_internal_notes)', null, format('child_id=%s', p_child_id)
  );

  return query
  select n.*
  from child_internal_notes n
  where n.child_id = p_child_id
    and n.deleted_at is null
    and (p_from is null or n.note_date >= p_from)
    and (p_to is null or n.note_date <= p_to)
    and (p_categories is null or n.category = any (p_categories))
  order by n.note_date desc, n.created_at desc
  limit p_limit offset p_offset;
end;
$$;

drop function if exists fetch_child_internal_notes_for_ai(uuid, date, date);

create or replace function fetch_child_internal_notes_for_ai(p_child_id uuid, p_from date, p_to date)
returns table (id uuid, body text)
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
begin
  select cc.office_id into v_office_id
  from child_class_enrollments cce
  join childcare_classes cc on cc.id = cce.class_id
  where cce.child_id = p_child_id and cce.effective_end_date is null
  limit 1;
  if v_office_id is null then
    raise exception 'child not found or not currently enrolled';
  end if;
  if not is_child_internal_notes_enabled_for_office(v_office_id) then
    raise exception 'feature not enabled for this office';
  end if;
  if not is_child_internal_notes_chief(v_office_id) then
    raise exception 'not authorized';
  end if;
  if p_from is null or p_to is null then
    raise exception 'p_from and p_to are required';
  end if;

  perform log_sensitive_access(
    '園内記録AI参照(fetch_child_internal_notes_for_ai)', null,
    format('child_id=%s, from=%s, to=%s', p_child_id, p_from, p_to)
  );

  return query
  select n.id, n.body
  from child_internal_notes n
  where n.child_id = p_child_id
    and n.category in ('handover', 'observation')
    and n.ai_excluded = false
    and n.deleted_at is null
    and n.note_date between p_from and p_to
  order by n.note_date;
end;
$$;
