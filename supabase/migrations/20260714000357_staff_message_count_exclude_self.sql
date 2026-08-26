-- 357: 園内連絡「自分宛て未確認件数」から自分が送信したメッセージを除外(俊指示 2026-08-26)。
--   全職員宛て等の一斉連絡では送信者本人も宛先に含まれ、本人は「確認」しないため未確認としてカウントされていた
--   (=誤ってバナーが出る)。自分の発信は確認不要のため除外する。
create or replace function fetch_my_unacknowledged_staff_message_count(p_office_id uuid)
returns int language sql stable security definer set search_path = public
as $$
  select count(*)::int from staff_messages m
  where m.office_id = p_office_id and m.deleted_at is null
    and m.author_employee_id is distinct from my_employee_id()  -- 自分の発信は除外
    and is_staff_message_addressed_to(m.id, my_employee_id())
    and not exists (select 1 from staff_message_reads r
                    where r.message_id = m.id and r.employee_id = my_employee_id() and r.acknowledged_at is not null);
$$;
