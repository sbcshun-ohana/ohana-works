-- =====================================================================
-- 統合追加機能 Phase A: 本番(wdsziqxvmhwbdyfeiame)確認クエリ集
-- =====================================================================
-- 目的: Claude Code の作業環境から本番DBへ接続できないため、本番でのみ
--       確認可能な現状データを俊さんが本番Supabaseの SQL Editor で実行し、
--       結果を貼り返していただくためのクエリ集。
-- 安全性: 全クエリ READ ONLY(SELECT のみ)。INSERT/UPDATE/DELETE/DDL は一切含まない。
-- 実行方法: 各ブロックを個別に実行して結果を確認してください。氏名等の個人情報は
--           原則出力しない設計にしています(⑥のみ承認者確認のため氏名を出します)。
-- 対応する質問: Q9(①〜⑤)+ Q8(⑥ 統括園長=大原利奈の現行役職調査)
-- =====================================================================


-- ---------------------------------------------------------------------
-- ① 本番のクラス写真の件数
--    確認内容: 既存クラス写真の規模。M4写真販売は「透かし版のみ保存で原本なし」
--              の前提のため、既存写真の量と状態(下書き/確認済/公開)を把握する。
-- ---------------------------------------------------------------------
select status, count(*) as photos
from class_daily_photos
group by status
order by status;

select count(*) as class_daily_photos_total from class_daily_photos;


-- ---------------------------------------------------------------------
-- ② 請求・契約関連データの有無
--    確認内容: M3(請求・決済)/M6(入園契約)の新規性の裏付け。請求・契約・料金・
--              プラン系のテーブルが本番に存在しない(=新規構築)ことを確認し、
--              併せて「契約の代理」となる在籍データの規模を見る。
-- ---------------------------------------------------------------------
-- 2-a: 請求/契約/料金/プラン/決済系の名前を持つテーブルの有無(1行でも出れば要確認)
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name ~* 'billing|invoice|payment|charge|fee|plan|contract|settlement|guardian_notice';

-- 2-b: 契約規模の代理指標(園児数・在籍レコード数)
select
  (select count(*) from children)                                             as children_total,
  (select count(*) from children where enrollment_status = '在籍中')          as children_enrolled,
  (select count(*) from child_class_enrollments where effective_end_date is null) as active_enrollments;


-- ---------------------------------------------------------------------
-- ③ 感染症関連の現行運用実態
--    確認内容: M8(感染症欠席・登園再開)は既存 parent_requests への拡張方針。
--              infectious_disease 型を含む申請の件数、欠席理由(自由記述)の使用実態を見る。
-- ---------------------------------------------------------------------
-- 3-a: 保護者申請の種別×状態別件数(infectious_disease の実利用を確認)
select request_type, status, count(*) as n
from parent_requests
group by request_type, status
order by request_type, status;

-- 3-b: 欠席理由(自由記述)の内容分布(マスタ化の要否判断用。氏名は出さない)
select absence_reason, count(*) as n
from child_daily_attendance
where is_absent = true and coalesce(absence_reason, '') <> ''
group by absence_reason
order by n desc
limit 30;


-- ---------------------------------------------------------------------
-- ④ feature_flags: child_internal_notes_enabled の本番状態
--    確認内容: 園内記録の main push 後の後追い安全確認。本番でこのフラグが
--              どの施設でも OFF のままであることを3段階で確認する。
--              (145番が本番未適用なら 4-a は 0 行になる想定)
-- ---------------------------------------------------------------------
-- 4-a: グローバル既定値(この行自体が無ければ 145番 未適用=フラグ機構ごと不在)
select feature_key, default_enabled
from feature_flags
where feature_key = 'child_internal_notes_enabled';

-- 4-b: 施設別オーバーライド(1行も出なければ、どの施設もONにしていない)
select o.name as office, ov.enabled
from feature_flag_office_overrides ov
join offices o on o.id = ov.office_id
where ov.feature_key = 'child_internal_notes_enabled';

-- 4-c: 施設ごとの実効値(effective_enabled が true の行が1つも無いことを確認)
select o.name,
  coalesce(
    (select enabled from feature_flag_office_overrides ov
       where ov.feature_key = 'child_internal_notes_enabled' and ov.office_id = o.id),
    (select default_enabled from feature_flags where feature_key = 'child_internal_notes_enabled'),
    false) as effective_enabled
from offices o
order by o.name;


