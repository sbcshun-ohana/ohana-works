-- 408: 一時預かり児の「休止/再開」(俊要望 2026-08-31)。
--   不定期利用: 当面使わない児をデイリーボードから非表示にしたいが、マスター情報は残して
--   次回そのまま再利用したい。→ クラス在籍を閉じる(休止)/開き直す(再開)で実現。
--     休止: 開いている在籍を effective_end_date=今日 でクローズ → 翌日以降ボード非表示。
--           enrollment_status は '在籍中' のまま = 一時預かり一覧には残る(再利用可)。
--     再開: 新しい在籍行(effective_start_date=今日・end=null)を作成 → ボード再表示。
--   利用中(active) = 開いている在籍(effective_end_date is null)が存在する状態。

create or replace function set_temp_care_active(p_child_id uuid, p_active boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_office uuid;
  v_kind text;
  v_status text;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
  v_fiscal int := case when extract(month from (now() at time zone 'Asia/Tokyo')::date) >= 4
                       then extract(year from (now() at time zone 'Asia/Tokyo')::date)::int
                       else extract(year from (now() at time zone 'Asia/Tokyo')::date)::int - 1 end;
  v_class uuid;
begin
  select office_id, child_kind, enrollment_status into v_office, v_kind, v_status
  from children where id = p_child_id;
  if v_office is null then raise exception 'not found'; end if;
  if v_kind <> 'temporary' then raise exception '一時預かり児のみ操作できます'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  if v_status = '退園済み' then raise exception '登録取消済みの児は操作できません'; end if;

  if p_active then
    -- 再開: 開いている在籍が無ければ新規在籍を作成(ボード再表示)
    if not exists (select 1 from child_class_enrollments
                   where child_id = p_child_id and effective_end_date is null) then
      v_class := ensure_temp_care_class(v_office, v_fiscal);
      insert into child_class_enrollments (child_id, class_id, effective_start_date, assigned_by)
      values (p_child_id, v_class, v_today, my_employee_id());
    end if;
  else
    -- 休止: 開いている在籍を今日でクローズ(翌日以降ボード非表示)
    update child_class_enrollments set effective_end_date = v_today
    where child_id = p_child_id and effective_end_date is null;
  end if;
end;
$$;
grant execute on function set_temp_care_active(uuid, boolean) to authenticated, service_role;
revoke execute on function set_temp_care_active(uuid, boolean) from public, anon;

-- fetch_temp_care_children に is_active(利用中=開いている在籍あり)を追加(戻り値型変更のため drop→create)
drop function if exists fetch_temp_care_children(uuid);
create function fetch_temp_care_children(p_office_id uuid)
returns table (
  child_id uuid, display_name text, name_kana text, birth_date date, gender text,
  nursery_age int, class_name text, contact_required boolean, nap_required boolean,
  enrollment_date date, is_active boolean
)
language plpgsql stable security definer set search_path = public as $$
declare v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  return query
  select c.id, c.display_name, c.name_kana, c.birth_date, c.gender,
         nursery_age_for_date(c.birth_date, v_today),
         cl.class_name,
         coalesce(c.family_daily_report_required_override, cl.family_daily_report_required, false),
         coalesce(c.nap_check_required_override, cl.nap_check_required, false),
         c.enrollment_date,
         exists (select 1 from child_class_enrollments e
                 where e.child_id = c.id and e.effective_end_date is null)
  from children c
  left join lateral (
    select cl.class_name, cl.family_daily_report_required, cl.nap_check_required
    from child_class_enrollments cce
    join childcare_classes cl on cl.id = cce.class_id
    where cce.child_id = c.id
    order by cce.effective_start_date desc limit 1
  ) cl on true
  where c.office_id = p_office_id
    and c.child_kind = 'temporary'
    and c.enrollment_status <> '退園済み'
  order by c.enrollment_date desc, c.display_name;
end;
$$;
grant execute on function fetch_temp_care_children(uuid) to authenticated, service_role;
revoke execute on function fetch_temp_care_children(uuid) from public, anon;
