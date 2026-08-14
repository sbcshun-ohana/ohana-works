-- 216: ボードの感染症バッジに紙受領者・受領時刻を表示するためのRPC拡張(俊要望 2026-08-14:
-- 受け取りを押した職員の名前を履歴として確認できるように)。
-- fetch_board_infection_cases_for_office(206) に受領情報(最新の紙受領の受領者名・時刻)と
-- 電子提出日時を追加(末尾列追加のみ=既存クライアント互換)。
-- ※適用前に pg_get_functiondef('fetch_board_infection_cases_for_office(uuid)'::regprocedure) を206と照合。
--   戻り型変更のため drop→create→grant 再付与。冪等: drop if exists→create。

drop function if exists fetch_board_infection_cases_for_office(uuid);

create function fetch_board_infection_cases_for_office(p_office_id uuid)
returns table (
  child_id uuid,
  case_id uuid,
  status text,
  disease_name text,
  required_document text,
  document_state text,
  received_by_name text,
  received_at timestamptz,
  submitted_at timestamptz
)
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
  select
    ic.child_id, ic.id, ic.status, m.name, ic.required_document, ic.document_state,
    r.received_by_name, r.received_at, n.submitted_at
  from infection_cases ic
  left join infectious_disease_masters m on m.id = ic.disease_master_id
  left join lateral (
    select e.name as received_by_name, pdr.received_at
    from paper_document_receipts pdr
    left join employees e on e.id = pdr.received_by
    where pdr.case_id = ic.id
    order by pdr.received_at desc limit 1
  ) r on true
  left join lateral (
    select irn.submitted_at
    from infection_return_notices irn
    where irn.case_id = ic.id and irn.status = 'submitted'
    limit 1
  ) n on true
  where ic.office_id = p_office_id and ic.status <> 'closed'
  order by ic.created_at;
end;
$$;

grant execute on function fetch_board_infection_cases_for_office(uuid) to anon, authenticated, service_role;
