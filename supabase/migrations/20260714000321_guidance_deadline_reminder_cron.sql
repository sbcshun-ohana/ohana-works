-- 321: 月案の提出締切「事前通知」を担任(class_homeroom_assignments・一般職員)へ配信(俊指示2026-08-25)。
-- 締切=guidance_monthly_deadline(今月)。締切1週間前〜締切当日の間、翌月の月案が未提出のクラスの担任へ
--   push+in_app 通知(冪等: 担任×クラス×実行日で1回)。土日繰上げ後の締切に自然に追随。
-- 主任以上の「締切超過・未提出」はアラートバー(320)が担うため、本通知は担任のみ・締切前の予告に限定。
create or replace function cron_guidance_monthly_deadline_reminders()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_y int := extract(year from current_date)::int;
  v_m int := extract(month from current_date)::int;
  v_fiscal int; v_next_month int; v_next_fiscal int; v_deadline date;
begin
  v_fiscal := case when v_m >= 4 then v_y else v_y - 1 end;
  v_deadline := guidance_monthly_deadline(v_y, v_m);
  -- 締切1週間前〜締切当日のみ(事前通知)。それ以外は何もしない。
  if current_date < v_deadline - 7 or current_date > v_deadline then return; end if;
  v_next_month := case when v_m = 12 then 1 else v_m + 1 end;
  v_next_fiscal := case when v_m = 3 then v_fiscal + 1 else v_fiscal end;

  insert into notifications (notification_type, title, body, channels, target_employee_id, payload, status)
  select distinct 'guidance_deadline_reminder',
    '月案の提出締切が近づいています',
    cc.class_name || ' の ' || v_next_month || '月の月案(対象児は個人案含む)の提出締切は '
      || to_char(v_deadline, 'MM/DD') || ' です。ご提出をお願いします。',
    array['in_app', 'push'], cha.employee_id,
    jsonb_build_object('class_id', cc.id::text,
      'target', v_next_fiscal::text || '-' || lpad(v_next_month::text, 2, '0'),
      'date', current_date::text),
    'pending'
  from childcare_classes cc
  join class_homeroom_assignments cha on cha.class_id = cc.id and cha.unassigned_at is null
  where cc.is_active
    and is_guidance_plans_enabled_for_office(cc.office_id)
    -- 翌月の月案が未提出(行なし or draft)のクラスのみ
    and not exists (
      select 1 from guidance_plans gp
      where gp.office_id = cc.office_id and gp.class_id = cc.id and gp.plan_type = 'monthly'
        and gp.fiscal_year = v_next_fiscal and gp.month = v_next_month
        and gp.status in ('submitted', 'chief_checked', 'approved')
    )
    -- 冪等: 同じ担任×クラス×実行日で1回
    and not exists (
      select 1 from notifications n
      where n.notification_type = 'guidance_deadline_reminder'
        and n.target_employee_id = cha.employee_id
        and n.payload->>'class_id' = cc.id::text
        and n.payload->>'date' = current_date::text
    );
end $$;

-- 07:00 JST(= 22:00 UTC)に実行。冪等(存在時のみ付替)。
do $$
begin
  if exists (select 1 from cron.job where jobname = 'guidance_monthly_deadline_reminders') then
    perform cron.unschedule('guidance_monthly_deadline_reminders');
  end if;
  perform cron.schedule('guidance_monthly_deadline_reminders', '0 22 * * *', 'select cron_guidance_monthly_deadline_reminders();');
end $$;
