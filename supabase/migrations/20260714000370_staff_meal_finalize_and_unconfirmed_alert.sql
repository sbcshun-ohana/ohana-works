-- 370: 職員給食 自己注文モデル M4b(俊指示 2026-08-27・設計ロック)。
--   9:31時点で当日の給食数を自動確定(承認の有無に関わらず厨房ボードへ反映済)。
--   ・meal_count_days.finalized_at を追加(9:31確定時刻)。
--   ・9:31 cron を「算出→確定(finalized_at)」に変更(cron_finalize_meal_counts)。
--     8:50 materialize は従来どおり cron_compute_meal_counts(算出のみ)。
--   ・一括承認の押し忘れ(確定済みだが未承認の日)を後から確認できる fetch_unconfirmed_finalized_days。
--   前提: rebuildは当日8:55以降 凍結(369)。9:31時点で 職員数=8:55時点のparticipation+手動manualで固定、
--         園児数は8:55-9:31の欠席連絡を反映して再集計(=園児は9:31スナップショット)。

-- ============================================================
-- (1) 確定時刻カラム
-- ============================================================
alter table meal_count_days add column finalized_at timestamptz;  -- 9:31自動確定の時刻(nullなら未確定)

-- ============================================================
-- (2) 9:31 確定cron: 最終算出 + finalized_at 刻印
-- ============================================================
-- 338(cron_compute_meal_counts)と同じスキップ条件でループし、算出した施設だけ finalized_at を刻印。
-- ※単純に cron_compute_meal_counts() を呼び + business_date一括UPDATEにすると、事前注文由来で
--   computed_at が付いた休園日/非稼働曜日にも刻印され、アラートの偽陽性になるため per-office で絞る。
create or replace function cron_finalize_meal_counts()
returns void language plpgsql security definer set search_path = public as $$
declare o record;
        v_today date := (now() at time zone 'Asia/Tokyo')::date;
        v_dow int := extract(dow from (now() at time zone 'Asia/Tokyo'))::int;
begin
  -- 全社休日(祝日・年末年始・会社休業)は全施設スキップ。
  if exists (select 1 from holidays h where h.holiday_date = v_today) then
    return;
  end if;
  for o in
    select id as office_id from offices where is_feature_enabled_for_office('meal_management_enabled', id)
  loop
    -- 施設の当日曜日が稼働日でなければスキップ(338と同一条件)。
    if not exists (
      select 1 from office_pickup_deadlines d
      where d.office_id = o.office_id and d.day_of_week = v_dow and d.is_operating_day = true
    ) then
      continue;
    end if;
    perform meal_compute_internal(o.office_id, v_today);
    -- この施設の当日を「確定」扱いに(承認の有無に関わらず厨房へ反映済)。初回のみ刻印。
    update meal_count_days
       set finalized_at = now()
     where office_id = o.office_id and business_date = v_today and finalized_at is null;
  end loop;
end $$;
revoke execute on function cron_finalize_meal_counts() from public, anon, authenticated;
grant execute on function cron_finalize_meal_counts() to service_role;

-- 9:31 cron を確定処理に差し替え(名称は finalize に変更)。8:50 materialize(369)はそのまま。
do $$ begin
  perform cron.unschedule('compute-meal-counts');
exception when others then null;
end $$;
do $$ begin
  perform cron.unschedule('finalize-meal-counts');
exception when others then null;
end $$;
select cron.schedule('finalize-meal-counts', '31 0 * * *', $$select cron_finalize_meal_counts();$$);

-- ============================================================
-- (3) 未承認アラート: 確定済みだが一括承認されていない日
--   (一括承認 confirm_meal_day が押されないまま9:31確定した=承認忘れ)
-- ============================================================
create or replace function fetch_unconfirmed_finalized_days(p_days int default 7)
returns table (office_id uuid, office_name text, business_date date, finalized_at timestamptz)
language sql stable security definer set search_path = public as $$
  select d.office_id, o.name, d.business_date, d.finalized_at
  from meal_count_days d
  join offices o on o.id = d.office_id
  where d.finalized_at is not null
    and d.business_date >= (now() at time zone 'Asia/Tokyo')::date - greatest(p_days, 0)
    and has_childcare_office_access(d.office_id)
    and exists (
      select 1 from meal_count_rows r
      where r.office_id = d.office_id and r.business_date = d.business_date and r.is_confirmed = false
    )
  order by d.business_date desc, o.name;
$$;
grant execute on function fetch_unconfirmed_finalized_days(int) to authenticated, service_role;
