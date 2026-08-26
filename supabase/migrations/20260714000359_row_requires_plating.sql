-- 359: 盛り付け配膳が必要な行(クラス)にフラグを立てる(俊指示 2026-08-26)。
--   盛り付け配膳(職員分もクラスへ盛り付けて配膳)が必要なのは 大和オハナ保育園の はな/そら/かぜ(0・1・2歳)のみ。
--   それ以外(大和 つき/ほし/にじ、BABY MAHALO、Mahalo Station、ハレレア)は自分で盛り付け=職員のクラス入力なし。
--   → 発注数ボードで「盛り付けクラスの昼食/午後おやつ」だけ職員数を入力できるようにする(fetch_meal_board が返す)。
alter table meal_row_definitions add column if not exists requires_plating boolean not null default false;

-- 大和(office_code='O')の 0・1・2歳クラス行に true(はな/そら/かぜ)。後期/完了期/幼児食の各行も対象クラスなのでtrue。
update meal_row_definitions rd
set requires_plating = true
from childcare_classes c, offices o
where rd.class_id = c.id and c.office_id = o.id and o.office_code = 'O'
  and coalesce(substring(c.age_group from '(\d)歳')::int, 9) <= 2
  and rd.requires_plating = false;

-- fetch_meal_board に requires_plating を追加(戻り値変更のため drop→再作成)。
drop function if exists fetch_meal_board(uuid, date);
create function fetch_meal_board(p_office_id uuid, p_business_date date)
returns table (
  row_key text, row_label text, row_type text, sort_order int, meal_slot text,
  child_count int, staff_count int, is_confirmed boolean, confirmed_by_name text, requires_plating boolean
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not is_childcare_staff() then raise exception 'not authorized'; end if;
  return query
  select rd.row_key, rd.row_label, rd.row_type, rd.sort_order, mr.meal_slot,
         mr.child_count, mr.staff_count, mr.is_confirmed, e.name, rd.requires_plating
  from meal_row_definitions rd
  join meal_count_rows mr on mr.office_id = rd.office_id and mr.row_key = rd.row_key and mr.business_date = p_business_date
  left join employees e on e.id = mr.confirmed_by
  where rd.office_id = p_office_id and rd.is_active
  order by rd.sort_order,
    case mr.meal_slot when 'am_snack' then 1 when 'lunch' then 2 else 3 end;
end;
$$;
grant execute on function fetch_meal_board(uuid, date) to authenticated, service_role;
