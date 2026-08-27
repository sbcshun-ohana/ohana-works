-- 368: 職員給食 自己注文モデル M3(俊指示 2026-08-27・設計ロック)。
--   (1) 請求集計 aggregate_staff_meal_deductions を改修: 358の「勤怠(実出勤打刻)がある日のみ請求」除外を撤去。
--       新モデルでは請求ベース=給食表の◯(participation ate=true)そのもの。食数=請求で完全一致させる。
--       併せて、当月の給食負担金を「◯が0になった職員」も含めて正確化(古い行の残存を防ぐため一旦削除→再投入)。
--   (2) 欠勤/有給申請の提出・承認・取下げ・却下・削除に連動して、対象職員×対象日の participation を自動再構築。
--       → 全日欠勤/有給の提出で自動キャンセル、取下げ/却下で自動復活(設計B)。過去日は rebuild 側ガードで凍結。
--   ※8:55締め切り後の当日変更の扱い(締切後は「変更」承認フロー)は後続 M4 で整合させる。

-- ============================================================
-- (1) 請求集計: 勤怠除外を撤去 + ◯0の職員も正確化
-- ============================================================
create or replace function aggregate_staff_meal_deductions(p_month date)
returns int language plpgsql security definer set search_path = public as $$
declare v_month date := date_trunc('month', p_month)::date; v_cnt int;
begin
  if not (is_labor_manager_plus() or is_childcare_admin_any()) then raise exception 'not authorized'; end if;

  -- 当月に給食◯(participation ate=true)が1件も無くなった職員の既存「給食管理」行を除去(請求=◯一致のため)。
  delete from burden_fee_records b
  where b.target_month = v_month and b.source = '給食管理'
    and not exists (
      select 1 from staff_meal_participation p
      where p.employee_id = b.employee_id and p.ate
        and p.business_date >= v_month
        and p.business_date < (v_month + interval '1 month')::date
    );

  -- ◯のある職員は 食数×施設単価 を再投入(勤怠除外なし=給食表の◯そのもの)。
  with agg as (
    select p.employee_id,
           count(*) as cnt,
           sum(coalesce(bm.unit_price, 0)) as amt
    from staff_meal_participation p
    left join burden_fee_masters bm on bm.office_id = p.office_id
    where p.ate
      and p.business_date >= v_month
      and p.business_date <  (v_month + interval '1 month')::date
    group by p.employee_id
  )
  insert into burden_fee_records (employee_id, target_month, meal_count, amount, source)
  select employee_id, v_month, cnt, amt, '給食管理'
  from agg
  on conflict (employee_id, target_month) do update
    set meal_count = excluded.meal_count, amount = excluded.amount, source = '給食管理';
  get diagnostics v_cnt = row_count;
  return v_cnt;
end $$;
grant execute on function aggregate_staff_meal_deductions(date) to authenticated, service_role;

-- ============================================================
-- (2) 欠勤/有給申請 → participation 自動再構築
-- ============================================================
-- 職員×日について、(a)現在participationがある施設 と (b)本来食べるべき施設 を再構築する。
-- (a)で除去(欠勤等)、(b)で復活(取下げ等)を両立。過去日は rebuild 側ガードで no-op。
create or replace function rebuild_staff_meal_for_employee_date(p_emp uuid, p_date date)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_weekday int; r record;
begin
  v_weekday := (extract(dow from p_date)::int + 6) % 7;
  -- (a) 現在この職員の participation がある施設を再構築(除去のため)
  for r in
    select distinct office_id from staff_meal_participation
    where employee_id = p_emp and business_date = p_date
  loop
    perform rebuild_staff_meal_participation(r.office_id, p_date);
  end loop;
  -- (b) 本来食べるべき施設(日別上書き > 曜日テンプレ > 主所属)を再構築(復活のため)
  select coalesce(
    (select office_id from staff_meal_entries where employee_id = p_emp and business_date = p_date),
    (select office_id from staff_meal_weekly_templates where employee_id = p_emp and weekday = v_weekday),
    (select home_office_id from employees where id = p_emp)
  ) into v_office;
  if v_office is not null then
    perform rebuild_staff_meal_participation(v_office, p_date);
  end if;
end $$;
-- 内部・トリガ専用(直接実行は不要)。PUBLIC/anon経由の実行権も塞ぐ。
revoke execute on function rebuild_staff_meal_for_employee_date(uuid, date) from public, anon, authenticated;
grant execute on function rebuild_staff_meal_for_employee_date(uuid, date) to service_role;
-- 367の rebuild も同様に PUBLIC/anon/authenticated から確実に revoke(create or replace は grant を保持するため追補)。
revoke execute on function rebuild_staff_meal_participation(uuid, date) from public, anon, authenticated;

-- requests(欠勤/有給)の追加・更新・削除で、対象日範囲を再構築するトリガ関数。
-- plpgsqlの「行型 IS NOT NULL」は全カラム非NULLの意味で使えないため、TG_OP と NEW/OLD を明示的に扱う。
-- NEW側・OLD側を独立に処理し、種別変更・職員変更・日付変更・削除の全ケースで除去/復活を両立させる。
create or replace function trg_requests_meal_rebuild()
returns trigger language plpgsql security definer set search_path = public as $$
declare d date; v_end date; v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  -- NEW側(INSERT/UPDATE): NEWが欠勤/有給なら NEW範囲を再構築(提出=キャンセル方向)。
  if TG_OP in ('INSERT', 'UPDATE') and NEW.request_type in ('absence', 'paid_leave') then
    d := greatest(NEW.target_date, v_today);                             -- 過去日はrebuildがno-op=飛ばす
    v_end := least(coalesce(NEW.target_end_date, NEW.target_date), v_today + 370);  -- 暴走キャップ
    while d <= v_end loop
      perform rebuild_staff_meal_for_employee_date(NEW.employee_id, d);
      d := d + 1;
    end loop;
  end if;

  -- OLD側(UPDATE/DELETE): OLDが欠勤/有給なら OLD範囲を再構築(取下げ/却下/種別変更/職員変更/削除=復活方向)。
  if TG_OP in ('UPDATE', 'DELETE') and OLD.request_type in ('absence', 'paid_leave') then
    d := greatest(OLD.target_date, v_today);
    v_end := least(coalesce(OLD.target_end_date, OLD.target_date), v_today + 370);
    while d <= v_end loop
      perform rebuild_staff_meal_for_employee_date(OLD.employee_id, d);
      d := d + 1;
    end loop;
  end if;

  return null;  -- AFTER トリガのため戻り値は無視される
end $$;

drop trigger if exists trg_requests_meal_rebuild on requests;
create trigger trg_requests_meal_rebuild
  after insert or update or delete on requests
  for each row execute function trg_requests_meal_rebuild();
