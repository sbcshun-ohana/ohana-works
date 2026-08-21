-- 273: (A) 保護者向け 除去食同意の履歴取得(272の補完・読み取りのみ)。
--      (B) 給食会議に「園側の出席者(職員)」を追加。氏名を選択して記録。
-- 保護者アプリで「給食会議で同意しました」という過去の同意記録を後から確認できるようにする。

-- ============================================================
-- (B) 給食会議の園側出席者(職員)。氏名スナップショットではなく職員IDで保持し、表示時に解決。
-- ============================================================
alter table meal_conferences add column if not exists attendee_employee_ids uuid[];
comment on column meal_conferences.attendee_employee_ids is '給食会議の園側出席者(職員)id配列(273・§7)。栄養士名は委託先テキスト(nutritionist_name)で別管理。';

-- create_meal_conference に出席者パラメータを追加(旧シグネチャは破棄)。
drop function if exists create_meal_conference(uuid, uuid, date, text, text);
create or replace function create_meal_conference(
  p_child_id uuid, p_diagnosis_id uuid, p_held_on date, p_nutritionist_name text, p_elimination_plan text,
  p_attendee_employee_ids uuid[]
)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_id uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  insert into meal_conferences (child_id, office_id, diagnosis_id, held_on, nutritionist_name,
                                recorder_employee_id, elimination_plan, attendee_employee_ids, created_by)
  values (p_child_id, v_office, p_diagnosis_id, p_held_on, p_nutritionist_name,
          my_employee_id(), p_elimination_plan, p_attendee_employee_ids, my_employee_id())
  returning id into v_id;
  return v_id;
end $$;
grant execute on function create_meal_conference(uuid, uuid, date, text, text, uuid[]) to authenticated, service_role;

-- 児ごとの会議一覧(出席者名を追加)。戻り値の型が変わるため drop してから作り直す。
drop function if exists fetch_meal_conferences_for_child(uuid);
create or replace function fetch_meal_conferences_for_child(p_child_id uuid)
returns table (id uuid, diagnosis_id uuid, held_on date, nutritionist_name text, recorder_name text,
               elimination_plan text, status text, created_at timestamptz,
               consent_at timestamptz, consent_guardian_name text, attendee_names text[])
language plpgsql security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  return query
    select mc.id, mc.diagnosis_id, mc.held_on, mc.nutritionist_name, e.name,
           mc.elimination_plan, mc.status, mc.created_at,
           cs.agreed_at, cs.agreed_guardian_name,
           (select array_agg(ae.name order by ae.name) from employees ae
            where ae.id = any(mc.attendee_employee_ids))
    from meal_conferences mc
    left join employees e on e.id = mc.recorder_employee_id
    left join lateral (
      select agreed_at, agreed_guardian_name from meal_conference_consents
      where conference_id = mc.id order by agreed_at desc limit 1
    ) cs on true
    where mc.child_id = p_child_id
    order by mc.created_at desc;
end $$;
grant execute on function fetch_meal_conferences_for_child(uuid) to authenticated, service_role;

-- 施設の会議一覧(出席者名を追加)。主任以上。戻り値の型が変わるため drop してから作り直す。
drop function if exists fetch_meal_conferences_for_office(uuid, boolean);
create or replace function fetch_meal_conferences_for_office(p_office_id uuid, p_only_unconsented boolean default false)
returns table (id uuid, child_id uuid, child_name text, held_on date, nutritionist_name text,
               status text, created_at timestamptz, consent_at timestamptz, attendee_names text[])
language plpgsql security definer set search_path = public as $$
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  return query
    select mc.id, mc.child_id, c.display_name, mc.held_on, mc.nutritionist_name,
           mc.status, mc.created_at,
           (select max(agreed_at) from meal_conference_consents where conference_id = mc.id),
           (select array_agg(ae.name order by ae.name) from employees ae
            where ae.id = any(mc.attendee_employee_ids))
    from meal_conferences mc join children c on c.id = mc.child_id
    where mc.office_id = p_office_id and mc.status <> 'cancelled'
      and (not p_only_unconsented or mc.status = 'held')
    order by mc.created_at desc;
end $$;
grant execute on function fetch_meal_conferences_for_office(uuid, boolean) to authenticated, service_role;

-- ============================================================
-- (A) 保護者向け 除去食同意の履歴取得。対象児の保護者のみ。文面snapshotも返す。
-- ============================================================
create or replace function fetch_meal_consents_for_child(p_child_id uuid)
returns table (
  id uuid,
  conference_id uuid,
  agreed_at timestamptz,
  agreed_guardian_name text,
  consent_text_snapshot text,
  held_on date,
  nutritionist_name text,
  elimination_plan text
)
language plpgsql security definer set search_path = public as $$
begin
  if not guardian_has_child_access(p_child_id) then raise exception 'not authorized'; end if;
  return query
    select cs.id, cs.conference_id, cs.agreed_at, cs.agreed_guardian_name, cs.consent_text_snapshot,
           mc.held_on, mc.nutritionist_name, mc.elimination_plan
    from meal_conference_consents cs
    join meal_conferences mc on mc.id = cs.conference_id
    where cs.child_id = p_child_id
    order by cs.agreed_at desc;
end $$;
grant execute on function fetch_meal_consents_for_child(uuid) to authenticated, service_role;
