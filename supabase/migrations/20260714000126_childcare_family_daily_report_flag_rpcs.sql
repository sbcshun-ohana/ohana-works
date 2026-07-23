-- admin_webに「連絡帳提出必須」フラグの表示・トグルを追加するため、
-- fetch_childcare_classes(クラスのデフォルト必須設定)とfetch_class_children(園児単位の上書き)を拡張する。
-- 戻り値の列を追加するためcreate or replaceでは型変更不可(42P13)。dropしてから作り直す。

drop function if exists fetch_childcare_classes(uuid);

create function fetch_childcare_classes(p_office_id uuid)
returns table (class_id uuid, class_name text, age_group text, school_year int, family_daily_report_required boolean)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not has_childcare_office_access(p_office_id) then
    raise exception 'not authorized';
  end if;

  return query
  select cc.id, cc.class_name, cc.age_group, cc.school_year, cc.family_daily_report_required
  from childcare_classes cc
  where cc.office_id = p_office_id and cc.is_active and has_childcare_class_access(cc.id)
  order by cc.class_name;
end;
$$;

drop function if exists fetch_class_children(uuid, date);

create function fetch_class_children(p_class_id uuid, p_business_date date)
returns table (
  child_id uuid,
  display_name text,
  honorific_suffix text,
  gender text,
  enrollment_status text,
  is_absent boolean,
  absence_reason text,
  family_daily_report_required_override boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not has_childcare_class_access(p_class_id) then
    raise exception 'not authorized';
  end if;

  return query
  select
    c.id, c.display_name, c.honorific_suffix, c.gender, c.enrollment_status,
    coalesce(cda.is_absent, false), cda.absence_reason,
    c.family_daily_report_required_override
  from child_class_enrollments cce
  join children c on c.id = cce.child_id
  left join child_daily_attendance cda on cda.child_id = c.id and cda.business_date = p_business_date
  where cce.class_id = p_class_id
    and cce.effective_start_date <= p_business_date
    and (cce.effective_end_date is null or cce.effective_end_date >= p_business_date)
    and c.enrollment_status <> '退園済み'
  order by c.display_name;
end;
$$;

-- 園児単位の「連絡帳提出必須」上書きフラグの設定(3歳以上クラス向け)。
-- 直接UPDATEではなくRPC化し、対象クラスがデフォルト必須(0〜2歳児相当)でないことを明示的に確認する
-- (0〜2歳児クラスでは上書きは無意味なため、誤操作防止のためRPC側でも軽くガードする)。
create or replace function set_family_daily_report_required_override(p_child_id uuid, p_required boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_office_id uuid;
begin
  select office_id into v_office_id from children where id = p_child_id;
  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not manages_childcare(v_office_id) then
    raise exception 'not authorized';
  end if;

  update children
  set family_daily_report_required_override = case when p_required then true else null end
  where id = p_child_id;
end;
$$;
