-- 231: 診断書の提出依頼の重複ガード(俊指摘 2026-08-18・staging適用は俊実施)。
-- 依頼中(requested)が既にある園児への再依頼を拒否。UI側もボタンを非表示化(二重ガード)。
create or replace function create_allergy_diagnosis_request(p_child_id uuid, p_requested_at date default null)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_office_id uuid; v_id uuid;
begin
  select c.office_id into v_office_id from children c where c.id = p_child_id;
  if v_office_id is null then raise exception 'child not found'; end if;
  if not is_childcare_admin(v_office_id) then raise exception 'not authorized'; end if;
  if exists (
    select 1 from child_allergy_diagnoses
    where child_id = p_child_id and status = 'requested'
  ) then
    raise exception 'a requested diagnosis already exists';
  end if;
  insert into child_allergy_diagnoses (child_id, office_id, status, requested_at, created_by)
  values (p_child_id, v_office_id, 'requested', coalesce(p_requested_at, current_date), my_employee_id())
  returning id into v_id;
  return v_id;
end;
$$;
