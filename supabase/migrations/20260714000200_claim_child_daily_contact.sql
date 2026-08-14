-- 200: 連絡帳の「自分を担当にする」(claim_child_daily_contact)(俊指示 2026-08-13)。
--
-- 背景: 連絡帳の担当は 193 で「下書き作成時に担任割当が無ければ作成者を担当にフォールバック」
--   済みだが、193以前に作られた assignee=NULL の行を職員が引き取る手段が無い
--   (RLS child_daily_contacts_update_assignee_content は assignee本人のみ更新可のため、
--    NULL→自分 への更新は一般職員には不可能)。
-- クラス活動の claim_class_activity(062) と同一の流儀の security definer RPC を新設する。
--
-- 認可:
--   - 施設アクセス(has_childcare_office_access)必須。
--   - 未割当、または既に自分が担当の場合のみ可(他人の担当は奪えない。付け替えは既存の
--     管理者経路=直接更新ポリシーに委ねる)。
--   - status は draft/rejected のみ(申請中/公開済みの連絡帳の担当引き取りは編集権限を
--     生まない無意味な操作のため不可)。
-- 冪等: create or replace のみ(新規関数・スキーマ変更なし)。

create or replace function claim_child_daily_contact(p_contact_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_contact child_daily_contacts%rowtype;
  v_office uuid;
begin
  select * into v_contact from child_daily_contacts where id = p_contact_id for update;
  if v_contact.id is null then
    raise exception 'contact not found';
  end if;

  select office_id into v_office from children where id = v_contact.child_id;
  if not has_childcare_office_access(v_office) then
    raise exception 'not authorized';
  end if;

  if v_contact.assignee_employee_id is distinct from my_employee_id()
     and v_contact.assignee_employee_id is not null then
    raise exception 'already assigned to another employee';
  end if;

  if v_contact.status not in ('draft', 'rejected') then
    raise exception 'contact is % and cannot be claimed', v_contact.status;
  end if;

  update child_daily_contacts set assignee_employee_id = my_employee_id() where id = p_contact_id;
end;
$$;

grant execute on function claim_child_daily_contact(uuid) to anon, authenticated, service_role;
