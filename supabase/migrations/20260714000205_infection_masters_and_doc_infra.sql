-- 205: 感染症 Phase 1 = マスター拡張+初期データ22種+様式PDF基盤+機能フラグ2段
--      (設計指示書 2026-08-13 §4/§3.9、Phase 0確認事項の俊回答 2026-08-14:
--       ①初期データ=現行ガイドライン文言(インフルエンザ=乳幼児3日) ②様式格納=137一本化
--       ③admin_overrideは感染症ゲート突破不可(ゲートはPhase 5) ④退園後=閲覧のみ→アプリ使用終了で遮断)
--
-- 概要:
--  (1) 「統括園長以上」共通ヘルパー is_executive_director_or_admin() を新設(§6のマスター管理権限)。
--  (2) 既存 infectious_disease_masters(090) を §4.3 要件へ拡張(重複エンティティを作らない=§5):
--      登園のめやす・感染しやすい期間(参考)・宣言的ルール(rule_definition jsonb)・版管理
--      (version/effective_from/effective_to)・出典(source_title/url/revision)・運用承認の確認記録
--      (confirmed_by_name/confirmed_at)・表示順(sort_order)。
--      共通マスターの書き込みを system_admin → 統括園長以上へ拡大(§6)。
--  (3) 初期データ22種(意見書13+登園届9)を name で upsert(office_id=null・source='national'・version=1)。
--      文言は「保育所における感染症対策ガイドライン(2018年改訂版・2023年5月一部改訂)」の表のとおり
--      (俊承認 2026-08-14。インフルエンザは「乳幼児にあっては3日」)。
--      22種に含まれない既存の国基準行は is_active=false(選択肢から除外・履歴は保持)。
--  (4) rule_definition の宣言形式(§4.3・任意コード実行なし):
--      { "checks": ["症状確認チェック文言", ...],                    -- 全て必須チェック
--        "date_condition": {"base_label": "基準日時の名称", "min_hours": N} }  -- 任意(溶連菌のみ)
--      意見書13種は rule_definition=null(書類=医師記入の許可書のみ。動的チェックは登園届側の機構)。
--  (5) 様式PDF基盤: document_templates(137) に file_path(storageパス)を追加し、書き込みを
--      統括園長以上へ拡大。storageバケット document-templates(非公開)を新設
--      (閲覧=職員+保護者(様式は機微でない・保護者DL要件§6)、書き込み=統括園長以上)。
--      ※感染症マスタ(090)の form_template_storage_path は非推奨(137一本化・俊確定②)。
--  (6) 機能フラグ2段: infection_control_enabled / infection_gate_enabled(既定OFF)+判定RPC。
--      gate判定RPCは control AND gate を返し「gate単独ON」を構造的に不可能にする(§3.9)。
--
-- 冪等: 列追加=if not exists、index/policy=drop if exists→create、seed=name基準のupsert、
--       フラグ=not existsガード、関数=create or replace。

-- (1) 統括園長以上(system_admin + executive_director)。§6のマスター・様式管理権限。
--     147のmanages_childcareと同じ判定材料(employee_roles×roles)。office_idスコープは見ない
--     (統括園長は全施設・147と同方針)。
create or replace function is_executive_director_or_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from employee_roles er
    join roles r on r.id = er.role_id
    where er.employee_id = my_employee_id()
      and r.code in ('system_admin', 'executive_director')
  );
$$;

grant execute on function is_executive_director_or_admin() to anon, authenticated, service_role;

-- (2) マスター拡張(090へ列追加)
alter table infectious_disease_masters add column if not exists return_criteria text;
alter table infectious_disease_masters add column if not exists infectious_period text;
alter table infectious_disease_masters add column if not exists rule_definition jsonb;
alter table infectious_disease_masters add column if not exists version int not null default 1;
alter table infectious_disease_masters add column if not exists effective_from date not null default current_date;
alter table infectious_disease_masters add column if not exists effective_to date;
alter table infectious_disease_masters add column if not exists source_title text;
alter table infectious_disease_masters add column if not exists source_url text;
alter table infectious_disease_masters add column if not exists source_revision text;
alter table infectious_disease_masters add column if not exists confirmed_by_name text;
alter table infectious_disease_masters add column if not exists confirmed_at date;
alter table infectious_disease_masters add column if not exists sort_order int;

