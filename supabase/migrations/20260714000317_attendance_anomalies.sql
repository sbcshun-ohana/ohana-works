-- 317: 登降園 Phase B。要確認判定(§11.1)。新マスター不要で補正必須の7条件を検出:
--   1降園なし/2登園なし/3逆転/4出席だが打刻なし/5欠席だが打刻あり/6打刻重複/9在籍期間外。
-- すべて severity='action'(補正必須・確認済み不可)。補正は Phase A の行内修正で解消。
-- 未実装(Phase D/E のマスター・イベント依存): 7閉園超過(閉園時刻マスター)/8日跨ぎ/10曜日外(利用曜日)/
--   11契約未解決(契約・認定)/12範囲外(施設設定範囲)。
create or replace function fetch_attendance_anomalies_for_office(p_office_id uuid, p_start date, p_end date)
returns table (child_id uuid, child_name text, class_name text, business_date date,
               anomaly_type text, label text, severity text)
language plpgsql stable security definer set search_path = public as $$
declare v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  return query
  with ev as (
    select e.child_id, (e.occurred_at at time zone 'Asia/Tokyo')::date as bd,
      count(*) filter (where e.event_type in ('drop_off','proxy_drop_off')) as in_cnt,
      count(*) filter (where e.event_type in ('pick_up','proxy_pick_up'))   as out_cnt,
      min(e.occurred_at) filter (where e.event_type in ('drop_off','proxy_drop_off')) as in_ts,
      max(e.occurred_at) filter (where e.event_type in ('pick_up','proxy_pick_up'))   as depart_ts
    from child_attendance_events e
    join children c on c.id = e.child_id
    where c.office_id = p_office_id
      and (e.occurred_at at time zone 'Asia/Tokyo')::date between p_start and p_end
    group by e.child_id, (e.occurred_at at time zone 'Asia/Tokyo')::date
  ),
  ab as (
    select a.child_id, a.business_date as bd, a.is_absent
    from child_daily_attendance a
    join children c on c.id = a.child_id
    where c.office_id = p_office_id and a.business_date between p_start and p_end
  ),
  base as (
    select coalesce(ev.child_id, ab.child_id) as cid, coalesce(ev.bd, ab.bd) as bd,
      coalesce(ev.in_cnt, 0) as in_cnt, coalesce(ev.out_cnt, 0) as out_cnt,
      ev.in_ts, ev.depart_ts, ab.is_absent
    from ev
    full join ab on ev.child_id = ab.child_id and ev.bd = ab.bd
  )
  select b.cid, c.display_name, cc.class_name, b.bd, x.atype, x.alabel, 'action'::text
  from base b
  join children c on c.id = b.cid
  left join child_class_enrollments cce on cce.child_id = c.id and cce.effective_end_date is null
  left join childcare_classes cc on cc.id = cce.class_id
  cross join lateral (
    values
      -- 1 登園ありだが降園なし(過去日・欠席でない)。当日は在園中のため対象外。
      ('no_departure', '降園打刻なし',
        (b.in_cnt > 0 and b.out_cnt = 0 and b.bd < v_today and coalesce(b.is_absent, false) = false)),
      -- 2 降園ありだが登園なし。
      ('no_arrival', '登園打刻なし',
        (b.out_cnt > 0 and b.in_cnt = 0 and coalesce(b.is_absent, false) = false)),
      -- 3 登園時刻が降園時刻より後(逆転)。
      ('reversed', '登園>降園(逆転)',
        (b.in_ts is not null and b.depart_ts is not null and b.in_ts > b.depart_ts)),
      -- 4 出席扱い(欠席=false明示)だが有効な打刻がない(過去日)。
      ('present_no_punch', '出席だが打刻なし',
        (b.is_absent = false and b.in_cnt = 0 and b.out_cnt = 0 and b.bd < v_today)),
      -- 5 欠席扱いだが打刻がある。
      ('absent_with_punch', '欠席だが打刻あり',
        (b.is_absent = true and (b.in_cnt > 0 or b.out_cnt > 0))),
      -- 6 同じ種類の打刻が重複。
      ('duplicate', '打刻の重複',
        (b.in_cnt > 1 or b.out_cnt > 1)),
      -- 9 在籍・退園期間外の打刻。
      ('out_of_enrollment', '在籍期間外の打刻',
        ((b.in_cnt > 0 or b.out_cnt > 0)
          and (b.bd < c.enrollment_date or (c.withdrawal_date is not null and b.bd > c.withdrawal_date))))
  ) x(atype, alabel, hit)
  where x.hit
  order by cc.class_name nulls last, c.display_name, b.bd;
end $$;
grant execute on function fetch_attendance_anomalies_for_office(uuid, date, date) to authenticated, service_role;
