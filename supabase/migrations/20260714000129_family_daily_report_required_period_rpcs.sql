-- is_family_daily_report_required()を「園児単位の適用期間」ベースの判定に変更する。
-- 対象日が個別期間内なら必須、期間外/未設定ならクラス既定にフォールバックする(従来と同じ優先順位)。
create or replace function is_family_daily_report_required(p_child_id uuid, p_business_date date)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select case
        when c.family_daily_report_required_from is not null
          and p_business_date >= c.family_daily_report_required_from
          and (c.family_daily_report_required_until is null or p_business_date <= c.family_daily_report_required_until)
        then true
        else null
      end
      from children c
      where c.id = p_child_id
    ),
    (
      select cc.family_daily_report_required
      from child_class_enrollments cce
      join childcare_classes cc on cc.id = cce.class_id
      where cce.child_id = p_child_id
        and cce.effective_start_date <= p_business_date
        and (cce.effective_end_date is null or cce.effective_end_date >= p_business_date)
      order by cce.effective_start_date desc
      limit 1
    ),
    true
  );
$$;

-- 旧ON/OFFトグル用RPC(boolean版)は適用期間モデルに置き換わるため廃止する。
drop function if exists set_family_daily_report_required_override(uuid, boolean);

-- 園児単位の連絡帳提出必須「適用期間」の設定。p_start_date=nullで解除(クラス既定に戻す)。
create or replace function set_family_daily_report_required_period(
  p_child_id uuid,
  p_start_date date,
  p_end_date date
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_office_id uuid;
begin
  if p_start_date is null and p_end_date is not null then
    raise exception 'end date requires a start date';
  end if;
  if p_end_date is not null and p_end_date < p_start_date then
    raise exception 'end date must be on or after start date';
  end if;

  select office_id into v_office_id from children where id = p_child_id;
  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not manages_childcare(v_office_id) then
    raise exception 'not authorized';
  end if;

  update children
  set family_daily_report_required_from = p_start_date,
      family_daily_report_required_until = p_end_date
  where id = p_child_id;
end;
$$;
