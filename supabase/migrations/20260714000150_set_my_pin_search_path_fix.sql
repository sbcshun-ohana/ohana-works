-- 149 の set_my_pin バグ修正(拒否側E2E検証で発覚)。
-- pgcrypto の crypt/gen_salt は Supabase では extensions スキーマにあり、
-- search_path=public では解決できず「function gen_salt(unknown) does not exist」で失敗する。
-- search_path に extensions を追加する(挙動・引数・戻り値は変更なし)。
create or replace function set_my_pin(p_pin text)
returns void
language plpgsql security definer set search_path = public, extensions
as $$
begin
  if my_employee_id() is null then
    raise exception 'not authenticated';
  end if;
  if p_pin !~ '^[0-9]{6}$' then
    raise exception 'PINは6桁の数字で入力してください';
  end if;
  if is_weak_pin(p_pin) then
    raise exception '推測されやすいPIN(全桁同じ・連番)は使用できません。別の6桁を設定してください';
  end if;
  insert into staff_pins (employee_id, pin_hash, failed_attempts, locked_until, updated_at)
  values (my_employee_id(), crypt(p_pin, gen_salt('bf')), 0, null, now())
  on conflict (employee_id) do update
    set pin_hash = excluded.pin_hash, failed_attempts = 0, locked_until = null, updated_at = now();
end;
$$;
