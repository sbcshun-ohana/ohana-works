-- 保護者アプリ Phase A: 登降園用の動的QRトークン(変更6)
--
-- 既存qr_tokens(9.2 職員打刻用)と同じ設計を踏襲する:
--   - サーバー発行の署名付きトークン(HMAC、有効期限60〜90秒)
--   - token_hashで保存し、生トークンはDBに残さない
--   - サーバー側でワンタイム消費(update ... where status='issued'の原子的更新)
-- 発行・消費はEdge Function(service role)経由に限定し、クライアントからの直接書込は
-- 許可しない(qr_tokens_select_selfと同じ方針)。

create table guardian_qr_tokens (
  id uuid primary key default gen_random_uuid(),
  guardian_id uuid not null references guardians(id) on delete cascade,
  child_id uuid not null references children(id) on delete cascade,
  token_hash text not null unique,
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  status text not null default 'issued' check (status in ('issued', 'used', 'expired')),
  used_at timestamptz,
  used_by_device_id uuid references devices(id),
  created_at timestamptz not null default now()
);
create index idx_guardian_qr_tokens_guardian on guardian_qr_tokens(guardian_id);
create index idx_guardian_qr_tokens_child on guardian_qr_tokens(child_id);

alter table guardian_qr_tokens enable row level security;
create policy guardian_qr_tokens_select_self on guardian_qr_tokens
  for select using (guardian_id = my_guardian_id());