comment on column infectious_disease_masters.return_criteria is
  '登園のめやす(ガイドライン文言・保護者/職員向け表示。205)';
comment on column infectious_disease_masters.infectious_period is
  '感染しやすい期間(参考情報。システム判定には使わない=設計書§4.1注記。205)';
comment on column infectious_disease_masters.rule_definition is
  '登園届の宣言的ルール(205): {"checks":[文言,...], "date_condition":{"base_label":..,"min_hours":N}}。意見書対象はnull';
comment on column infectious_disease_masters.version is
  '版番号(205)。改訂時は新しい行を追加し旧行に effective_to を入れる(過去記録は当時の版で再現=AC-16)';
comment on column infectious_disease_masters.form_template_storage_path is
  '【非推奨(205)】様式PDFは document_templates(137拡張)で一元管理する(俊確定 2026-08-14)。本列は使用しない';

-- 同名・同版の重複防止(共通マスターのみ。園独自 office_specific は従来どおり)
drop index if exists uq_infectious_disease_masters_name_version;
create unique index uq_infectious_disease_masters_name_version
  on infectious_disease_masters(name, version) where office_id is null;

-- 共通マスターの書き込みを 統括園長以上 へ拡大(従来=system_adminのみ)
drop policy if exists infectious_disease_masters_write_global on infectious_disease_masters;
create policy infectious_disease_masters_write_global on infectious_disease_masters
  for all using (office_id is null and is_executive_director_or_admin())
  with check (office_id is null and is_executive_director_or_admin());

-- (3) 初期データ22種(俊承認 2026-08-14: ガイドライン2018年改訂版(2023年5月一部改訂)の文言)
do $$
declare
  v_src_title text := '保育所における感染症対策ガイドライン(2018年改訂版)';
  v_src_rev   text := '2023(令和5)年5月一部改訂';
  v_src_url   text := 'https://www.cfa.go.jp/policies/hoiku/kansensho-guideline';
  v_from      date := date '2026-08-14';
  r record;
