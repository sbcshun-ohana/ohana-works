-- 265: 午睡チェック記入漏れの境界バグ修正。俊指摘2026-08-20。
-- 起床時刻(wake_up_at)がちょうど5分刻みのとき、その「起床スロット」を要チェックに
-- 含めてしまい記入漏れを誤検出していた。起床時刻を排他的境界にして、就寝中(起床の
-- 直前スロットまで)のみを要チェックにする。169の全文差し替え(endpoint の1行のみ変更)。
create or replace function fetch_nap_missing_slots(p_office_id uuid, p_session_date date)
returns table (
  session_id uuid, child_id uuid, display_name text, class_id uuid, class_name text,
  missing_count int, missing_slots timestamptz[]
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not has_childcare_office_access(p_office_id) then
    raise exception 'not authorized';
  end if;

  return query
  with expected as (
    select s.id as session_id, gs as slot_at
    from nap_sessions s
    cross join lateral generate_series(
      date_bin('5 minutes', s.sleep_start_at, timestamptz 'epoch')
        + case when s.sleep_start_at > date_bin('5 minutes', s.sleep_start_at, timestamptz 'epoch')
               then interval '5 minutes' else interval '0' end,
      -- 起床時刻は排他的境界(起床の瞬間のスロットは要チェックにしない)。就寝中は now() まで。
      least(coalesce(s.wake_up_at - interval '1 microsecond', now()), now()),
      interval '5 minutes'
    ) gs
    where s.office_id = p_office_id and s.session_date = p_session_date and s.sleep_start_at is not null
  ),
  miss as (
    select e.session_id, array_agg(e.slot_at order by e.slot_at) as slots, count(*) as cnt
    from expected e
    left join nap_checks nc on nc.session_id = e.session_id and nc.slot_at = e.slot_at
    where nc.id is null
    group by e.session_id
  )
  select s.id, c.id, c.display_name, cc.id, cc.class_name, m.cnt::int, m.slots
  from miss m
  join nap_sessions s on s.id = m.session_id
  join children c on c.id = s.child_id
  join childcare_classes cc on cc.id = s.class_id
  order by cc.age_group, cc.class_name, c.display_name;
end;
$$;
