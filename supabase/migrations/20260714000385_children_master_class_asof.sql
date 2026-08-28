-- 385: 園児マスタ一覧のクラス列を「基準日(JST今日)」基準へ(開発計画§6の軽微TODO)。
--   217版は effective_end_date is null(現在オープンな在籍行)で解決していたため、
--   進級を先付け登録した児が未来のクラスで表示される/端境期に無クラス表示になる。
--   本日時点で有効な在籍行(start<=today<=end)を採用し、重複時は開始日の新しい方を優先
--   (同一開始日の異常重複は created_at 降順で決定的に)。
--   シグネチャ不変(create or replace)。呼び出し元は無改修:
--   admin 園児マスタ(children)/incidents/therapy-records/meal-conferences・Kids 園児台帳。
--   仕様注記: 入園日を先付けした「在籍中」児は入園日までクラス空欄になる(未来クラスを
--   出さない本修正の趣旨と一貫。先付け登録は enrollment_status='入園予定' の運用が本筋)。
create or replace function fetch_children_for_office_master(p_office_id uuid)
returns table (
  child_id uuid,
  display_name text,
  honorific_suffix text,
  full_name text,
  name_kana text,
  gender text,
  birth_date date,
  enrollment_status text,
  withdrawal_date date,
  class_id uuid,
  class_name text,
  class_family_daily_report_required boolean,
  family_daily_report_required_from date,
  family_daily_report_required_until date,
  child_kind text,
  enrollment_date date
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  if not has_childcare_office_access(p_office_id) then
    raise exception 'not authorized';
  end if;

  return query
  select
    c.id, c.display_name, c.honorific_suffix_resolved, c.full_name, c.name_kana,
    c.gender, c.birth_date, c.enrollment_status, c.withdrawal_date,
    cc.id, cc.class_name, cc.family_daily_report_required,
    c.family_daily_report_required_from, c.family_daily_report_required_until,
    c.child_kind, c.enrollment_date
  from children c
  left join lateral (
    select e.class_id
    from child_class_enrollments e
    where e.child_id = c.id
      and e.effective_start_date <= v_today
      and (e.effective_end_date is null or e.effective_end_date >= v_today)
    order by e.effective_start_date desc, e.created_at desc
    limit 1
  ) cce on true
  left join childcare_classes cc on cc.id = cce.class_id
  where c.office_id = p_office_id
  order by cc.class_name, c.display_name;
end;
$$;
grant execute on function fetch_children_for_office_master(uuid) to authenticated, service_role;
