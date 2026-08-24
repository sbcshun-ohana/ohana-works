-- 313: 重要事項説明書の公開時に、在籍児の保護者へ通知(in_app+push)して同意を促す。同意必須の運用強化。
-- dispatch-pending-notifications が target_guardian_id を push_device_tokens と突合して送信する。
create or replace function save_important_matters_document(p_office_id uuid, p_fiscal_year int, p_title text, p_storage_path text, p_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_ver int; v_id uuid;
begin
  if not is_childcare_admin(p_office_id) then raise exception 'not authorized'; end if;
  select coalesce(max(version), 0) + 1 into v_ver from important_matters_documents where office_id = p_office_id and fiscal_year = p_fiscal_year;
  insert into important_matters_documents (office_id, fiscal_year, title, storage_path, version, is_published, published_by, note)
    values (p_office_id, p_fiscal_year, p_title, p_storage_path, v_ver, true, my_employee_id(), nullif(trim(coalesce(p_note,'')),''))
    returning id into v_id;

  -- 在籍児の保護者(重複除去)へ確認・同意のお願い通知。
  insert into notifications (notification_type, title, body, channels, target_guardian_id, payload, status)
  select 'important_matters_published', '重要事項説明書のご確認・ご同意のお願い',
         p_title || 'が公開されました。アプリでご確認のうえ、ご同意をお願いします。',
         array['in_app', 'push'], g.gid, jsonb_build_object('document_id', v_id::text), 'pending'
  from (
    select distinct gcl.guardian_id as gid
    from guardian_child_links gcl
    join children ch on ch.id = gcl.child_id
    where ch.office_id = p_office_id and ch.enrollment_status = '在籍中'
  ) g;

  return v_id;
end $$;
grant execute on function save_important_matters_document(uuid, int, text, text, text) to authenticated, service_role;
