-- 園児マスタ: 翌年度への進級一括登録。
-- 現在の在籍(effective_end_date is null)があれば新開始日の前日で閉じ、進級先クラスへの
-- 新しい在籍レコードを作成する。事前登録運用のため、実行時点ではまだ新期間が始まっていなくてもよい。
-- 園児ごとに在籍期間の重複チェックを行い、重複がある園児は理由付きでスキップする(バッチ全体は失敗させない)。
create or replace function bulk_promote_children(
  p_child_ids uuid[],
  p_destination_class_id uuid,
  p_start_date date,
  p_end_date date
)
returns table (child_id uuid, success boolean, message text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_office_id uuid;
  v_child_id uuid;
  v_child_office_id uuid;
  v_current_enrollment_id uuid;
  v_overlap_exists boolean;
begin
  if p_end_date is not null and p_end_date < p_start_date then
    raise exception 'end date must be on or after start date';
  end if;

  select office_id into v_office_id from childcare_classes where id = p_destination_class_id;
  if v_office_id is null then
    raise exception 'destination class not found';
  end if;
  if not manages_childcare(v_office_id) then
    raise exception 'not authorized';
  end if;

  foreach v_child_id in array p_child_ids loop
    begin
      select office_id into v_child_office_id from children where id = v_child_id;
      if v_child_office_id is null then
        child_id := v_child_id;
        success := false;
        message := '園児が見つかりません';
        return next;
        continue;
      end if;
      if v_child_office_id <> v_office_id then
        child_id := v_child_id;
        success := false;
        message := '進級先クラスと施設が一致しません';
        return next;
        continue;
      end if;

      select id into v_current_enrollment_id
      from child_class_enrollments
      where child_id = v_child_id and effective_end_date is null;

      select exists (
        select 1 from child_class_enrollments cce
        where cce.child_id = v_child_id
          and (v_current_enrollment_id is null or cce.id <> v_current_enrollment_id)
          and cce.effective_start_date <= coalesce(p_end_date, 'infinity'::date)
          and coalesce(cce.effective_end_date, 'infinity'::date) >= p_start_date
      ) into v_overlap_exists;

      if v_overlap_exists then
        child_id := v_child_id;
        success := false;
        message := '既に重複する在籍期間があるためスキップしました';
        return next;
        continue;
      end if;

      if v_current_enrollment_id is not null then
        update child_class_enrollments
        set effective_end_date = p_start_date - 1
        where id = v_current_enrollment_id;
      end if;

      insert into child_class_enrollments (child_id, class_id, effective_start_date, effective_end_date)
      values (v_child_id, p_destination_class_id, p_start_date, p_end_date);

      child_id := v_child_id;
      success := true;
      message := '登録しました';
      return next;
    exception when others then
      child_id := v_child_id;
      success := false;
      message := sqlerrm;
      return next;
    end;
  end loop;
end;
$$;
