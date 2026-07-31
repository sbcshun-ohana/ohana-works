-- 要件3(職員ピッカー+PIN簡易ログイン)のサーバ側DB。
-- 設計: docs/権限・セッション管理_設計案_2026-07-30.md §4。
--
-- 原則:
--  - PINは**ハッシュのみ保存**(pgcrypto bcrypt)。平文・ログ出力禁止。
--  - staff_pins / pin_login_attempts はクライアントから一切アクセス不可(RLS有効・ポリシー無し
--    =deny-all)。pin_hash はどの経路でもクライアントへ返さない。
--  - ピッカー表示・PIN検証・セッション発行は Edge Function(service role)がサーバ側で行う。
--    クライアントでPIN照合しない。
--
-- 【セキュリティレビュー反映 2026-07-31】
--  1) 端末バインド強化と併せ、PIN最小桁数を **6桁** に引き上げ(端末IDが平文shared_preferences
--     保管で複製可能なため、ブルートフォース耐性を桁数＋レート制限で担保する)。
--  3) 職員単位ロックに加え **端末単位のレート制限**(pin_login_attempts で device_id×時間窓)。
--  5) 自明なPIN(全桁同一・連番昇降)を set_my_pin で拒否。
--  reset_staff_pin は **削除方式**(既知の初期PINを設定しない=管理者なりすまし経路を作らない)。
--
-- volatility(§3.2b): set/reset は書き込み=volatile。fetch_staff_pin_status/is_weak_pin は stable/immutable。
--  いずれも log_sensitive_access を呼ばない。

-- ============================================================
-- staff_pins: PINハッシュ・失敗回数・職員単位ロック
-- ============================================================
create table staff_pins (
  employee_id uuid primary key references employees(id) on delete cascade,
  pin_hash text not null,
  failed_attempts int not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);
create trigger trg_staff_pins_updated_at before update on staff_pins
  for each row execute function set_updated_at();
create trigger trg_audit_staff_pins after insert or update or delete on staff_pins
  for each row execute function log_event_change();
alter table staff_pins enable row level security;  -- deny-all(Edge Function service role のみ)

-- ============================================================
-- pin_login_attempts: 端末単位レート制限＋監査。PIN値は保存しない(resultのみ)。
-- ============================================================
create table pin_login_attempts (
  id uuid primary key default gen_random_uuid(),
  device_id uuid references devices(id) on delete set null,
  employee_id uuid references employees(id) on delete set null,
  result text not null check (result in (
    'success', 'invalid_pin', 'locked', 'no_pin', 'no_access',
    'device_invalid', 'device_rate_limited'
  )),
  attempted_at timestamptz not null default now()
);
create index idx_pin_login_attempts_device_time on pin_login_attempts (device_id, attempted_at);
alter table pin_login_attempts enable row level security;  -- deny-all(Edge Function service role のみ)

-- ============================================================
-- 自明なPINの判定(全桁同一 / 連番の昇順・降順)
-- ============================================================
create or replace function is_weak_pin(p_pin text)
returns boolean
language plpgsql immutable
as $$
declare
  i int;
  all_same boolean := true;
  asc_seq boolean := true;
  desc_seq boolean := true;
begin
  if p_pin is null or length(p_pin) < 2 then
    return true;
  end if;
  for i in 2 .. length(p_pin) loop
    if substr(p_pin, i, 1) <> substr(p_pin, 1, 1) then
      all_same := false;
    end if;
    if ascii(substr(p_pin, i, 1)) <> ascii(substr(p_pin, i - 1, 1)) + 1 then
      asc_seq := false;
    end if;
    if ascii(substr(p_pin, i, 1)) <> ascii(substr(p_pin, i - 1, 1)) - 1 then
      desc_seq := false;
    end if;
  end loop;
  return all_same or asc_seq or desc_seq;
end;
$$;

-- ============================================================
-- 本人がPINを設定/変更(メール+パスワードでログイン済みで呼ぶ)。ハッシュ化はサーバ側。
-- ============================================================
create or replace function set_my_pin(p_pin text)
returns void
language plpgsql security definer set search_path = public
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

-- ============================================================
-- 管理者が対象職員のPINをリセット(**削除方式**=次回本人が再設定)。対象施設を管理できる者のみ。
-- ============================================================
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
  delete from staff_pins where employee_id = p_employee_id;  -- 既知PINを設定しない(なりすまし防止)
end;
$$;

-- ============================================================
-- admin_web 職員マスタ表示用: PIN設定状況(ハッシュは返さない)。対象施設を管理できる者のみ。
-- ============================================================
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
