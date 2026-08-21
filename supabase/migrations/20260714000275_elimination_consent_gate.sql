-- 275: アレルギー管理 Phase2-b = 除去食の提供開始ゲート(給食会議+保護者同意)。経過措置あり。
-- 設計書§7: 共通除去食の提供開始条件に「給食会議の保護者同意」を追加する。
-- fetch_daily_elimination_for_office(232/233)を改修し、除去食対象児の handling を同意状況で分岐:
--   ・保護者同意あり(meal_conference_consents) → そのまま 'elimination'(除去食提供)
--   ・経過措置対象(下記カットオフ日までに診断書受領=現在提供中)→ 'elimination'(継続・運用を止めない)
--   ・上記いずれも無い新規 → 'bento'(弁当持参・同意待ち)。未同意の除去食提供を防ぐ(安全側)。
-- consent_status(ok/waived/pending)を返却に追加し、ボード/厨房で同意状況を把握できるようにする。
-- 経過措置カットオフ = 2026-08-21(このmigration適用日)。以降に受領した新規診断は会議+同意が必須。

-- 戻り値に consent_status を追加するため drop してから作り直す。
drop function if exists fetch_daily_elimination_for_office(uuid, date);
create or replace function fetch_daily_elimination_for_office(p_office_id uuid, p_business_date date)
returns table (
  child_id uuid,
  child_name text,
  class_name text,
  handling text,
  elimination_targets text[],
  consent_status text            -- 'ok'=同意あり / 'waived'=経過措置 / 'pending'=同意待ち / null=除去食対象外
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not has_childcare_office_access(p_office_id) then
    raise exception 'not authorized';
  end if;
  return query
  with base as (
    select c.id as bid, c.display_name as bname, cc.class_name as bclass,
      (select array_agg(distinct t)
       from child_allergy_diagnoses d, unnest(coalesce(d.elimination_targets, '{}')) t
       where d.child_id = c.id and d.status = 'received'
         and (d.effective_from is null or d.effective_from <= p_business_date)
         and (d.effective_until is null or d.effective_until >= p_business_date)) as targets,
      exists (select 1 from child_allergy_diagnoses d
              where d.child_id = c.id and d.status = 'requested') as pending_diag,
      exists (select 1 from child_food_records r
              where r.child_id = c.id and r.result = 'symptom' and r.staff_confirmed_at is null) as pending_sym,
      exists (select 1 from child_food_records r
              where r.child_id = c.id and r.result = 'symptom' and r.staff_confirmed_at is not null) as review_sym,
      exists (select 1 from child_allergy_diagnoses d
              where d.child_id = c.id and d.status in ('received', 'released')) as medical_resolved,
      -- 除去食提供に対する保護者同意(272)。取消会議の同意は除外。
      exists (select 1 from meal_conference_consents cs
              join meal_conferences mc on mc.id = cs.conference_id
              where cs.child_id = c.id and mc.status <> 'cancelled') as has_consent,
      -- 経過措置: カットオフ日までに受領済みの有効な診断書(=現在提供中)は同意なしでも継続。
      exists (select 1 from child_allergy_diagnoses d
              where d.child_id = c.id and d.status = 'received'
                and d.received_at is not null and d.received_at <= date '2026-08-21'
                and (d.effective_from is null or d.effective_from <= p_business_date)
                and (d.effective_until is null or d.effective_until >= p_business_date)
                and coalesce(array_length(d.elimination_targets, 1), 0) > 0) as grandfathered
    from children c
    left join child_class_enrollments cce on cce.child_id = c.id and cce.effective_end_date is null
    left join childcare_classes cc on cc.id = cce.class_id
    where c.office_id = p_office_id and c.enrollment_status = '在籍中'
      and not exists (
        select 1 from child_daily_attendance a
        where a.child_id = c.id and a.business_date = p_business_date and a.is_absent
      )
  )
  select bid, bname, bclass,
    case
      when pending_sym then 'hold'
      when pending_diag then 'bento'
      when array_length(targets, 1) > 0 then
        case when has_consent or grandfathered then 'elimination' else 'bento' end
      when review_sym and not medical_resolved then 'hold'
      else null
    end,
    -- 除去食材は「実際に除去食を提供する(=同意あり/経過措置)」ときだけ厨房へ渡す。
    -- 同意待ち(bento)のときは弁当持参のため除去食材は空にする。
    case when array_length(targets, 1) > 0 and not pending_sym and not pending_diag
              and (has_consent or grandfathered)
         then coalesce(targets, '{}') else '{}'::text[] end,
    case when array_length(targets, 1) > 0 and not pending_sym and not pending_diag then
      case when has_consent then 'ok' when grandfathered then 'waived' else 'pending' end
    else null end
  from base
  where pending_sym or pending_diag or array_length(targets, 1) > 0
     or (review_sym and not medical_resolved)
  order by bclass, bname;
end;
$$;
grant execute on function fetch_daily_elimination_for_office(uuid, date) to authenticated, service_role;
