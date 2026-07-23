-- 保護者アプリ: 園児の所属施設名をヘッダー表示するためのRPC。
-- offices自体のRLSは職員限定(offices_select_authenticated)のため保護者には開放せず、
-- 園児IDに紐づく施設名のみを返す専用RPCで最小限の情報だけ公開する。
create or replace function fetch_my_children_office_names()
returns table (child_id uuid, office_name text)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, o.name
  from guardian_child_links gcl
  join children c on c.id = gcl.child_id
  join offices o on o.id = c.office_id
  where gcl.guardian_id = my_guardian_id();
$$;
