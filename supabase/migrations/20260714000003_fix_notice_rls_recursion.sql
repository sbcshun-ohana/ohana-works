-- 8章 お知らせ: notices ⇄ notice_recipients のRLS相互参照によるinfinite recursion(42P17)を修正
--
-- 原因: notices_select_target が notice_recipients を直接SELECTし、
-- notice_recipients_select_self が notices を直接SELECTしていたため、
-- notices取得時にPostgreSQLが両ポリシーを循環的に評価してエラーになっていた。
-- my_employee_id()/manages_office() と同様にSECURITY DEFINER関数を介することで、
-- 関数内部のクエリはRLSを経由せず判定できるため、循環を断つ。

create or replace function is_notice_recipient(p_notice_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from notice_recipients
    where notice_id = p_notice_id and employee_id = my_employee_id()
  );
$$;

create or replace function is_notice_creator(p_notice_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from notices
    where id = p_notice_id and created_by = my_employee_id()
  );
$$;

drop policy if exists notices_select_target on notices;
create policy notices_select_target on notices
  for select using (
    category = '会社一斉'
    or created_by = my_employee_id()
    or (target_office_id is not null and manages_office(target_office_id))
    or (
      target_office_id is not null
      and target_office_id in (select home_office_id from employees where id = my_employee_id())
    )
    or (
      target_position_id is not null
      and target_position_id in (select position_id from employees where id = my_employee_id())
    )
    or is_notice_recipient(id)
  );

drop policy if exists notice_recipients_select_self on notice_recipients;
create policy notice_recipients_select_self on notice_recipients
  for select using (
    employee_id = my_employee_id()
    or is_notice_creator(notice_id)
  );
