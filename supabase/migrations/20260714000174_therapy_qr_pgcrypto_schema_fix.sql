-- 173 修正: issue_therapy_qr の gen_random_bytes/digest(pgcrypto)は extensions スキーマにあり、
-- set search_path = public では解決できない(42883)。schema 修飾に直す。
-- token_hash は hex sha256(EF resolve-therapy-qr の sha256Hex と一致させる)。

create or replace function issue_therapy_qr(p_child_id uuid, p_provider_id uuid)
returns table (qr_id uuid, token text)
language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_token text; v_hash text; v_id uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;

  update therapy_outing_qr_codes set revoked_at = now()
  where child_id = p_child_id and provider_id = p_provider_id and revoked_at is null;

  v_token := encode(extensions.gen_random_bytes(24), 'hex');
  v_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');
  insert into therapy_outing_qr_codes(child_id, provider_id, token_hash, issued_by)
  values (p_child_id, p_provider_id, v_hash, my_employee_id())
  returning id into v_id;

  qr_id := v_id; token := v_token; return next;
end; $$;
