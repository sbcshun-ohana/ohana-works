-- 345: 厨房ビューを施設×行区分(クラス/給食段階)×食事区分で一覧するための横断RPC(俊指示 2026-08-26)。
--   従来の fetch_meal_slot_crossoffice(施設合計)では0歳の後期/完了期/幼児食やクラス別が潰れるため、
--   fetch_meal_board(単一施設の行×区分)を複数施設に拡張したもの。meal_row_definitions の行を施設別に返す。
create or replace function fetch_meal_board_crossoffice(p_office_ids uuid[], p_business_date date)
returns table (
  office_id uuid, office_name text, office_code text,
  row_key text, row_label text, row_type text, sort_order int,
  meal_slot text, child_count int, staff_count int
)
language plpgsql stable security definer set search_path = public as $$
declare v_oid uuid;
begin
  foreach v_oid in array p_office_ids loop
    if not has_childcare_office_access(v_oid) then raise exception 'not authorized for office %', v_oid; end if;
  end loop;
  return query
    select o.id, o.name, o.office_code, rd.row_key, rd.row_label, rd.row_type, rd.sort_order,
           mr.meal_slot, mr.child_count, mr.staff_count
    from offices o
    join meal_row_definitions rd on rd.office_id = o.id and rd.is_active
    join meal_count_rows mr on mr.office_id = rd.office_id and mr.row_key = rd.row_key and mr.business_date = p_business_date
    where o.id = any(p_office_ids)
    order by o.office_code, rd.sort_order,
      case mr.meal_slot when 'am_snack' then 1 when 'lunch' then 2 else 3 end;
end $$;
grant execute on function fetch_meal_board_crossoffice(uuid[], date) to authenticated, service_role;
