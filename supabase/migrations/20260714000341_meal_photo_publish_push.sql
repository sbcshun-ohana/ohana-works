-- 341: 給食写真の公開時プッシュ(給食管理 §8/§9.2・任意・既定OFF・俊指示 2026-08-25)。
--   施設別フラグ meal_photo_push_enabled(既定OFF)がONの施設のみ、写真公開時に在籍児の保護者へ
--   in_app+push 通知。うるさくしないため「その日の初回公開」のみ通知する。
--   保護者通知は target_guardian_id(dispatch-pending-notifications が push_device_tokens と突合)経由。
insert into feature_flags (feature_key, name, description, default_enabled) values
  ('meal_photo_push_enabled', '給食写真の公開プッシュ',
   '給食写真を公開したとき、在籍児の保護者へプッシュ通知する(任意・既定OFF・施設別ON・その日の初回のみ)。', false)
on conflict (feature_key) do nothing;

create or replace function approve_meal_photo(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v meal_photos%rowtype; v_first boolean;
begin
  select * into v from meal_photos where id = p_id for update;
  if v.id is null then raise exception 'photo not found'; end if;
  if not is_childcare_admin(v.office_id) then raise exception 'not authorized'; end if;
  if v.status = 'published' then return; end if;

  -- 公開前に「その日すでに公開済みの写真があるか」を判定(初回公開のみ通知するため)。
  v_first := not exists (
    select 1 from meal_photos m
    where m.office_id = v.office_id and m.business_date = v.business_date
      and m.status = 'published' and m.id <> p_id
  );

  update meal_photos set status = 'published', approved_by = my_employee_id(), approved_at = now(), rejected_reason = null
    where id = p_id;

  -- 施設フラグONかつその日の初回公開なら、在籍児の保護者へ通知。
  if v_first and is_feature_enabled_for_office('meal_photo_push_enabled', v.office_id) then
    insert into notifications (notification_type, title, body, channels, target_guardian_id, payload, status)
    select 'meal_photo_published', '本日の給食',
           '本日の給食の写真が公開されました。アプリの「給食」でご覧いただけます。',
           array['in_app', 'push'], g.gid,
           jsonb_build_object('office_id', v.office_id::text, 'business_date', v.business_date::text), 'pending'
    from (
      select distinct gcl.guardian_id as gid
      from guardian_child_links gcl
      join children ch on ch.id = gcl.child_id
      where ch.office_id = v.office_id and ch.enrollment_status = '在籍中'
    ) g;
  end if;
end $$;
grant execute on function approve_meal_photo(uuid) to authenticated, service_role;
