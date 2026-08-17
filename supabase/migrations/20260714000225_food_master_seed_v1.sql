-- 225: 食材チェック初期マスター投入(草案§13.3必須31/§13.4目安73・version 1・俊承認済 2026-08-17)。
-- staging適用済み。件数突合: 必須=初期7/中期6/後期4/完了期14、目安=初期18/中期19/後期15/完了期21。
-- 二重実行防止つき。回数要件=2回(版で変更可)。代替グループ=いずれか1つ(any)。
-- ※本番公開前に給食担当者の確認が必要(草案§13.3注記)。

do $$
declare
  v_ver uuid;
begin
  if exists (select 1 from food_checklist_versions where version = 1) then
    raise exception '初期マスター(version 1)は投入済みです';
  end if;

  insert into food_checklist_versions (version, status, required_times, note, published_at)
  values (1, 'published', 2, '初期版(草案§13.3/13.4・2026-08-17投入・本番公開前に給食担当者確認)', now())
  returning id into v_ver;

  create temporary table _seed_ctx(ver uuid);
  insert into _seed_ctx values (v_ver);
end $$;

create or replace function pg_temp._seed(
  p_stage text, p_group text, p_category text, p_name text, p_order int,
  p_alt text default null, p_alt_rule text default null
) returns void language plpgsql as $$
declare v_item uuid; v_ver uuid;
begin
  select ver into v_ver from _seed_ctx;
  insert into food_items (name, food_group) values (p_name, p_group)
  on conflict (name) do update set food_group = excluded.food_group
  returning id into v_item;
  insert into food_checklist_items (version_id, food_item_id, stage, category, alt_group, alt_group_rule, display_order)
  values (v_ver, v_item, p_stage, p_category, p_alt, p_alt_rule, p_order);
end $$;

-- ============ §13.3 必須確認食材 ============
-- 初期/穀類
select pg_temp._seed('初期','穀類','required','食パン(パン粥)',10);
-- 初期/たんぱく質
select pg_temp._seed('初期','たんぱく質','required','豆腐',20,'初期_豆腐グループ','any');
select pg_temp._seed('初期','たんぱく質','required','きな粉',21,'初期_豆腐グループ','any');
select pg_temp._seed('初期','たんぱく質','required','高野豆腐(すりおろし)',22,'初期_豆腐グループ','any');
select pg_temp._seed('初期','たんぱく質','required','たい',23);
select pg_temp._seed('初期','たんぱく質','required','かれい',24);
-- 初期/野菜・果物
select pg_temp._seed('初期','野菜・果物','required','バナナ',30);
-- 中期/たんぱく質
select pg_temp._seed('中期','たんぱく質','required','鶏肉(ささみ・ひき肉等)',10);
select pg_temp._seed('中期','たんぱく質','required','鮭',11);
select pg_temp._seed('中期','たんぱく質','required','ツナ缶(まぐろ水煮)',12);
select pg_temp._seed('中期','たんぱく質','required','牛乳(加熱・調理用)',13,'中期_乳グループ','any');
select pg_temp._seed('中期','たんぱく質','required','プレーンヨーグルト',14,'中期_乳グループ','any');
select pg_temp._seed('中期','たんぱく質','required','粉チーズ',15,'中期_乳グループ','any');
-- 後期/たんぱく質
select pg_temp._seed('後期','たんぱく質','required','豚肉(ひき肉等)',10);
select pg_temp._seed('後期','たんぱく質','required','かつお節',11);
select pg_temp._seed('後期','たんぱく質','required','さわら',12);
select pg_temp._seed('後期','たんぱく質','required','たら',13);
-- 完了期/たんぱく質
select pg_temp._seed('完了期','たんぱく質','required','えび',10);
select pg_temp._seed('完了期','たんぱく質','required','かに',11);
select pg_temp._seed('完了期','たんぱく質','required','さば',12);
select pg_temp._seed('完了期','たんぱく質','required','鯵',13);
select pg_temp._seed('完了期','たんぱく質','required','かじき',14);
select pg_temp._seed('完了期','たんぱく質','required','ぶり',15);
select pg_temp._seed('完了期','たんぱく質','required','しらす',16);
select pg_temp._seed('完了期','たんぱく質','required','ごま',17);
select pg_temp._seed('完了期','たんぱく質','required','ゼラチン',18);
select pg_temp._seed('完了期','たんぱく質','required','卵(加熱)',19);
select pg_temp._seed('完了期','たんぱく質','required','マヨネーズ',20);
select pg_temp._seed('完了期','たんぱく質','required','牛乳(非加熱)',21);
-- 完了期/野菜・果物
select pg_temp._seed('完了期','野菜・果物','required','オレンジ',30);
select pg_temp._seed('完了期','野菜・果物','required','りんご(加熱)',31);

