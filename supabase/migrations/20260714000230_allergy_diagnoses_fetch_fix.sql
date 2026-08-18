-- 230: fetch_child_allergy_diagnoses の列名衝突修正(227のバグ修正・staging適用済 2026-08-18)。
-- 関数内の unqualified な "id" が戻り値列 id と衝突し 42702 で毎回失敗していた。テーブル別名で修飾する。
create or replace function fetch_child_allergy_diagnoses(p_child_id uuid)
returns table (
  id uuid, status text, requested_at date, received_at date,
  doctor_name text, medical_institution text, diagnosis_content text,
  elimination_targets text[], effective_from date, effective_until date,
  renewal_deadline date, document_path text, release_note text, created_at timestamptz
)
language plpgsql stable security definer set search_path = public
as $$
declare v_office_id uuid;
begin
  select c.office_id into v_office_id from children c where c.id = p_child_id;
  if v_office_id is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office_id) then raise exception 'not authorized'; end if;
  return query
  select d.id, d.status, d.requested_at, d.received_at, d.doctor_name, d.medical_institution,
    d.diagnosis_content, d.elimination_targets, d.effective_from, d.effective_until,
    d.renewal_deadline, d.document_path, d.release_note, d.created_at
  from child_allergy_diagnoses d where d.child_id = p_child_id order by d.created_at desc;
end;
$$;
