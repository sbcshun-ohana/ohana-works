-- Phase 3(支援保育事業): 実機確認で判明した「candidate not found」バグの修正。
--
-- 原因: fetch_support_childcare_applications がcandidate_id(support_childcare_candidates.id)
-- を戻り値に含めていなかったため、admin_webの「申請作成」ボタンがやむを得ずchild_idを
-- 代用してcreate_support_childcare_application(p_candidate_id)へ渡していた。
-- candidate_idとchild_idは別テーブルの別カラムで値が一致しないため、常に
-- 「candidate not found」で失敗していた(migration 142の項目修正とは無関係の、
-- UI実装当初からの既存バグ)。
-- 対応: RPCの戻り値にcandidate_idを追加し、admin_web側もそれを使うよう修正する。

drop function if exists fetch_support_childcare_applications(uuid);

create or replace function fetch_support_childcare_applications(p_program_office_id uuid)
returns table (
  candidate_id uuid, application_id uuid, child_id uuid, child_name text, candidacy_status text,
  status text, author_name text, approver_name text, finalized_at timestamptz
)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_office_id uuid;
begin
  select po.office_id into v_office_id from support_childcare_program_offices po where po.id = p_program_office_id;
  if v_office_id is null then
    raise exception 'program office not found';
  end if;
  if not (has_childcare_office_access(v_office_id) or is_support_childcare_office_approver(v_office_id)) then
    raise exception 'not authorized';
  end if;

  return query
  select
    cand.id, a.id, cand.child_id, ch.display_name, cand.candidacy_status,
    a.status, author.name, approver.name, a.finalized_at
  from support_childcare_candidates cand
  join children ch on ch.id = cand.child_id
  left join support_childcare_applications a on a.candidate_id = cand.id
  left join employees author on author.id = a.author_id
  left join employees approver on approver.id = a.approver_id
  where cand.program_office_id = p_program_office_id
  order by ch.display_name;
end;
$$;
