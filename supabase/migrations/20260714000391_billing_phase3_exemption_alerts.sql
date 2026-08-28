-- 391: 免除書類の確認待ちアラート(俊要望 2026-08-28)。
--   書類確認待ち(pending)・不備あり(deficient)の免除を、確認完了(confirmed)まで
--   園児マスタ上部のアラートとして統括に出し続ける(311未同意アラートと同型の画面内方式)。
--   最終防衛線はPhase7の請求承認前自動チェック(免除書類未確認で承認ブロック)に別途実装する。
--   権限: 統括のみ(免除=非課税世帯を示唆する機微情報・390と同方針)。

create or replace function fetch_pending_exemption_alerts(p_office_id uuid)
returns table (
  child_id uuid,
  child_name text,
  kind text,
  document_state text,
  document_fiscal_year int,
  start_month date
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_executive_director_or_admin() then raise exception 'not authorized'; end if;
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  if not is_billing_enabled_for_office(p_office_id) then raise exception 'feature disabled'; end if;

  return query
  select x.child_id, c.display_name, x.kind, x.document_state, x.document_fiscal_year, x.start_month
  from child_exemptions x
  join children c on c.id = x.child_id
  where c.office_id = p_office_id
    and c.enrollment_status <> '退園済み'
    and x.document_state in ('pending', 'deficient')
    and (x.end_month is null or x.end_month >= jst_current_month())
  order by x.document_state, x.start_month, c.display_name;  -- 'deficient'(不備) < 'pending' の辞書順=重い順に並ぶ
end;
$$;
grant execute on function fetch_pending_exemption_alerts(uuid) to authenticated, service_role;
revoke execute on function fetch_pending_exemption_alerts(uuid) from public, anon;
