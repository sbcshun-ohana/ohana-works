-- 要件3(職員ピッカー+PIN簡易ログイン)のサーバ側DB。
-- 設計: docs/権限・セッション管理_設計案_2026-07-30.md §4。
--
-- 原則:
--  - PINは**ハッシュのみ保存**(pgcrypto bcrypt)。平文・ログ出力禁止。
--  - staff_pins はクライアントから一切アクセス不可(RLS有効・ポリシー無し=deny-all)。
--    pin_hash はどの経路でもクライアントへ返さない。
--  - ピッカー表示・PIN検証・セッション発行は Edge Function(service role)がサーバ側で行う
--    (端末ID・施設・職員・PINを検証してから発行)。クライアントでPIN照合しない。
--  - 本人のPIN設定/変更・管理者のリセットは、認証済みで呼ぶ SECURITY DEFINER RPC。
--    いずれも pin_hash を返さない。
--
-- volatility(§3.2b): set/reset は書き込み=volatile(既定)。fetch_staff_pin_status は
--  読み取り=stable。いずれも log_sensitive_access を呼ばない。

create table staff_pins (
  employee_id uuid primary key references employees(id) on delete cascade,
  pin_hash text not null,
  failed_attempts int not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);
create trigger trg_staff_pins_updated_at before update on staff_pins
  for each row execute function set_updated_at();
-- 監査(設定・リセット・ロックの追跡)。※ log_event_change は before/after を残すが、
--  pin_hash も after_data に含まれ得るため event_logs 自体のアクセスは既存どおり厳格に扱う。
create trigger trg_audit_staff_pins after insert or update or delete on staff_pins
  for each row execute function log_event_change();

-- RLS 有効・ポリシー無し = クライアントから deny-all。Edge Function(service role)と
-- 下記 SECURITY DEFINER RPC のみが触る。
alter table staff_pins enable row level security;

-- 本人がPINを設定/変更する(メール+パスワードでログイン済みの状態で呼ぶ)。ハッシュ化はサーバ側。
create or replace function set_my_pin(p_pin text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if my_employee_id() is null then
    raise exception 'not authenticated';
  end if;
  if p_pin !~ '^[0-9]{4,6}$' then
    raise exception 'PINは4〜6桁の数字で入力してください';
  end if;
  insert into staff_pins (employee_id, pin_hash, failed_attempts, locked_until, updated_at)
  values (my_employee_id(), crypt(p_pin, gen_salt('bf')), 0, null, now())
  on conflict (employee_id) do update
    set pin_hash = excluded.pin_hash, failed_attempts = 0, locked_until = null, updated_at = now();
end;
$$;

-- 管理者が対象職員のPINをリセット(削除=次回本人が再設定)。対象職員の所属施設を管理できる者のみ。
create or replace function reset_staff_pin(p_employee_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office uuid;
begin
  select home_office_id into v_office from employees where id = p_employee_id;
  if v_office is null then
    raise exception 'employee not found';
  end if;
  if not manages_office(v_office) then
    raise exception 'not authorized';
  end if;
  delete from staff_pins where employee_id = p_employee_id;
end;
$$;

-- admin_web 職員マスタ表示用: PIN設定状況(ハッシュは返さない)。対象施設を管理できる者のみ。
create or replace function fetch_staff_pin_status(p_office_id uuid)
returns table (employee_id uuid, has_pin boolean, is_locked boolean)
language sql stable security definer set search_path = public
as $$
  select e.id,
         (sp.employee_id is not null) as has_pin,
         (sp.locked_until is not null and sp.locked_until > now()) as is_locked
  from employees e
  left join staff_pins sp on sp.employee_id = e.id
  where manages_office(p_office_id) and e.home_office_id = p_office_id;
$$;
