-- 保護者アプリ Phase A 修正: 保護者申請の種類を見直す。
-- 「感染症」は独立した申請種類から廃止し、「欠席」のdetails内(感染症による欠席か、
-- 該当する感染症の種類)に統合する(既存のinfectious_disease_masters・
-- fetch_infectious_disease_masters相当のRLSはそのまま流用し、テーブル自体は変更しない)。
-- 「その他連絡」を新設し、保護者が自由に園へ連絡できるようにする。
--
-- parent_requests・infectious_disease_masters とも本番データ0件のため、
-- 既存行への影響なく列挙値を差し替えられる(2026-07-17 確認済み)。

alter table parent_requests drop constraint parent_requests_request_type_check;
alter table parent_requests add constraint parent_requests_request_type_check
  check (request_type in ('absence', 'tardiness', 'early_leave', 'pickup_person_change', 'other'));
