-- 213: 園内連絡 Phase 3(UI)用の一覧RPC(設計書§10で予定されていた fetch_staff_messages。156の補完)。
-- 一覧に必要な導出(宛先ラベル・自分宛てか・確認済みか・開封済みか・確認状況カウント)を
-- サーバー側で1回で返す(宛先判定は is_staff_message_addressed_to に一元化=フロント複製禁止§12)。
-- 既定=直近30日。p_include_archive=true で全期間(削除は論理のみ・deleted_atは常に除外)。
-- 冪等: create or replace のみ。

create or replace function fetch_staff_messages(p_office_id uuid, p_include_archive boolean default false)
returns table (
  message_id uuid,
  body text,
  target_date date,
  created_at timestamptz,
  author_employee_id uuid,
  author_name text,
  target_labels text[],
  is_addressed_to_me boolean,
  acknowledged_by_me boolean,
  ack_count int,
  addressed_count int
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
    m.id,
    m.body,
    m.target_date,
    m.created_at,
    m.author_employee_id,
    e.name,
    (
      select array_agg(
        case t.target_type
          when 'facility' then '施設全体'
          when 'individual' then coalesce(te.name, '職員')
          when 'band' then coalesce(b.name, '時間帯')
          when 'class' then coalesce(cc.class_name, 'クラス')
        end order by t.created_at)
      from staff_message_targets t
      left join employees te on te.id = t.employee_id
      left join staff_time_bands b on b.id = t.band_id
      left join childcare_classes cc on cc.id = t.class_id
      where t.message_id = m.id
    ),
    is_staff_message_addressed_to(m.id, my_employee_id()),
    exists (select 1 from staff_message_reads r
            where r.message_id = m.id and r.employee_id = my_employee_id() and r.acknowledged_at is not null),
    (select count(*)::int from staff_message_reads r
      where r.message_id = m.id and r.acknowledged_at is not null),
    (select count(*)::int from employees emp
      where emp.id in (select office_accessible_employee_ids(m.office_id))
        and is_staff_message_addressed_to(m.id, emp.id))
  from staff_messages m
  join employees e on e.id = m.author_employee_id
  where m.office_id = p_office_id
    and m.deleted_at is null
    and (p_include_archive or m.created_at >= now() - interval '30 days')
  order by m.created_at desc;
end;
$$;

grant execute on function fetch_staff_messages(uuid, boolean) to anon, authenticated, service_role;