-- ============ §13.4 目安食材 ============
-- 初期/穀類
select pg_temp._seed('初期','穀類','reference','米(お粥)',100);
-- 初期/たんぱく質
select pg_temp._seed('初期','たんぱく質','reference','麩',110);
-- 初期/いも・野菜・果物
select pg_temp._seed('初期','いも・野菜・果物','reference','じゃが芋',120);
select pg_temp._seed('初期','いも・野菜・果物','reference','人参',121);
select pg_temp._seed('初期','いも・野菜・果物','reference','玉ねぎ',122);
select pg_temp._seed('初期','いも・野菜・果物','reference','大根',123);
select pg_temp._seed('初期','いも・野菜・果物','reference','かぶ',124);
select pg_temp._seed('初期','いも・野菜・果物','reference','トマト',125);
select pg_temp._seed('初期','いも・野菜・果物','reference','キャベツ',126);
select pg_temp._seed('初期','いも・野菜・果物','reference','白菜',127);
select pg_temp._seed('初期','いも・野菜・果物','reference','ほうれん草',128);
select pg_temp._seed('初期','いも・野菜・果物','reference','小松菜',129);
select pg_temp._seed('初期','いも・野菜・果物','reference','チンゲン菜',130);
select pg_temp._seed('初期','いも・野菜・果物','reference','ブロッコリー',131);
select pg_temp._seed('初期','いも・野菜・果物','reference','かぼちゃ',132);
select pg_temp._seed('初期','いも・野菜・果物','reference','さつま芋',133);
-- 初期/調味料等
select pg_temp._seed('初期','調味料等','reference','片栗粉',140);
select pg_temp._seed('初期','調味料等','reference','昆布だし',141);
-- 中期/穀類
select pg_temp._seed('中期','穀類','reference','うどん',100);
select pg_temp._seed('中期','穀類','reference','そうめん',101);
select pg_temp._seed('中期','穀類','reference','マカロニ',102);
select pg_temp._seed('中期','穀類','reference','スパゲティ',103);
-- 中期/たんぱく質
select pg_temp._seed('中期','たんぱく質','reference','納豆',110);
select pg_temp._seed('中期','たんぱく質','reference','豆乳(加熱・調理用)',111);
select pg_temp._seed('中期','たんぱく質','reference','大豆水煮',112);
-- 中期/いも・野菜・果物
select pg_temp._seed('中期','いも・野菜・果物','reference','いんげん',120);
select pg_temp._seed('中期','いも・野菜・果物','reference','きゅうり',121);
select pg_temp._seed('中期','いも・野菜・果物','reference','なす',122);
select pg_temp._seed('中期','いも・野菜・果物','reference','里芋',123);
select pg_temp._seed('中期','いも・野菜・果物','reference','アスパラガス',124);
select pg_temp._seed('中期','いも・野菜・果物','reference','絹さや',125);
select pg_temp._seed('中期','いも・野菜・果物','reference','カリフラワー',126);
select pg_temp._seed('中期','いも・野菜・果物','reference','もやし',127);
select pg_temp._seed('中期','いも・野菜・果物','reference','ピーマン',128);
-- 中期/調味料等
select pg_temp._seed('中期','調味料等','reference','砂糖',140);
select pg_temp._seed('中期','調味料等','reference','しょうゆ',141);
select pg_temp._seed('中期','調味料等','reference','味噌',142);
-- 後期/穀類
select pg_temp._seed('後期','穀類','reference','ホットケーキミックス',100);
select pg_temp._seed('後期','穀類','reference','コーンフレーク',101);
select pg_temp._seed('後期','穀類','reference','小麦粉',102);
select pg_temp._seed('後期','穀類','reference','ベーキングパウダー',103);
-- 後期/いも・野菜・果物
select pg_temp._seed('後期','いも・野菜・果物','reference','野菜全般(完了期記載分を除く)',120);
select pg_temp._seed('後期','いも・野菜・果物','reference','わかめ',121);
select pg_temp._seed('後期','いも・野菜・果物','reference','ひじき',122);
select pg_temp._seed('後期','いも・野菜・果物','reference','のり',123);
select pg_temp._seed('後期','いも・野菜・果物','reference','寒天',124);
-- 後期/調味料等
select pg_temp._seed('後期','調味料等','reference','かつおだし',140);
select pg_temp._seed('後期','調味料等','reference','マーガリン',141);
select pg_temp._seed('後期','調味料等','reference','バター',142);
select pg_temp._seed('後期','調味料等','reference','酢',143);
select pg_temp._seed('後期','調味料等','reference','みりん',144);
select pg_temp._seed('後期','調味料等','reference','ケチャップ',145);
-- 完了期/穀類
select pg_temp._seed('完了期','穀類','reference','中華麺',100);
-- 完了期/たんぱく質
select pg_temp._seed('完了期','たんぱく質','reference','食肉製品',110);
select pg_temp._seed('完了期','たんぱく質','reference','魚肉練り製品',111);
select pg_temp._seed('完了期','たんぱく質','reference','大豆製品',112);
-- 完了期/いも・野菜・果物
select pg_temp._seed('完了期','いも・野菜・果物','reference','枝豆',120);
select pg_temp._seed('完了期','いも・野菜・果物','reference','ごぼう',121);
select pg_temp._seed('完了期','いも・野菜・果物','reference','たけのこ',122);
select pg_temp._seed('完了期','いも・野菜・果物','reference','とうもろこし',123);
select pg_temp._seed('完了期','いも・野菜・果物','reference','きのこ類',124);
select pg_temp._seed('完了期','いも・野菜・果物','reference','梨(加熱)',125);
select pg_temp._seed('完了期','いも・野菜・果物','reference','イチゴ',126);
select pg_temp._seed('完了期','いも・野菜・果物','reference','みかん',127);
-- 完了期/調味料等
select pg_temp._seed('完了期','調味料等','reference','サラダ油',140);
select pg_temp._seed('完了期','調味料等','reference','ごま油',141);
select pg_temp._seed('完了期','調味料等','reference','カレールウ',142);
select pg_temp._seed('完了期','調味料等','reference','煮干しだし',143);
select pg_temp._seed('完了期','調味料等','reference','さば節',144);
select pg_temp._seed('完了期','調味料等','reference','中華だし',145);
select pg_temp._seed('完了期','調味料等','reference','コンソメ',146);
select pg_temp._seed('完了期','調味料等','reference','ソース',147);
select pg_temp._seed('完了期','調味料等','reference','はちみつ',148);
