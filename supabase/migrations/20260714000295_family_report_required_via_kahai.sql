-- 295: 連絡帳提出必須の判定を「クラス基準 OR 加配期間中」に一本化(俊指示2026-08-24)。
-- 独自の「期間設定」(children.family_daily_report_required_from/until)は廃止し、加配期間に統合。
-- 加配期間中は 幼児(3-5歳)でも連絡帳提出が必須(かつ個人案も必要)。
-- 判定: 0-2歳児クラス=必須(クラス基準) / それ以外=加配期間が当日に有効なら必須。
-- ※ family_daily_report_required_from/until は今後不使用(列・旧RPCは残置)。

create or replace function is_family_daily_report_required(p_child_id uuid, p_business_date date)
returns boolean
language sql stable security definer set search_path = public
as $$
  select
    coalesce(
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
    )
    or exists (
      select 1 from child_kahai_periods k
      where k.child_id = p_child_id
        and k.start_date <= p_business_date
        and (k.end_date is null or k.end_date >= p_business_date)
    );
$$;
