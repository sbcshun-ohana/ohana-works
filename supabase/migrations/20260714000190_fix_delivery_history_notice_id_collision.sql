-- fetch_guardian_notice_delivery_history() の列名衝突を修正する。
--
-- 不具合: 戻り値のOUTパラメータ名 notice_id が、世帯数を数えるサブクエリ内で
-- 無修飾参照している guardian_notice_recipients.notice_id と衝突しており、
-- 呼び出すたびに "column reference \"notice_id\" is ambiguous" で必ず失敗していた
-- (bulk_promote_children/135・tax_withholding/136 と同一パターン)。
-- admin_web の一斉配信ページ(childcare/announcements)上部で実機確認し、
--   「配信履歴の取得に失敗しました: column reference \"notice_id\" is ambiguous」
-- を実際に確認済み。180 の他の notice_id 参照は全て t.notice_id / gn.id と
-- 修飾済みのため、衝突していたのは世帯数サブクエリの1箇所のみ。
--
-- 修正: 世帯数サブクエリの WHERE 句を guardian_notice_recipients.notice_id と
-- テーブル名で明示的に修飾する。戻り値の列名・型・順序・その他ロジックは一切
-- 変更しない(呼び出し元 admin_web との互換性を保つ)。
--
-- 適用形態: create or replace のみ(drop 不要・データ変更なし)。
-- 依存関係: 修正対象 180 は第1弾(145〜183)に含まれる。本修正は 184〜189
-- (第2弾/デイリーボード刷新)のいずれのオブジェクトにも依存しない。

create or replace function fetch_guardian_notice_delivery_history(p_office_id uuid)
returns table (
  notice_id uuid, title text, status text, scheduled_send_at timestamptz, sent_at timestamptz,
  revoked_at timestamptz, target_summary text, recipient_household_count int
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  return query
  select gn.id, gn.title, gn.status, gn.scheduled_send_at, gn.sent_at, gn.revoked_at,
    coalesce((
      select string_agg(
        case t.target_type
          when 'all' then '全体'
          when 'office' then '施設:' || o.name
          when 'class' then 'クラス:' || cc.class_name
          when 'child' then '園児:' || ch.display_name
        end, ' / ')
      from guardian_notice_targets t
      left join offices o on o.id = t.office_id
      left join childcare_classes cc on cc.id = t.class_id
      left join children ch on ch.id = t.child_id
      where t.notice_id = gn.id
    ), '—'),
    (select count(distinct guardian_id)::int from guardian_notice_recipients
       where guardian_notice_recipients.notice_id = gn.id)
  from guardian_notices gn
  where exists (
    select 1 from guardian_notice_targets t
    left join childcare_classes cc on cc.id = t.class_id
    left join children ch on ch.id = t.child_id
    where t.notice_id = gn.id and (
      t.target_type = 'all' or t.office_id = p_office_id
      or cc.office_id = p_office_id or ch.office_id = p_office_id
    )
  )
  order by coalesce(gn.sent_at, gn.scheduled_send_at, gn.updated_at) desc;
end; $$;
