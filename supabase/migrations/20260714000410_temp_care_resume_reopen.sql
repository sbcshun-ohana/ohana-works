-- 410: 一時預かり「再開」の重複エラー修正(俊報告 2026-08-31)。
--   408は再開時に新しい在籍を今日から挿入したが、休止で end_date=今日 に閉じた在籍と
--   境界日(今日)で期間が重複し child_class_enrollments_no_overlap に違反した。
--   → 再開は新規挿入せず「閉じた最新の在籍を再オープン(end_date=null)」に変更。重複しない。

create or replace function set_temp_care_active(p_child_id uuid, p_active boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_office uuid;
  v_kind text;
  v_status text;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
  v_fiscal int := case when extract(month from (now() at time zone 'Asia/Tokyo')::date) >= 4
                       then extract(year from (now() at time zone 'Asia/Tokyo')::date)::int
                       else extract(year from (now() at time zone 'Asia/Tokyo')::date)::int - 1 end;
  v_class uuid;
  v_latest uuid;
begin
  select office_id, child_kind, enrollment_status into v_office, v_kind, v_status
  from children where id = p_child_id;
  if v_office is null then raise exception 'not found'; end if;
  if v_kind <> 'temporary' then raise exception '一時預かり児のみ操作できます'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  if v_status = '退園済み' then raise exception '登録取消済みの児は操作できません'; end if;

  if p_active then
    -- 既に開いている在籍があれば何もしない
    if exists (select 1 from child_class_enrollments
               where child_id = p_child_id and effective_end_date is null) then
      return;
    end if;
    -- 閉じた最新の在籍を再オープン(end_date=null)。重複しないよう新規挿入はしない。
    select id into v_latest from child_class_enrollments
    where child_id = p_child_id
    order by effective_start_date desc, effective_end_date desc nulls last
    limit 1;
    if v_latest is not null then
      update child_class_enrollments set effective_end_date = null where id = v_latest;
    else
      -- 在籍履歴が全く無い場合のみ新規作成
      v_class := ensure_temp_care_class(v_office, v_fiscal);
      insert into child_class_enrollments (child_id, class_id, effective_start_date, assigned_by)
      values (p_child_id, v_class, v_today, my_employee_id());
    end if;
  else
    -- 休止: 開いている在籍を今日でクローズ(翌日以降ボード非表示)
    update child_class_enrollments set effective_end_date = v_today
    where child_id = p_child_id and effective_end_date is null;
  end if;
end;
$$;
