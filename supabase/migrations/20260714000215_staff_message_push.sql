-- 215: 園内連絡 Phase 4 = プッシュ連携(設計書§8)。
-- create_staff_message(156) を再定義し、送信時点の宛先該当者(送信者本人を除く)へ
-- 既存 notifications outbox に target_employee_id 行を積む(新しい送信系統は作らない=§12)。
-- 宛先解決は is_staff_message_addressed_to(214適用後=facilityは管理職込み) に一元化。
-- band宛ては送信時点のシフトで解決するため、以後の差し替え分はプッシュされない(§6.3の明記済み非対称。
-- ログイン時のアラート/バッジで気づける)。
-- タイトル=「【園内連絡】○○さんから」、本文=先頭20字程度(§8: ロック画面に出しすぎない)。
-- ※適用前に pg_get_functiondef('create_staff_message(uuid,text,date,jsonb)'::regprocedure) を156と照合すること。
-- 冪等: create or replace のみ。

create or replace function create_staff_message(p_office_id uuid, p_body text, p_target_date date, p_targets jsonb)
returns uuid language plpgsql security definer set search_path = public
as $$
declare v_id uuid; v_t jsonb; v_type text; v_author_name text;
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  if coalesce(trim(p_body),'')='' then raise exception 'body required'; end if;
  if p_targets is null or jsonb_array_length(p_targets)=0 then raise exception 'target required'; end if;

  insert into staff_messages (office_id, author_employee_id, body, target_date)
  values (p_office_id, my_employee_id(), p_body, p_target_date) returning id into v_id;

  for v_t in select * from jsonb_array_elements(p_targets) loop
    v_type := v_t->>'type';
    if v_type in ('band','class') and p_target_date is null then
      raise exception 'target_date is required for band/class targets';
    end if;
    insert into staff_message_targets (message_id, target_type, employee_id, band_id, class_id)
    values (v_id, v_type,
      nullif(v_t->>'employee_id','')::uuid, nullif(v_t->>'band_id','')::uuid, nullif(v_t->>'class_id','')::uuid);
  end loop;

  -- 215(§8): 送信時点の宛先該当者(本人を除く)へプッシュ(outbox→毎分dispatcher)。
  select name into v_author_name from employees where id = my_employee_id();
  insert into notifications (notification_type, title, body, channels, target_employee_id, payload, status)
  select
    'staff_message',
    '【園内連絡】' || coalesce(v_author_name, '職員') || 'さんから',
    left(p_body, 20) || case when length(p_body) > 20 then '…' else '' end,
    array['push'],
    emp,
    jsonb_build_object('message_id', v_id::text, 'office_id', p_office_id::text),
    'pending'
  from office_accessible_employee_ids(p_office_id) emp
  where emp <> my_employee_id()
    and is_staff_message_addressed_to(v_id, emp);

  return v_id;
end;
$$;