begin
  for r in
    select * from (values
      -- 意見書(医師記入・登園許可書)13種 ------------------------------------------------
      (1,  '麻しん(はしか)', 'second', true, false,
       '解熱後3日を経過していること',
       '発症1日前から発しん出現後の4日後まで', null::jsonb),
      (2,  'インフルエンザ', 'second', true, false,
       '発症した後5日経過し、かつ解熱した後2日経過していること(乳幼児にあっては、3日経過していること)',
       '症状が有る期間(発症前24時間から発病後3日程度までが最も感染力が強い)', null),
      (3,  '新型コロナウイルス感染症', 'second', true, false,
       '発症した後5日を経過し、かつ症状が軽快した後1日を経過すること(無症状の感染者の場合は、検体採取日を0日目として、5日を経過すること)',
       '発症後5日間', null),
      (4,  '風しん', 'second', true, false,
       '発しんが消失していること',
       '発しん出現の7日前から7日後くらい', null),
      (5,  '水痘(水ぼうそう)', 'second', true, false,
       'すべての発しんが痂皮(かさぶた)化していること',
       '発しん出現1〜2日前から痂皮(かさぶた)形成まで', null),
      (6,  '流行性耳下腺炎(おたふくかぜ)', 'second', true, false,
       '耳下腺、顎下腺、舌下腺の腫脹が発現してから5日経過し、かつ全身状態が良好になっていること',
       '発症3日前から耳下腺腫脹後4日', null),
      (7,  '結核', 'second', true, false,
       '医師により感染の恐れがないと認められていること', null, null),
      (8,  '咽頭結膜熱(プール熱)', 'second', true, false,
       '発熱、充血等の主な症状が消失した後2日経過していること',
       '発熱、充血等の症状が出現した数日間', null),
      (9,  '流行性角結膜炎', 'third', true, false,
       '結膜炎の症状が消失していること',
       '充血、目やに等の症状が出現した数日間', null),
      (10, '百日咳', 'second', true, false,
       '特有の咳が消失していること又は適正な抗菌性物質製剤による5日間の治療が終了していること',
       '抗菌薬を服用しない場合、咳出現後3週間を経過するまで', null),
      (11, '腸管出血性大腸菌感染症(O157、O26、O111等)', 'third', true, false,
       '医師により感染のおそれがないと認められていること(無症状病原体保有者の場合、トイレでの排泄習慣が確立している5歳以上の小児については出席停止の必要はなく、また、5歳未満の子どもについては、2回以上連続で便から菌が検出されなければ登園可能である)',
       null, null),
      (12, '急性出血性結膜炎', 'third', true, false,
       '医師により感染の恐れがないと認められていること', null, null),
      (13, '侵襲性髄膜炎菌感染症(髄膜炎菌性髄膜炎)', 'second', true, false,
       '医師により感染の恐れがないと認められていること', null, null),
      -- 登園届(保護者記入)9種 ----------------------------------------------------------
      (14, '溶連菌感染症', 'third', false, true,
       '抗菌薬内服後24〜48時間が経過していること',
       '適切な抗菌薬治療を開始する前と開始後1日間',
       '{"checks":["医師の診断を受け、抗菌薬の内服を開始した"],"date_condition":{"base_label":"抗菌薬の内服を開始した日時","min_hours":24}}'::jsonb),
      (15, 'マイコプラズマ肺炎', 'third', false, true,
       '発熱や激しい咳が治まっていること',
       '適切な抗菌薬治療を開始する前と開始後数日間',
       '{"checks":["発熱が治まっている","激しい咳が治まっている"]}'),
      (16, '手足口病', 'third', false, true,
       '発熱や口腔内の水疱・潰瘍の影響がなく、普段の食事がとれること',
       '手足や口腔内に水疱・潰瘍が発症した数日間',
       '{"checks":["発熱がない","口腔内の水疱・潰瘍の影響がない","普段の食事がとれている"]}'),
      (17, '伝染性紅斑(りんご病)', 'third', false, true,
       '全身状態が良いこと',
       '発しん出現前の1週間',
       '{"checks":["全身状態が良い"]}'),
      (18, 'ウイルス性胃腸炎(ノロウイルス、ロタウイルス、アデノウイルス等)', 'third', false, true,
       '嘔吐、下痢等の症状が治まり、普段の食事がとれること',
       '症状のある間と、症状消失後1週間(量は減少していくが数週間ウイルスを排出しているので注意が必要)',
       '{"checks":["嘔吐が治まっている","下痢等の症状が治まっている","普段の食事がとれている"]}'),
      (19, 'ヘルパンギーナ', 'third', false, true,
       '発熱や口腔内の水疱・潰瘍の影響がなく、普段の食事がとれること',
       '急性期の数日間(便の中に1か月程度ウイルスを排出しているので注意が必要)',
       '{"checks":["発熱がない","口腔内の水疱・潰瘍の影響がない","普段の食事がとれている"]}'),
      (20, 'RSウイルス感染症', 'third', false, true,
       '呼吸器症状が消失し、全身状態が良いこと',
       '呼吸器症状のある間',
       '{"checks":["呼吸器症状が消失している","全身状態が良い"]}'),
      (21, '帯状疱しん', 'third', false, true,
       'すべての発しんが痂皮(かさぶた)化していること',
       '水疱を形成している間',
       '{"checks":["すべての発しんがかさぶた(痂皮)になっている"]}'),
      (22, '突発性発しん', 'third', false, true,
       '解熱し機嫌が良く全身状態が良いこと', null,
       '{"checks":["解熱している","機嫌が良く全身状態が良い"]}')
    ) as t(ord, name, category, opinion, form, criteria, period, rule)
  loop
    update infectious_disease_masters set
      category = r.category,
      requires_opinion_letter = r.opinion,
      requires_return_form = r.form,
      return_criteria = r.criteria,
      infectious_period = r.period,
      rule_definition = r.rule,
      version = 1,
      effective_from = v_from,
      effective_to = null,
      source = 'national',
      source_title = v_src_title,
      source_url = v_src_url,
      source_revision = v_src_rev,
      sort_order = r.ord,
      is_active = true
    where office_id is null and name = r.name;

    if not found then
      insert into infectious_disease_masters
        (office_id, name, category, requires_opinion_letter, requires_return_form,
         return_criteria, infectious_period, rule_definition,
         version, effective_from, source, source_title, source_url, source_revision,
         sort_order, is_active)
      values
        (null, r.name, r.category, r.opinion, r.form,
         r.criteria, r.period, r.rule,
         1, v_from, 'national', v_src_title, v_src_url, v_src_rev,
         r.ord, true);
    end if;
  end loop;

  -- 22種に含まれない既存の国基準行は選択肢から除外(履歴として行は残す)
  update infectious_disease_masters set is_active = false
  where office_id is null and source = 'national'
    and name not in (
      '麻しん(はしか)','インフルエンザ','新型コロナウイルス感染症','風しん','水痘(水ぼうそう)',
      '流行性耳下腺炎(おたふくかぜ)','結核','咽頭結膜熱(プール熱)','流行性角結膜炎','百日咳',
      '腸管出血性大腸菌感染症(O157、O26、O111等)','急性出血性結膜炎','侵襲性髄膜炎菌感染症(髄膜炎菌性髄膜炎)',
      '溶連菌感染症','マイコプラズマ肺炎','手足口病','伝染性紅斑(りんご病)',
      'ウイルス性胃腸炎(ノロウイルス、ロタウイルス、アデノウイルス等)','ヘルパンギーナ',
      'RSウイルス感染症','帯状疱しん','突発性発しん'
    );
