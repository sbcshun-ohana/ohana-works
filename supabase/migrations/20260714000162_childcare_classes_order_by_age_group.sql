-- Phase 2 §2.1: クラス並び順を「年齢区分順」に統一(2026-08-03 俊確定)。
-- fetch_childcare_classes の返却順を class_name 単独から age_group→class_name に変更する。
-- フロント側(admin_web / Ohana Kids)は独自ソートせず、この返却順にそのまま乗る方針。
-- 返却列は不変のため create or replace で置換可能(型変更なし・42P13は発生しない)。
--
-- 注: age_group は自由記述テキスト(例: '0-1歳' / '3歳児' / '4-5歳')だが、
-- 先頭の年齢数字が照合順序を支配するため施設内では実質的に年齢区分順になる。
-- 将来、先頭が数字でない age_group 表記を導入する場合はこの前提を再確認すること。

create or replace function fetch_childcare_classes(p_office_id uuid)
returns table (class_id uuid, class_name text, age_group text, school_year int, family_daily_report_required boolean)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not has_childcare_office_access(p_office_id) then
    raise exception 'not authorized';
  end if;

  return query
  select cc.id, cc.class_name, cc.age_group, cc.school_year, cc.family_daily_report_required
  from childcare_classes cc
  where cc.office_id = p_office_id and cc.is_active and has_childcare_class_access(cc.id)
  order by cc.age_group, cc.class_name;
end;
$$;
