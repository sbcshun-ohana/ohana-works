-- 245: M6 Phase 7-1 = 食数の自動集計RPC(本案§4.2)。
-- 当日の在籍・非欠席児を給食状態5区分(fetch_child_meal_status)別に集計し、
-- 職員食数(確定シフトの出勤者)も返す。厨房ページ(Ohana Kids)と月次集計の基礎。
-- 認可: has_childcare_office_access(所属施設の職員以上・厨房ページ閲覧と同一)。
--
-- 給食提供数 provided = 通常食 + 共通除去食(弁当持参/給食開始保留/給食提供前は提供対象外)。
-- 欠席控除は child_daily_attendance.is_absent(承認済み欠席連絡も当日欠席登録に同期される既存仕様)。
-- 職員食数(§6-3 v1既定): 確定シフト(status='confirmed')で start_time 非NULL=出勤者を全員喫食として計上。
--   喫食対象(食べる/食べない)の個別設定・検食分は後続(構造だけ将来拡張)。
-- 給食状態は fetch_child_meal_status の「現時点」判定(当日の食数用途に十分。過去日の再現は確定スナップショット=7-2)。
create or replace function fetch_meal_count_for_office(p_office_id uuid, p_business_date date)
returns table (
  normal_count bigint,       -- 通常食
  elimination_count bigint,  -- 共通除去食
  bento_count bigint,        -- 弁当持参
  hold_count bigint,         -- 給食開始保留
  pre_count bigint,          -- 給食提供前
  provided_count bigint,     -- 給食提供数(通常食+共通除去食)
  staff_count bigint         -- 職員食数(確定シフト出勤者)
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not has_childcare_office_access(p_office_id) then
    raise exception 'not authorized';
  end if;

  return query
  with child_status as (
    select s.meal_status
    from children c
    cross join lateral fetch_child_meal_status(c.id) s
    where c.office_id = p_office_id
      and c.enrollment_status = '在籍中'
      and not exists (
        select 1 from child_daily_attendance a
        where a.child_id = c.id and a.business_date = p_business_date and a.is_absent
      )
  )
  select
    count(*) filter (where meal_status = '通常食'),
    count(*) filter (where meal_status = '共通除去食'),
    count(*) filter (where meal_status = '弁当持参'),
    count(*) filter (where meal_status = '給食開始保留'),
    count(*) filter (where meal_status = '給食提供前'),
    count(*) filter (where meal_status in ('通常食', '共通除去食')),
    (select count(distinct sh.employee_id)
     from shifts sh
     where sh.office_id = p_office_id
       and sh.work_date = p_business_date
       and sh.status = 'confirmed'
       and sh.start_time is not null)
  from child_status;
end;
$$;
grant execute on function fetch_meal_count_for_office(uuid, date) to authenticated, service_role;
