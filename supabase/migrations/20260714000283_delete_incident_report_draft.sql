-- 283: ヒヤリハット・事故報告の「下書き」を削除できるようにする。
-- 俊指示(2026-08-24): 一度下書きを作ると消す入り口がない。下書き(差し戻し含む=status='draft')のみ削除可。
-- 権限=作成者本人 or 主任以上(作成/申請と同じゲート)。子テーブルは全て on delete cascade(246)。
-- 申請中/承認済は削除不可(差し戻し・承認取消・クローズの既存フローを使う)。

create or replace function delete_incident_report(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_status text; v_office uuid; v_created_by uuid;
begin
  select status, office_id, created_by into v_status, v_office, v_created_by
  from incident_reports where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not (v_created_by = my_employee_id() or manages_childcare(v_office)) then
    raise exception 'not authorized';
  end if;
  if v_status <> 'draft' then
    raise exception 'only draft can be deleted';
  end if;
  delete from incident_reports where id = p_id;  -- 子コレクションは on delete cascade
end $$;
grant execute on function delete_incident_report(uuid) to authenticated, service_role;
