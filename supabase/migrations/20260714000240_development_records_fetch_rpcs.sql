-- 240: 発達記録 Phase 3(取得RPC・読み取り専用)。
-- 正本 §5(年齢区分)/§9(画面)。年度年齢判定はピュア関数に分離し境界E2E可能にする。
-- 権限: 発達記録の閲覧=has_childcare_office_access(office)、承認キュー=manages_childcare(office)。

-- ─────────────────────────────────────────────────────────────
-- 適用年齢区分(§5確定ルール): 現保育年度(4月始まり)の4/1時点の満年齢(年度年齢)が
-- 2以上なら AGE_n、2未満なら実月齢で M00_05/M06_14/M15_23。
-- これにより「実月齢24か月到達〜年度末はM15_23継続、翌4/1にAGE_2」も自然に表現される
-- (年度途中に2歳になっても年度年齢は1のまま=M15_23、翌4/1に年度年齢2=AGE_2)。
create or replace function development_age_band(p_birth_date date, p_ref_date date)
returns text language sql immutable as $$
  with a as (
    select make_date(
      case when extract(month from p_ref_date) >= 4
           then extract(year from p_ref_date)::int
           else extract(year from p_ref_date)::int - 1 end, 4, 1) as anchor
  ),
  calc as (
    select
      extract(year from age((select anchor from a), p_birth_date))::int as fiscal_age,
      (extract(year from age(p_ref_date, p_birth_date))::int * 12
       + extract(month from age(p_ref_date, p_birth_date))::int) as months
  )
  select case
    when p_birth_date is null then null
    when fiscal_age >= 5 then 'AGE_5'
    when fiscal_age = 4 then 'AGE_4'
    when fiscal_age = 3 then 'AGE_3'
    when fiscal_age = 2 then 'AGE_2'
    when months < 6 then 'M00_05'
    when months < 15 then 'M06_14'
    else 'M15_23'
  end
  from calc;
$$;
comment on function development_age_band(date, date) is
  '園児の適用発達区分(§5・240)。年度年齢>=2でAGE_n、<2で実月齢区分。';

-- 園児の現在の適用区分(JST今日基準)
create or replace function development_age_band_for_child(p_child_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select development_age_band(birth_date, (now() at time zone 'Asia/Tokyo')::date)
  from children where id = p_child_id;
$$;
grant execute on function development_age_band_for_child(uuid) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────
-- 発達記録画面のヘッダ情報(園児名・クラス・生年月日・適用区分)
create or replace function fetch_child_development_header(p_child_id uuid)
returns table (
  child_name text, class_name text, birth_date date, applicable_band text
)
language plpgsql stable security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;

  return query
  select c.display_name, cc.class_name, c.birth_date,
         development_age_band(c.birth_date, (now() at time zone 'Asia/Tokyo')::date)
  from children c
  left join child_class_enrollments cce on cce.child_id = c.id and cce.effective_end_date is null
  left join childcare_classes cc on cc.id = cce.class_id
  where c.id = p_child_id;
end $$;
grant execute on function fetch_child_development_header(uuid) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────
-- 発達記録一覧(園児×区分。既定は適用区分。過去区分はp_age_band_codeで指定して閲覧)
create or replace function fetch_child_development_records(
  p_child_id uuid, p_age_band_code text default null
)
returns table (
  item_id uuid, age_band_code text, domain_code text, item_name text,
  observation_point text, display_order int,
  is_achieved boolean, achievement_id uuid, first_achieved_on date,
  method text, approved_by_name text, target_year_month text,
  has_pending boolean, request_id uuid, requested_by_name text,
  requested_at timestamptz, request_note text
)
language plpgsql stable security definer set search_path = public as $$
declare v_office uuid; v_band text;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  v_band := coalesce(p_age_band_code, development_age_band_for_child(p_child_id));

  return query
  select m.id, m.age_band_code, m.domain_code, m.item_name, m.observation_point, m.display_order,
         (a.id is not null), a.id, a.first_achieved_on, a.method, ea.name, a.target_year_month,
         (r.id is not null), r.id, er.name, r.requested_at, r.note
  from development_item_masters m
  left join child_development_achievements a
    on a.item_id = m.id and a.child_id = p_child_id and a.is_active
  left join employees ea on ea.id = a.approved_by
  left join development_achievement_requests r
    on r.item_id = m.id and r.child_id = p_child_id and r.status = 'pending_review'
  left join employees er on er.id = r.requested_by
  where m.age_band_code = v_band and m.is_active
  order by m.domain_code, m.display_order;
end $$;
grant execute on function fetch_child_development_records(uuid, text) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────
-- 達成申請の承認キュー(主任以上・自施設の承認待ち)
create or replace function fetch_development_approval_queue(p_office_id uuid)
returns table (
  request_id uuid, child_id uuid, child_name text, class_name text,
  item_id uuid, item_name text, domain_code text, age_band_code text,
  source text, note text, requested_by_name text, requested_at timestamptz
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;

  return query
  select r.id, r.child_id, c.display_name, cc.class_name,
         r.item_id, m.item_name, m.domain_code, m.age_band_code,
         r.source, r.note, e.name, r.requested_at
  from development_achievement_requests r
  join children c on c.id = r.child_id
  left join child_class_enrollments cce on cce.child_id = c.id and cce.effective_end_date is null
  left join childcare_classes cc on cc.id = cce.class_id
  join development_item_masters m on m.id = r.item_id
  left join employees e on e.id = r.requested_by
  where r.office_id = p_office_id and r.status = 'pending_review'
  order by r.requested_at;
end $$;
grant execute on function fetch_development_approval_queue(uuid) to authenticated, service_role;