-- ---------------------------------------------------------------------
-- ⑤ BABY MAHALO の3〜5歳児在籍の実例(Q6 追加調査)
--    確認内容: 従業員託児で3〜5歳児を BABY MAHALO(通常0〜2歳クラスのみ)へ
--              登録する際、「年齢相当クラスが無い」ケースが現状どう扱われているか。
--              クラス未割当在籍が可能か/実例があるかを本番で確認する。
--    ※ ステージングは seed が全施設に3〜5歳クラスを作っているため再現できない。
-- ---------------------------------------------------------------------
-- 5-a: BABY MAHALO の現行クラスの年齢区分(3〜5歳クラスが無いことの確認)
select cc.class_name, cc.age_group, cc.school_year
from childcare_classes cc
join offices o on o.id = cc.office_id
where o.name = 'BABY MAHALO'
order by cc.school_year, cc.class_name;

-- 5-b: BABY MAHALO 在籍児の「学年年齢(4/1基準)」×「割当クラスの年齢区分」の分布
--      cohort_age_at_april1 が 3 以上の在籍児が居るか、居る場合どのクラスに入っているか
--      (enrolled_class_age_group が NULL ならクラス未割当)。氏名は出さない。
with ref as (
  select make_date(
           case when extract(month from current_date) >= 4
                then extract(year from current_date)::int
                else extract(year from current_date)::int - 1 end,
           4, 1) as april1
)
select
  date_part('year', age((select april1 from ref), c.birth_date))::int as cohort_age_at_april1,
  cc.age_group as enrolled_class_age_group,
  count(*)     as children
from children c
join offices o on o.id = c.office_id and o.name = 'BABY MAHALO'
left join child_class_enrollments e on e.child_id = c.id and e.effective_end_date is null
left join childcare_classes cc on cc.id = e.class_id
where c.enrollment_status in ('在籍中', '入園予定')
group by 1, 2
order by 1;

-- 5-c: 全施設で「在籍だが有効なクラス割当が無い」児童の件数(クラス未割当在籍の実在確認)
select o.name as office, count(*) as children_without_active_class
from children c
join offices o on o.id = c.office_id
where c.enrollment_status in ('在籍中', '入園予定')
  and not exists (
    select 1 from child_class_enrollments e
    where e.child_id = c.id and e.effective_end_date is null
  )
group by o.name
order by o.name;


-- ---------------------------------------------------------------------
-- ⑥ 統括園長(大原利奈)の現行システム役職・施設スコープ(Q8 調査)
--    確認内容: 感染症提出ルールの承認者=大原利奈統括園長。「統括園長」は
--              ロールコードに存在しない業務役職のため、大原氏に現在DB上で
--              どの役職(role)がどの施設スコープで割り当てられているかを確認する。
--              (Phase0調査報告では「役職の対応関係はDB未入力」の可能性が指摘されている)
--    ※ 氏名一致確認のため name を出力します。表記揺れ(大原利奈/おおはら等)に注意。
-- ---------------------------------------------------------------------
-- 6-a: 「大原」を含む職員と、割り当てられている役職・施設スコープ
select e.employee_number, e.name,
       r.code as role_code, r.name as role_name,
       o.name as scoped_office   -- er.office_id が NULL なら全施設スコープ
from employees e
left join employee_roles er on er.employee_id = e.id
left join roles r on r.id = er.role_id
left join offices o on o.id = er.office_id
where e.name like '%大原%'
order by e.employee_number, r.sort_order;

-- 6-b: 全職員の役職割当の有無(director/chief/office_manager が誰かに入っているか。
--      Phase0調査の「実在職員に director/chief/office_manager が0名」の現況確認)
select r.code as role_code, count(er.employee_id) as assigned_employees
from roles r
left join employee_roles er on er.role_id = r.id
group by r.code, r.sort_order
order by r.sort_order;


-- ---------------------------------------------------------------------
-- ⑦ (任意) burden_fee_masters / burden_fee_records の本番件数
--    確認内容: ②でヒットした2テーブルは「職員の給食費(まかない)負担金=給与控除」で
--              M3(保護者請求)とは無関係、と調査済み(Phase A報告§8.2)。本番の規模を
--              念のため確認するための任意クエリ(M3設計には影響しない)。
-- ---------------------------------------------------------------------
select 'burden_fee_masters' as t, count(*) as n from burden_fee_masters
union all
select 'burden_fee_records', count(*) from burden_fee_records;

-- 参考: 施設別単価(職員給食費の単価。保育料ではない)
select o.name as office, m.unit_price, m.effective_start_date
from burden_fee_masters m
join offices o on o.id = m.office_id
order by o.name;
