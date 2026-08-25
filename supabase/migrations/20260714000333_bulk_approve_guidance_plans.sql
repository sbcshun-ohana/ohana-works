-- 333: 指導計画の一括承認(俊指示 2026-08-25・改訂)。1クラスずつ承認するのが手間なため、
--   その施設・年度で「承認待ち」の計画をまとめて承認する。権限は単体承認と同じ
--   (統括園長・園長=can_approve_guidance_plan)。
--   承認待ち=申請中(submitted)＋主任確認済(chief_checked) の両方。認可(大和)の2段階では
--   本来 担当申請→主任確認→承認 だが、承認者(統括園長・園長)による「一括承認」では、まだ主任確認前
--   (申請中)のものも含めてまとめて承認する(俊確認: ほし組8月/9月が申請中で0件だった件の対応)。
--   その際、監査の整合のため主任確認欄も承認者名で補完する。下書き/既承認は対象外。作成者へは各件通知。
create or replace function bulk_approve_guidance_plans(p_office_id uuid, p_fiscal_year int)
returns int language plpgsql security definer set search_path = public as $$
declare v_count int := 0; r record;
begin
  if not can_approve_guidance_plan(p_office_id) then raise exception '承認は統括園長・園長が行えます'; end if;

  for r in
    select id, created_by from guidance_plans
    where office_id = p_office_id and fiscal_year = p_fiscal_year
      and status in ('submitted', 'chief_checked')
  loop
    update guidance_plans set
      status = 'approved',
      chief_checked_at = coalesce(chief_checked_at, now()),
      chief_checked_by = coalesce(chief_checked_by, my_employee_id()),
      approved_at = now(),
      approved_by = my_employee_id()
      where id = r.id;
    if r.created_by is not null and r.created_by <> my_employee_id() then
      insert into notifications (notification_type, title, body, channels, target_employee_id, payload, status)
      values ('guidance_plan_approved', '指導計画が承認されました', '申請した指導計画が承認されました。',
        array['in_app'], r.created_by, jsonb_build_object('guidance_plan_id', r.id::text), 'pending');
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;
grant execute on function bulk_approve_guidance_plans(uuid, int) to authenticated, service_role;
