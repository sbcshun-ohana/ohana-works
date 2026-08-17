-- 223: 園児の個別クラス変更+在籍履歴RPC(俊指示 2026-08-17)。
-- これまでクラスは 新規登録/正式入園/進級一括 でのみ設定可能だった。年度途中の転クラス・誤登録修正用に
-- 個別変更を追加する。在籍履歴(child_class_enrollments)は閉じるだけで削除しない=進級・転クラスの履歴が残る。
-- 1) change_child_class(主任以上): 変更日前日で現行在籍を閉じ、新在籍を開始。変更日以降に開始予定の行は置き換え。
-- 2) fetch_child_class_history(全職員): クラス名つき在籍履歴(台帳・クラス変更モーダルの履歴表示用)。
-- 冪等: create or replace のみ。

create or replace function change_child_class(p_child_id uuid, p_class_id uuid, p_effective_date date)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_class_office_id uuid;
begin
  select office_id into v_office_id from children where id = p_child_id;
  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not manages_childcare(v_office_id) then
    raise exception 'not authorized';
  end if;
  if p_class_id is null or p_effective_date is null then
    raise exception 'class and effective date required';
  end if;
  select office_id into v_class_office_id from childcare_classes where id = p_class_id;
  if v_class_office_id is null or v_class_office_id <> v_office_id then
    raise exception 'class does not belong to this office';
  end if;

  -- 同じクラスに変更日時点で在籍中なら何もしない(誤操作防止)
  if exists (
    select 1 from child_class_enrollments
    where child_id = p_child_id and class_id = p_class_id
      and effective_start_date <= p_effective_date
      and (effective_end_date is null or effective_end_date >= p_effective_date)
  ) then
    raise exception 'child is already in this class on the effective date';
  end if;

  -- 変更日以降に開始する予約済み在籍は置き換え(履歴にならない未来の行のみ削除)
  delete from child_class_enrollments
  where child_id = p_child_id and effective_start_date >= p_effective_date;

  -- 現行(変更日をまたぐ)在籍を変更日前日で閉じる=履歴として残る
  update child_class_enrollments
  set effective_end_date = p_effective_date - 1
  where child_id = p_child_id
    and effective_start_date < p_effective_date
    and (effective_end_date is null or effective_end_date >= p_effective_date);

  insert into child_class_enrollments (child_id, class_id, effective_start_date, effective_end_date, assigned_by)
  values (p_child_id, p_class_id, p_effective_date, null, my_employee_id());
end;
$$;

create or replace function fetch_child_class_history(p_child_id uuid)
returns table (
  class_id uuid,
  class_name text,
  effective_start_date date,
  effective_end_date date
)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_office_id uuid;
begin
  select office_id into v_office_id from children where id = p_child_id;
  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  return query
  select cc.id, cc.class_name, cce.effective_start_date, cce.effective_end_date
  from child_class_enrollments cce
  join childcare_classes cc on cc.id = cce.class_id
  where cce.child_id = p_child_id
  order by cce.effective_start_date;
end;
$$;
