-- 253: ヒヤリハット・事故報告 Phase B ②(未クローズ通知 cron)。設計指示書v2 §3.3 + §7②俊回答。
-- 発生から施設別しきい値(既定1日=発生翌日)を過ぎても未クローズの事故報告書がある施設に、
-- 日次で1通(件数集約)を 管理者以上+統括園長 へ通知。本文に園児名は含めない(件数+施設+導線のみ)。
-- 以後、未クローズが残る限り毎日再通知(incident_unclosed_notified_on で当日重複を防止)。
create or replace function cron_notify_open_incidents()
returns void
language plpgsql security definer set search_path = public
as $$
declare
  o record;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  for o in
    select r.office_id as office_id, count(*)::int as cnt, o2.name as office_name
    from incident_reports r
    join childcare_office_settings s on s.office_id = r.office_id
    join offices o2 on o2.id = r.office_id
    where r.closure_status = 'open'
      and r.report_type in ('minor', 'hospital')
      and r.occurred_on + s.incident_unclosed_notify_days <= v_today
      and (s.incident_unclosed_notified_on is null or s.incident_unclosed_notified_on < v_today)
    group by r.office_id, o2.name
  loop
    insert into notifications (notification_type, title, body, channels, target_employee_id, payload)
    select 'incident_unclosed', '未クローズの事故報告',
           o.cnt::text || '件の事故報告書が未クローズです。保護者対応の完了確認をお願いします。',
           array['in_app'], t.employee_id,
           jsonb_build_object('office_id', o.office_id, 'count', o.cnt)
    from (
      select distinct er.employee_id
      from employee_roles er
      join roles ro on ro.id = er.role_id
      where ro.code in ('system_admin', 'executive_director')
         or (ro.code in ('director', 'office_manager') and (er.office_id is null or er.office_id = o.office_id))
    ) t;

    update childcare_office_settings set incident_unclosed_notified_on = v_today where office_id = o.office_id;
  end loop;
end;
$$;

-- 毎日 08:00 JST(= 23:00 UTC)に実行。冪等(既存ジョブがあれば張り替え)。
do $$
begin
  if exists (select 1 from cron.job where jobname = 'notify-open-incidents') then
    perform cron.unschedule('notify-open-incidents');
  end if;
end $$;
select cron.schedule('notify-open-incidents', '0 23 * * *', $$select cron_notify_open_incidents();$$);
