-- 214: 園内連絡「施設全体」宛ての確認対象を拡大(俊テストで発覚した運用課題・2026-08-14適用済み)。
-- 156の設計では facility=在籍職員(employee_office_assignments)のみだったが、
-- 在籍行を持たない管理職(統括園長・付与された統括管理者等)が確認対象に入らないため、
-- facility の判定を office_accessible_employee_ids(在籍+施設スコープ管理者+統括)へ拡大する。
-- band/class/individual の判定は不変。設計書§6.1からの意図的変更。冪等: create or replace のみ。

create or replace function is_staff_message_addressed_to(p_message_id uuid, p_employee_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from staff_messages m
    join staff_message_targets t on t.message_id = m.id
    where m.id = p_message_id and m.deleted_at is null
      and (
        (t.target_type = 'individual' and t.employee_id = p_employee_id)
        -- 214: facility=在籍職員+管理職(アクセス可能職員)へ拡大
        or (t.target_type = 'facility' and p_employee_id in (select office_accessible_employee_ids(m.office_id)))
        or (t.target_type = 'class' and exists (
              select 1 from class_homeroom_assignments cha
              where cha.class_id = t.class_id and cha.employee_id = p_employee_id and cha.unassigned_at is null))
        or (t.target_type = 'band' and m.target_date is not null and exists (
              select 1 from shifts s join staff_time_bands b on b.id = t.band_id
              where s.employee_id = p_employee_id and s.work_date = m.target_date
                and s.office_id = m.office_id and s.status in ('draft', 'confirmed')
                and (
                  case
                    when b.start_from is not null then s.start_time between b.start_from and b.start_until
                    when b.end_from is not null then s.end_time between b.end_from and b.end_until
                    else not exists (
                      select 1 from staff_time_bands b2 where b2.office_id = m.office_id and (
                        (b2.start_from is not null and s.start_time between b2.start_from and b2.start_until) or
                        (b2.end_from is not null and s.end_time between b2.end_from and b2.end_until)))
                  end
                )))
      )
  );
$$;
