-- 293: 加配期間の重複を禁止。俊指示(2026-08-24): 1人につき同じ期間が重複して適用されないように。
-- 追加・編集時に既存期間と重なる場合はエラー。end_date null(継続中)は無期限として重なり判定。

create or replace function add_child_kahai_period(p_child_id uuid, p_start date, p_end date, p_note text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_id uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  if p_start is null then raise exception '開始日を入力してください'; end if;
  if p_end is not null and p_end < p_start then raise exception '終了日は開始日以降にしてください'; end if;
  if exists (select 1 from child_kahai_periods k
             where k.child_id = p_child_id
               and k.start_date <= coalesce(p_end, 'infinity'::date)
               and p_start <= coalesce(k.end_date, 'infinity'::date)) then
    raise exception '加配期間が既存の期間と重複しています。重複しない期間で登録してください';
  end if;
  insert into child_kahai_periods (child_id, office_id, start_date, end_date, note, created_by)
  values (p_child_id, v_office, p_start, p_end, p_note, my_employee_id()) returning id into v_id;
  return v_id;
end $$;
grant execute on function add_child_kahai_period(uuid, date, date, text) to authenticated, service_role;

create or replace function update_child_kahai_period(p_id uuid, p_start date, p_end date, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_child uuid;
begin
  select office_id, child_id into v_office, v_child from child_kahai_periods where id = p_id;
  if v_office is null then raise exception 'not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  if p_start is null then raise exception '開始日を入力してください'; end if;
  if p_end is not null and p_end < p_start then raise exception '終了日は開始日以降にしてください'; end if;
  if exists (select 1 from child_kahai_periods k
             where k.child_id = v_child and k.id <> p_id
               and k.start_date <= coalesce(p_end, 'infinity'::date)
               and p_start <= coalesce(k.end_date, 'infinity'::date)) then
    raise exception '加配期間が他の期間と重複しています';
  end if;
  update child_kahai_periods set start_date = p_start, end_date = p_end, note = p_note where id = p_id;
end $$;
grant execute on function update_child_kahai_period(uuid, date, date, text) to authenticated, service_role;
