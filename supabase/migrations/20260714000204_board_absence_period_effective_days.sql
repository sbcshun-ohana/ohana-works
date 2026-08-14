-- 204: 欠席期間バッジを「実際に欠席のままの日」から算出する(俊指摘 2026-08-14)。
--
-- 経緯:
--   198(2026-08-13俊確定)では「バッジは申請ベース。当日を手動で出席へ戻しても欠席予定を返す」
--   としていたが、実運用で矛盾が発生: 8/14を出席へ戻した後、8/14表示では(クライアント読み替えで)
--   「8/15〜8/16」、8/15表示では申請どおり「8/14〜8/16」となり、同一承認の期間表示が日によって
--   食い違った。→ 2026-08-14俊確定でこの決定を更新し、期間の始点・終点をサーバー側で
--   child_daily_attendance の実欠席日(is_absent=true)から導出する。
--
-- 新仕様:
--   - 対象申請の選び方(distinct on・最も先まで続く1件・在籍クリップ・対象営業日が申請期間内)は198のまま。
--   - 返す期間 = クリップ後期間内で is_absent=true が残っている日の min〜max。
--     (197の承認が期間の各日に行を書くため、未来日も含め実欠席日はここから判定できる)
--   - 全日が出席へ戻された場合は行を返さない(バッジ非表示)。
--   - 対象営業日の行が出席へ戻っていても、申請期間内なら予告として返す
--     (当日を表示から除くのはクライアント側の既存読み替えが担当)。
--
-- 権限・シグネチャ・戻り型は198と同一(create or replace のみ・drop不要・grantは既存ACL維持)。

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
  select w.cid, a.eff_start, a.eff_end, w.kind
  from (
    select distinct on (c.id)
      c.id as cid,
      greatest(pr.target_date, c.enrollment_date) as clip_start,
      case
        when c.withdrawal_date is not null
          then least(coalesce(pr.end_date, pr.target_date), c.withdrawal_date)
        else coalesce(pr.end_date, pr.target_date)
      end as clip_end,
      pr.absence_kind as kind
    from parent_requests pr
    join children c on c.id = pr.child_id
    where c.office_id = p_office_id
      and pr.request_type = 'absence'
      and pr.status = 'approved'
      and pr.absence_kind is not null
      -- 在籍クリップ後の期間が対象営業日を含むこと(198と同一)
      and greatest(pr.target_date, c.enrollment_date) <= p_business_date
      and (case
             when c.withdrawal_date is not null
               then least(coalesce(pr.end_date, pr.target_date), c.withdrawal_date)
             else coalesce(pr.end_date, pr.target_date)
           end) >= p_business_date
    order by c.id, coalesce(pr.end_date, pr.target_date) desc
  ) w
  -- 204: 実欠席日(is_absent=true が残っている日)の範囲へ読み替え。全日戻し済みなら行ごと除外。
  join lateral (
    select min(cda.business_date) as eff_start, max(cda.business_date) as eff_end
    from child_daily_attendance cda
    where cda.child_id = w.cid
      and cda.business_date between w.clip_start and w.clip_end
      and cda.is_absent = true
  ) a on a.eff_start is not null;
end;
$$;
