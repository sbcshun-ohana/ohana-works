-- 要件2(ログイン中アカウントの常時表示)用の読み取りRPC。
-- employee_roles には本人自己参照のRLSポリシーが無い(deny-all)ため、ログイン中職員が
-- 自分の役職を直接読めない。氏名は employees_select_self で読めるが、役職(employee_roles)は
-- 読めないため、氏名＋最上位役職コードを返す SECURITY DEFINER の薄い読み取り関数を追加する。
-- (役職の日本語表示名はフロントの定数1箇所で管理するため、ここでは role_code のみ返す。)
--
-- 最上位役職 = roles.sort_order 昇順の先頭(sort_order が小さいほど上位)。役職行が無い職員
-- (一般職員は役職行を持たない運用)は role_code = null を返す。表示側で「一般職員」等にフォールバックする。
--
-- volatility(§3.2b): log_sensitive_access を呼ばず、読み取りのみのため stable でよい。
create or replace function fetch_my_session_identity()
returns table (employee_id uuid, name text, role_code text)
language sql
stable
security definer
set search_path = public
as $$
  select
    e.id,
    e.name,
    (
      select r.code
      from employee_roles er
      join roles r on r.id = er.role_id
      where er.employee_id = e.id
      order by r.sort_order
      limit 1
    ) as role_code
  from employees e
  where e.id = my_employee_id();
$$;
