-- 進級一括登録(bulk_promote_children)の重複ガード修正。
--
-- 不具合: 旧実装は「effective_end_date is null の行(現在在籍)」を無条件に
-- 重複チェックの対象外としていたため、同一条件で2回実行すると、1回目で作った
-- 新在籍行が2回目では「現在在籍」として扱われ、自分自身を除外してすり抜けて
-- しまう。結果として effective_start_date > effective_end_date という壊れた行と、
-- 同一クラス・同一開始日の重複行が作られていた。
--
-- 本マイグレーションはDBレベルの制約(1)とRPC側の判定強化(2)の二重で防止する。

-- =========================================================
-- 1) DBレベルの制約
--    適用前に既存データが違反していないことを別途確認すること
--    (確認SQLは本ファイルに含めない。違反があれば本マイグレーションは実行しない)
-- =========================================================

alter table child_class_enrollments
  add constraint child_class_enrollments_date_order_check
  check (effective_end_date is null or effective_end_date >= effective_start_date);

create extension if not exists btree_gist;

alter table child_class_enrollments
  add constraint child_class_enrollments_no_overlap
  exclude using gist (
    child_id with =,
    daterange(effective_start_date, coalesce(effective_end_date, 'infinity'::date), '[]') with &&
  );

-- =========================================================
-- 2) RPC修正
-- =========================================================

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
  v_current_start_date date;
  v_overlap_exists boolean;
  v_duplicate_exists boolean;
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

      -- child_id は戻り値のOUTパラメータ名と衝突するため、テーブル別名で明示的に修飾する
      -- (無修飾のままだと"column reference is ambiguous"で必ず失敗する。132番の既存バグ)
      select cce.id, cce.effective_start_date into v_current_enrollment_id, v_current_start_date
      from child_class_enrollments cce
      where cce.child_id = v_child_id and cce.effective_end_date is null;

      -- 現在在籍の開始日以前(同日含む)には進級できない。
      -- これにより「1回目で作った新在籍行」を2回目実行時に現在在籍として
      -- 扱ってしまうケースを確実にブロックする。
      if v_current_enrollment_id is not null and v_current_start_date >= p_start_date then
        child_id := v_child_id;
        success := false;
        message := '現在の在籍開始日より後の日付にしか進級できません';
        return next;
        continue;
      end if;

      select exists (
        select 1 from child_class_enrollments cce
        where cce.child_id = v_child_id
          and cce.class_id = p_destination_class_id
          and cce.effective_start_date = p_start_date
      ) into v_duplicate_exists;

      if v_duplicate_exists then
        child_id := v_child_id;
        success := false;
        message := '同じ開始日・進級先クラスの在籍記録が既に存在します';
        return next;
        continue;
      end if;

      -- 重複チェック: 現在在籍行(v_current_enrollment_id)だけは
      -- 「p_start_date - 1 で閉じた後」の期間で判定し、それ以外の行は
      -- 無条件除外にせず実際の期間で判定する。
      select exists (
        select 1 from child_class_enrollments cce
        where cce.child_id = v_child_id
          and cce.effective_start_date <= coalesce(p_end_date, 'infinity'::date)
          and (
            case
              when cce.id = v_current_enrollment_id then p_start_date - 1
              else coalesce(cce.effective_end_date, 'infinity'::date)
            end
          ) >= p_start_date
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
