-- P0: イベント駆動プッシュ通知の自動化(2/4: 申請結果)。
--
-- requests(有給/欠勤/遅刻早退/情報変更)の承認・却下は、有給と情報変更のみ専用RPC
-- (approve_paid_leave_request/approve_info_change_request)を経由するが、欠勤・遅刻早退の
-- 承認、および全種別の却下は requests_update_managers ポリシー経由の直接UPDATEのみで行われ
-- 専用RPCが存在しない(20260714000005のコメント参照)。そのため通知はRPC個別に埋め込むのではなく
-- requestsテーブルのAFTER UPDATEトリガーとして実装し、経路によらず一律に発火させる。

create or replace function notify_request_decision()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type_label text;
  v_title text;
  v_body text;
begin
  if old.status <> 'pending' or new.status not in ('approved', 'rejected') then
    return new;
  end if;

  v_type_label := case new.request_type
    when 'paid_leave' then '有給休暇申請'
    when 'absence' then '欠勤連絡'
    when 'tardiness_early_leave' then '遅刻早退連絡'
    when 'info_change' then '情報変更申請'
  end;

  v_title := case new.status
    when 'approved' then v_type_label || 'が承認されました'
    else v_type_label || 'が却下されました'
  end;

  v_body := to_char(new.target_date, 'yyyy年mm月dd日') || 'の' || v_type_label
    || case when new.decision_reason is not null and length(trim(new.decision_reason)) > 0
         then '(' || new.decision_reason || ')' else '' end;

  insert into notifications (
    notification_type, title, body, channels, target_employee_id, payload, status
  ) values (
    'request_decision', v_title, v_body, array['fcm', 'in_app'], new.employee_id,
    jsonb_build_object('request_id', new.id, 'request_type', new.request_type, 'status', new.status),
    'pending'
  );

  return new;
end;
$$;

create trigger trg_requests_notify_decision
  after update on requests
  for each row execute function notify_request_decision();
