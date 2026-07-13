-- 8章 お知らせ機能: 既読管理・管理者による未読者確認・添付ファイル格納の補強
--
-- 20260710160006_rls.sql は既にリモート適用済みのため、追加ポリシーは
-- 本ファイルで独立して定義する。

-- 職員は「自分が閲覧可能な notices」に対してのみ、自分の notice_recipients 行を
-- 作成できる(会社一斉/園単位/役職別など、事前にrecipient行が用意されていない
-- 配信でも、開封時に自己申告で既読行を作成できるようにする)。
-- exists(...)はnoticesテーブルのRLS(notices_select_target)を経由して評価されるため、
-- 閲覧権限のない notice_id に対しては挿入できない。
create policy notice_recipients_insert_self on notice_recipients
  for insert with check (
    employee_id = my_employee_id()
    and exists (select 1 from notices n where n.id = notice_recipients.notice_id)
  );

-- 管理者(施設管理範囲を持つロール)は、自身の管理施設に所属する職員の
-- 既読状況を閲覧できる(8章: 未読者一覧確認)。
create policy notice_recipients_select_managers on notice_recipients
  for select using (
    exists (
      select 1 from employees e
      where e.id = notice_recipients.employee_id and manages_office(e.home_office_id)
    )
  );

-- お知らせ添付ファイル格納用バケット。
-- 実際のアクセス制御は notices/notice_attachments 側のRLSで行毎に既に絞られているため、
-- (=見えないnotice_attachments行のfile_pathはクライアントがそもそも取得できない)
-- ストレージ側はログイン済み職員全体に読み取りを許可する簡易ポリシーとする。
insert into storage.buckets (id, name, public)
values ('notice-attachments', 'notice-attachments', false)
on conflict (id) do nothing;

create policy notice_attachments_storage_read on storage.objects
  for select using (
    bucket_id = 'notice-attachments' and my_employee_id() is not null
  );
