-- 344: 厨房ビュー用・複数施設のアレルギー対応者リスト(給食管理・俊相談 2026-08-26)。
--   厨房が「作るアレルギー食」を1画面で把握するため、担当施設の当日の除去食対象児(elimination)と
--   弁当持参(bento=提供なし)を施設別に返す。各児の代替(除去/代替内容)は当日の除去食献立
--   (menu_days food_type='allergy_removed'・removal_kind一致)の removal_note から取得。
--   既存の fetch_daily_elimination_for_office(275・同意状況分岐)を施設ごとに束ねる(二重管理しない)。
create or replace function fetch_meal_allergy_crossoffice(p_office_ids uuid[], p_business_date date)
returns table (
  office_id uuid, office_name text, office_code text,
  child_name text, class_name text, handling text,
  allergens text[], substitute text, consent_status text
)
language plpgsql stable security definer set search_path = public as $$
declare v_oid uuid;
begin
  foreach v_oid in array p_office_ids loop
    if not has_childcare_office_access(v_oid) then raise exception 'not authorized for office %', v_oid; end if;
  end loop;
  return query
  select o.id, o.name, o.office_code,
         e.child_name, e.class_name, e.handling, e.elimination_targets,
         (select string_agg(md.removal_kind || ': ' || coalesce(nullif(btrim(md.removal_note), ''), '除去のみ'), ' / '
                   order by md.removal_kind)
            from menu_days md
            join menu_imports mi on mi.id = md.import_id
            where md.office_id = o.id and md.menu_date = p_business_date and mi.status = 'published'
              and md.food_type = 'allergy_removed' and md.removal_kind = any(e.elimination_targets)),
         e.consent_status
  from unnest(p_office_ids) as u(oid)
  join offices o on o.id = u.oid
  cross join lateral fetch_daily_elimination_for_office(u.oid, p_business_date) e
  where e.handling in ('elimination', 'bento')
  order by o.office_code,
    case e.handling when 'elimination' then 0 else 1 end,
    e.class_name, e.child_name;
end $$;
grant execute on function fetch_meal_allergy_crossoffice(uuid[], date) to authenticated, service_role;