end $$;

-- (5) 様式PDF基盤: 137拡張(俊確定②=137一本化)
alter table document_templates add column if not exists file_path text;

comment on column document_templates.file_path is
  '様式PDF実体のstorageパス(document-templatesバケット。205)。NULL=ファイル未登録(項目定義のみ)';

-- 書き込みを 統括園長以上 へ拡大(§4.3(b): マスター・様式の管理=俊(executive_director)/system_admin)
drop policy if exists document_templates_write_system_admin on document_templates;
create policy document_templates_write_system_admin on document_templates
  for all using (is_executive_director_or_admin()) with check (is_executive_director_or_admin());

insert into storage.buckets (id, name, public)
values ('document-templates', 'document-templates', false)
on conflict (id) do nothing;

-- 閲覧=職員+保護者(様式は機微情報でなく、保護者のPDF閲覧・DLが要件=§6)。書き込み=統括園長以上。
drop policy if exists document_templates_storage_read on storage.objects;
drop policy if exists document_templates_storage_write on storage.objects;
drop policy if exists document_templates_storage_update on storage.objects;
drop policy if exists document_templates_storage_delete on storage.objects;
create policy document_templates_storage_read on storage.objects
  for select using (
    bucket_id = 'document-templates' and (my_employee_id() is not null or is_guardian())
  );
create policy document_templates_storage_write on storage.objects
  for insert with check (
    bucket_id = 'document-templates' and is_executive_director_or_admin()
  );
create policy document_templates_storage_update on storage.objects
  for update using (
    bucket_id = 'document-templates' and is_executive_director_or_admin()
  );
create policy document_templates_storage_delete on storage.objects
  for delete using (
    bucket_id = 'document-templates' and is_executive_director_or_admin()
  );

-- (6) 機能フラグ2段(§3.9)。gate判定は control AND gate = gate単独ONを構造的に不可能にする。
insert into feature_flags (feature_key, name, description, default_enabled)
select 'infection_control_enabled', '感染症管理(カード・届)',
       '引き継ぎカード・欠席連絡の感染症案件・電子登園届・許可書配布', false
where not exists (select 1 from feature_flags where feature_key = 'infection_control_enabled');

insert into feature_flags (feature_key, name, description, default_enabled)
select 'infection_gate_enabled', '感染症登園ゲート',
       '必要書類未充足時の登園ブロック(infection_control_enabledが前提)', false
where not exists (select 1 from feature_flags where feature_key = 'infection_gate_enabled');

create or replace function is_infection_control_enabled_for_office(p_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select is_feature_enabled_for_office('infection_control_enabled', p_office_id);
$$;

create or replace function is_infection_gate_enabled_for_office(p_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  -- gate単独ONは無効(§3.9: controlを先行させる2段構成)
  select is_feature_enabled_for_office('infection_control_enabled', p_office_id)
     and is_feature_enabled_for_office('infection_gate_enabled', p_office_id);
$$;

grant execute on function is_infection_control_enabled_for_office(uuid) to anon, authenticated, service_role;
grant execute on function is_infection_gate_enabled_for_office(uuid) to anon, authenticated, service_role;
