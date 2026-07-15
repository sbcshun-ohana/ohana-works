-- allowance_mastersはRLS有効・直接ポリシー無し(デフォルト拒否)のため、
-- admin_web施設別手当UIの選択肢取得用に読み取りRPCを追加する。

create or replace function fetch_allowance_masters()
returns table (id uuid, name text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not is_labor_manager_plus() then
    raise exception 'not authorized';
  end if;

  return query select am.id, am.name from allowance_masters am order by am.name;
end;
$$;
