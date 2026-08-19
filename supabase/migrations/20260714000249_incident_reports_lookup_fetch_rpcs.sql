-- 249: ヒヤリハット・事故報告 Phase A ④(ルックアップCRUD + fetch RPC)。
-- ルックアップ管理=管理者以上(is_childcare_admin_any)。閲覧=全施設の保育職員(is_childcare_staff)。

-- ルックアップの追加/更新(kindは作成時固定・更新はlabel/sort_order)
create or replace function upsert_incident_lookup_option(
  p_id uuid, p_kind text, p_label text, p_sort_order int)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_id uuid;
begin
  if not is_childcare_admin_any() then raise exception 'not authorized'; end if;
  if p_id is null then
    if p_kind not in ('place','injury_site','med_department','med_exam','med_treatment','med_prescription') then
      raise exception 'invalid kind';
    end if;
    insert into incident_lookup_options (kind, label, sort_order)
    values (p_kind, p_label, coalesce(p_sort_order, 0)) returning id into v_id;
  else
    update incident_lookup_options
      set label = p_label, sort_order = coalesce(p_sort_order, sort_order), updated_at = now()
    where id = p_id returning id into v_id;
    if v_id is null then raise exception 'not found'; end if;
  end if;
  return v_id;
end;
$$;
grant execute on function upsert_incident_lookup_option(uuid, text, text, int) to authenticated, service_role;

-- ルックアップの有効/無効(既存データは壊さずソフト無効化)
create or replace function set_incident_lookup_option_active(p_id uuid, p_active boolean)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not is_childcare_admin_any() then raise exception 'not authorized'; end if;
  update incident_lookup_options set is_active = p_active, updated_at = now() where id = p_id;
  if not found then raise exception 'not found'; end if;
end;
$$;
grant execute on function set_incident_lookup_option_active(uuid, boolean) to authenticated, service_role;

-- ルックアップ取得(フォームのプルダウン。p_kind=null で全種別・有効のみ)
create or replace function fetch_incident_lookup_options(p_kind text)
returns table (id uuid, kind text, label text, sort_order int)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not is_childcare_staff() then raise exception 'not authorized'; end if;
  return query
  select o.id, o.kind, o.label, o.sort_order
  from incident_lookup_options o
  where o.is_active and (p_kind is null or o.kind = p_kind)
  order by o.kind, o.sort_order, o.label;
end;
$$;
grant execute on function fetch_incident_lookup_options(text) to authenticated, service_role;

-- 一覧(全施設閲覧。フィルタ office/status/type は null で全件)
create or replace function fetch_incident_reports(
  p_office_id uuid, p_status text, p_report_type text)
returns table (
  id uuid, office_id uuid, office_name text, report_type text, status text,
  occurred_on date, occurred_at time, place_label text, closure_status text,
  child_names text, created_by_name text,
  submitted_at timestamptz, approved_at timestamptz, updated_at timestamptz
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not is_childcare_staff() then raise exception 'not authorized'; end if;
  return query
  select r.id, r.office_id, o.name, r.report_type, r.status,
         r.occurred_on, r.occurred_at,
         coalesce(lo.label, r.place_other) as place_label,
         r.closure_status,
         (select string_agg(coalesce(c.child_name_snapshot, ''), '、' order by c.created_at)
          from incident_report_children c where c.incident_report_id = r.id) as child_names,
         e.name as created_by_name,
         r.submitted_at, r.approved_at, r.updated_at
  from incident_reports r
  join offices o on o.id = r.office_id
  left join incident_lookup_options lo on lo.id = r.place_option_id
  left join employees e on e.id = r.created_by
  where (p_office_id is null or r.office_id = p_office_id)
    and (p_status is null or r.status = p_status)
    and (p_report_type is null or r.report_type = p_report_type)
  order by r.occurred_on desc, r.occurred_at desc nulls last, r.created_at desc;
end;
$$;
grant execute on function fetch_incident_reports(uuid, text, text) to authenticated, service_role;

-- 詳細(本体+全子コレクションをjsonbで返す)
create or replace function fetch_incident_report_detail(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare v jsonb;
begin
  if not is_childcare_staff() then raise exception 'not authorized'; end if;
  select jsonb_build_object(
    'report', to_jsonb(r),
    'office_name', (select name from offices where id = r.office_id),
    'created_by_name', (select name from employees where id = r.created_by),
    'chief_approved_by_name', (select name from employees where id = r.chief_approved_by),
    'approved_by_name', (select name from employees where id = r.approved_by),
    'place_label', coalesce((select label from incident_lookup_options where id = r.place_option_id), r.place_other),
    'injury_site_label', (select label from incident_lookup_options where id = r.injury_site_option_id),
    'children', coalesce((select jsonb_agg(to_jsonb(c) order by c.created_at)
        from incident_report_children c where c.incident_report_id = r.id), '[]'::jsonb),
    'progress_logs', coalesce((select jsonb_agg(to_jsonb(pl) order by pl.logged_at)
        from incident_report_progress_logs pl where pl.incident_report_id = r.id), '[]'::jsonb),
    'guardian_contacts', coalesce((select jsonb_agg(to_jsonb(gc) order by gc.contacted_at)
        from incident_report_guardian_contacts gc where gc.incident_report_id = r.id), '[]'::jsonb),
    'medical_visits', coalesce((select jsonb_agg(to_jsonb(mv) order by mv.created_at)
        from incident_report_medical_visits mv where mv.incident_report_id = r.id), '[]'::jsonb),
    'childcare_dept_contacts', coalesce((select jsonb_agg(to_jsonb(dc) order by dc.contacted_at)
        from incident_report_childcare_dept_contacts dc where dc.incident_report_id = r.id), '[]'::jsonb),
    'photos', coalesce((select jsonb_agg(to_jsonb(ph) order by ph.sort_order)
        from incident_report_photos ph where ph.incident_report_id = r.id), '[]'::jsonb)
  )
  into v
  from incident_reports r
  where r.id = p_id;
  if v is null then raise exception 'not found'; end if;
  return v;
end;
$$;
grant execute on function fetch_incident_report_detail(uuid) to authenticated, service_role;
