-- 208: 一斉配信(保護者向けお知らせ=guardian_notices)のPDF・画像添付(俊指示 2026-08-14)。
--
-- 概要:
--  (1) 添付テーブル guardian_notice_attachments(お知らせ×複数ファイル・表示順つき)。
--  (2) storageバケット guardian-notice-attachments(非公開)。パス規約 {notice_id}/{ファイル名}。
--      アップロード/削除=職員(作成フローは既存の下書き→承認→送信のまま)。
--      閲覧=職員全体(既存notice-attachmentsと同じ簡易方針)+
--            保護者は「自分がrecipientの承認済み・未取消のお知らせ」の添付のみ(152の閲覧規則と一致)。
--  (3) 監査=log_event_change。
--
-- 冪等: バケット=on conflict、ポリシー=drop if exists→create。テーブルは初回適用前提の素create。

create table guardian_notice_attachments (
  id uuid primary key default gen_random_uuid(),
  notice_id uuid not null references guardian_notices(id) on delete cascade,
  file_path text not null,
  file_name text not null,
  content_type text,
  file_size_bytes int,
  sort_order int not null default 0,
  created_by uuid references employees(id),
  created_at timestamptz not null default now()
);

comment on table guardian_notice_attachments is
  '一斉配信の添付(208)。PDF/画像をstorage(guardian-notice-attachments)に置き、パスを保持する';

create index idx_gna_notice on guardian_notice_attachments (notice_id);

alter table guardian_notice_attachments enable row level security;

-- 職員: 参照/追加/削除可(お知らせ本体の作成・承認フローは既存のまま。簡易方針=在籍職員)
create policy gna_staff_all on guardian_notice_attachments
  for all using (my_employee_id() is not null) with check (my_employee_id() is not null);

-- 保護者: 自分がrecipientの承認済み・未取消お知らせの添付のみ参照可(152の可視規則と一致)
create policy gna_guardian_select on guardian_notice_attachments
  for select using (
    exists (
      select 1
      from guardian_notice_recipients r
      join guardian_notices n on n.id = r.notice_id
      where r.notice_id = guardian_notice_attachments.notice_id
        and r.guardian_id = my_guardian_id()
        and n.status = 'approved'
        and n.revoked_at is null
    )
  );

do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'guardian_notice_attachments'
  );
end $$;

-- storage バケット+ポリシー(パス規約: {notice_id}/{ファイル名})
insert into storage.buckets (id, name, public)
values ('guardian-notice-attachments', 'guardian-notice-attachments', false)
on conflict (id) do nothing;

drop policy if exists guardian_notice_attachments_staff_read on storage.objects;
drop policy if exists guardian_notice_attachments_staff_write on storage.objects;
drop policy if exists guardian_notice_attachments_staff_delete on storage.objects;
drop policy if exists guardian_notice_attachments_guardian_read on storage.objects;

create policy guardian_notice_attachments_staff_read on storage.objects
  for select using (
    bucket_id = 'guardian-notice-attachments' and my_employee_id() is not null
  );
create policy guardian_notice_attachments_staff_write on storage.objects
  for insert with check (
    bucket_id = 'guardian-notice-attachments' and my_employee_id() is not null
  );
create policy guardian_notice_attachments_staff_delete on storage.objects
  for delete using (
    bucket_id = 'guardian-notice-attachments' and my_employee_id() is not null
  );
create policy guardian_notice_attachments_guardian_read on storage.objects
  for select using (
    bucket_id = 'guardian-notice-attachments'
    and exists (
      select 1
      from guardian_notice_recipients r
      join guardian_notices n on n.id = r.notice_id
      where r.notice_id = ((storage.foldername(name))[1])::uuid
        and r.guardian_id = my_guardian_id()
        and n.status = 'approved'
        and n.revoked_at is null
    )
  );
