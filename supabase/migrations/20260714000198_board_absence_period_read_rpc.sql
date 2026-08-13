-- 198: デイリーボードの「欠席期間表示」用 読み取りRPC(新設)。
--
-- 目的:
--   承認済みの欠席申請(parent_requests, request_type='absence' かつ absence_kind 非NULL)のうち、
--   対象営業日が期間内のものを園児あたり1件返す。デイリーボードの各行に
--   「MM/DD〜MM/DD 欠席予定(病欠/都合欠)」(単日は「MM/DD 欠席予定(...)」)を出すための付加情報。
--
-- 設計判断(俊確定 2026-08-13):
--   - fetch_daily_board_for_office(172) の drop+recreate は避ける(列追加の重さ・186前例リスク)。
--     → 別RPC + クライアント結合(child_id)で実現。ボードRPCは一切変更しない。
--   - 抽出は「対象営業日が期間内」のみ(未来の欠席の予告表示は今回スコープ外)。
--   - 手動欠席(申請なし=set_child_attendance_status / child_daily_attendance 直接)は対象外(期間概念なし)。
--   - 表示範囲は承認処理(197)の在籍クリップと一致させる:
--       start = greatest(target_date, children.enrollment_date)
--       end   = least(coalesce(end_date, target_date), children.withdrawal_date)  -- withdrawal_date が NULL なら未クリップ
--     クリップ後の範囲が対象営業日を含む行のみ返す(在籍外の日は返さない)。
--   - 同一児に期間の重なる承認が複数ある場合は、最も先まで続く1件のみ返す
--     (distinct on (child_id) ... order by child_id, coalesce(end_date, target_date) desc)。
--     単日承認(end_date=NULL)が期間承認に勝つ desc既定NULLS FIRST取り違えを coalesce で回避。
--   - バッジは申請ベース。承認後に職員が当日を手動で出席へ戻しても本RPCは「欠席予定」を返す(俊確定)。
--     → 当日の child_daily_attendance には結合しない。
--
-- 権限: gate = has_childcare_office_access(p_office_id)(ボードRPC 172 と同一)。
-- grant: 172のボードRPCと同じ実効権限(20260713000001 の default privileges = anon/authenticated/service_role)を明示付与。
-- 冪等: 新規関数のため drop/照合不要。create or replace で完結(返り型変更の 42P13 は発生しない)。

create or replace function fetch_board_absence_periods_for_office(
  p_office_id uuid,
  p_business_date date
)
returns table (
  child_id uuid,
  start_date date,
  end_date date,
  absence_kind text
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
  select distinct on (c.id)
    c.id as child_id,
    greatest(pr.target_date, c.enrollment_date) as start_date,
    case
      when c.withdrawal_date is not null
        then least(coalesce(pr.end_date, pr.target_date), c.withdrawal_date)
      else coalesce(pr.end_date, pr.target_date)
    end as end_date,
    pr.absence_kind
  from parent_requests pr
  join children c on c.id = pr.child_id
  where c.office_id = p_office_id
    and pr.request_type = 'absence'
    and pr.status = 'approved'
    and pr.absence_kind is not null
    -- 在籍クリップ後の期間が対象営業日を含むこと
    and greatest(pr.target_date, c.enrollment_date) <= p_business_date
    and (case
           when c.withdrawal_date is not null
             then least(coalesce(pr.end_date, pr.target_date), c.withdrawal_date)
           else coalesce(pr.end_date, pr.target_date)
         end) >= p_business_date
  -- 「最も先まで続く1件」を選ぶ。end_date はエイリアスに依存せず生の期間終端で並べる
  -- (coalesce で単日承認 end_date=NULL を target_date に落とし、desc既定 NULLS FIRST の取り違えを防ぐ)。
  order by c.id, coalesce(pr.end_date, pr.target_date) desc;
end;
$$;

grant execute on function fetch_board_absence_periods_for_office(uuid, date) to anon, authenticated, service_role;
