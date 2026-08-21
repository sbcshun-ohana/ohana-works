-- 276: アレルギー管理 Phase2-c = 除去食献立の保護者限定公開。
-- 設計書§7/§9: 除去食提供中の児の保護者だけが、自分の子の除去代替献立を閲覧できる。
-- 既存 fetch_published_menu_days_for_guardian(270)は allergy_removed をブロックしている。
-- 本RPCは「除去食を実際に提供している児(275と同じ同意/経過措置の判定)」の保護者にのみ、
-- 公開済みの allergy_removed 献立を返す。該当外の保護者には一切出さない(空配列)。

create or replace function fetch_allergy_menu_days_for_child(p_child_id uuid, p_target_month date)
returns table (menu_date date, meal_slot text, menu_text text, ingredients jsonb,
               removal_kind text, removal_note text)
language plpgsql security definer set search_path = public as $$
declare
  v_office uuid;
  v_month date := date_trunc('month', p_target_month)::date;
  v_eligible boolean;
begin
  if not guardian_has_child_access(p_child_id) then raise exception 'not authorized'; end if;
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then return; end if;
  if not is_meal_parent_section_enabled_for_office(v_office) then return; end if;

  -- 除去食を実際に提供中か(275と同じ判定・当日欠席は問わない):
  --   有効な受領診断書に除去対象があり、かつ 保護者同意あり or 経過措置(受領<=カットオフ)。
  select
    exists (
      select 1 from child_allergy_diagnoses d
      where d.child_id = p_child_id and d.status = 'received'
        and coalesce(array_length(d.elimination_targets, 1), 0) > 0
        and (d.effective_from is null or d.effective_from <= current_date)
        and (d.effective_until is null or d.effective_until >= current_date)
    )
    and (
      exists (select 1 from meal_conference_consents cs
              join meal_conferences mc on mc.id = cs.conference_id
              where cs.child_id = p_child_id and mc.status <> 'cancelled')
      or exists (select 1 from child_allergy_diagnoses d
                 where d.child_id = p_child_id and d.status = 'received'
                   and d.received_at is not null and d.received_at <= date '2026-08-21'
                   and coalesce(array_length(d.elimination_targets, 1), 0) > 0
                   and (d.effective_from is null or d.effective_from <= current_date)
                   and (d.effective_until is null or d.effective_until >= current_date))
    )
  into v_eligible;

  if not v_eligible then return; end if;

  return query
    select d.menu_date, d.meal_slot, d.menu_text, d.ingredients, d.removal_kind, d.removal_note
    from menu_days d join menu_imports mi on mi.id = d.import_id
    where d.office_id = v_office and d.food_type = 'allergy_removed' and mi.status = 'published'
      and d.menu_date >= v_month and d.menu_date < (v_month + interval '1 month')::date
    order by d.menu_date, d.meal_slot;
end $$;
grant execute on function fetch_allergy_menu_days_for_child(uuid, date) to authenticated, service_role;
