-- 330: 大和オハナ保育園 令和8年度(2026)8月分の月案(6クラス)＋個人案 seed(俊指示 2026-08-25)。
-- 添付Excel(月案 0・1歳/1・2歳/3・4・5歳)の内容を guidance_plans(月案) と
--   guidance_plan_individual_entries(個人案)に投入。全て status='draft'(下書き。承認は画面で行う)。
-- 方針(俊確認): 個人案は固有データのみ投入=はな/かぜ/つき/ほし。そら組の個人案シートは「はな組」の、
--   にじ組は「ほし組」の複製だったため個人案はスキップ(主月案のみ投入)。3・4・5歳の週別(1〜4週)欄は
--   月案テンプレに欄が無いため今回はスキップ。児童照合は在籍クラス×氏名(空白無視)で行い、未一致は NOTICE。
-- クラスは office×age_group×is_active(2026年度優先)で解決。冪等(既存は content 更新)。
do $$
declare
  v_office uuid := '9503dfbd-6cdc-424c-aa3e-ac18441478ba';
  v_year   int  := 2026;
  v_month  int  := 8;
  v_class  uuid;
  v_tmpl   uuid;
  v_plan   uuid;
  v_child  uuid;
  v_norm   text;
  rec      record;
begin
  -- ============ はな組（0歳） ============
  select id into v_class from childcare_classes
    where office_id = v_office and age_group = '0歳' and is_active
    order by (school_year = v_year) desc, school_year desc limit 1;
  if v_class is null then
    raise notice 'クラスが見つかりません: 0歳（はな）';
  else
    select id into v_tmpl from guidance_plan_templates
      where plan_type='monthly' and coalesce(age_variant,'')='age0'
      order by is_published desc, version desc limit 1;
    if v_tmpl is null then raise exception 'monthly age0 テンプレ無し(285未適用?)'; end if;
    select id into v_plan from guidance_plans
      where office_id=v_office and class_id=v_class and plan_type='monthly'
        and fiscal_year=v_year and coalesce(month,0)=v_month and week_start_date is null;
    if v_plan is null then
      insert into guidance_plans (office_id, class_id, plan_type, age_variant, template_id, fiscal_year, month, content, status)
        values (v_office, v_class, 'monthly', 'age0', v_tmpl, v_year, v_month, '{"aim": "・水の感触を感じながら遊ぶことを楽しむ\n・表情や手振りで楽しさを伝えようとする水や感触遊びを楽しみ、夏ならではの遊びに触れる", "nursing": "・沐浴、水遊びの際は、体調や個々の発達に合わせた遊び方をする。\n・あせもやおむつかぶれに留意し、着替えや沐浴で清潔を保つようにする。", "$子育て支援$": "・感染症などの症状が見られた時は、早めの受診をしてもらえるように話をする\n・汗をかき、服が汚れやすい時期なので、着替えの衣服を多めに用意してもらう", "$保育の実施に関わる配慮事項$": "沐浴の際は子どもから決して目を離さず、安全管理や保育士の役割について確認をとりながら行う", "healthygrow*aim": "褒められたり励ましてもらいながら、楽しく食事をする。\n夏の暑さに負けず健康的に過ごす。", "healthygrow*content": "水分補給や休息をこまめに取り、暑い夏を元気に過ごす", "healthygrow*$内容の取り扱い$": "活動の前後にこまめに水分補給をし、快適な環境の中で休息をとる", "withfeelings*aim": "保育士と触れ合い，安定感を持って遊ぶ\n特定の保育者に愛着を持ち、リラックスして過ごす。", "withfeelings*content": "気温の高い日には室内のプレイマットやボールプール等で体を十分に動かしていく。", "withfeelings*$内容の取り扱い$": "保育士と触れ合いながら自分の好きな遊びを十分に味わえるようにする", "sensitivity*aim": "・保育士に見守られながら、喜んでつかまり立ちや伝い歩きをする。", "sensitivity*content": "はいはい、伝え歩き、手つなぎ歩き、歩行等、個々の発達に合った動きを存分に行う。", "sensitivity*$内容の取り扱い$": "・体操の曲や手遊び歌など様々な音楽を流して興味を持てるようにする。", "health*aim": "・ 保育士に見守られながらお座りをして遊ぶことを楽しむ\n ・特定の保育士とので関わりの中で、安心して過ごす", "health*content": "・沐浴をした後は十分に休息を取る。", "health*$内容の取り扱い$": "室温を適温に設定したり、水遊びをしたり沐浴をしたりして、暑い夏を心地良く過ごせるようにする。", "relations*aim": "・保育士に見守られながら、喜んでつかまり立ちや伝い歩きをする。", "relations*content": "保育者と簡単な言葉でやり取りをしたり、名前を呼ばれて笑顔で反応をしたりする。", "relations*$内容の取り扱い$": "子どもの思いを受け止め安心感を与えられる様にする", "environment*aim": "・伝い歩きなど、十分に体を動かして遊ぶ。\n・食事の時間を楽しみにし、食べることに興味を持つ。", "environment*content": "ハイハイや伝い歩きなどで動き回り、口や手で探索行動を楽しむ。", "environment*$内容の取り扱い$": "・水の感触を十分に楽しめるように道具を用意したり遊び方の工夫をする。", "lang*aim": "・呼びかけに反応したり手振りで返事したりする。", "lang*content": "言葉のくり返しのある絵本を見て楽しさを知り、言葉を覚えていく。", "lang*$内容の取り扱い$": "・喃語や発語のタイミングを逃さないように、ゆっくり話しかけたり聞いたりする。", "expression*aim": "・水の感触を感じながら遊ぶことを楽しむ\n・表情や手振りで楽しさを伝えようとする", "expression*content": "水、氷などにふれて遊ぶ。", "expression*$内容の取り扱い$": "・同じ動きでも個々の月齢に合わせた声掛けや動作をしていき安全に考慮し広いスペースでのびのびと身体を動かして遊べるような環境作りをする。"}'::jsonb, 'draft')
        returning id into v_plan;
    else
      update guidance_plans set content='{"aim": "・水の感触を感じながら遊ぶことを楽しむ\n・表情や手振りで楽しさを伝えようとする水や感触遊びを楽しみ、夏ならではの遊びに触れる", "nursing": "・沐浴、水遊びの際は、体調や個々の発達に合わせた遊び方をする。\n・あせもやおむつかぶれに留意し、着替えや沐浴で清潔を保つようにする。", "$子育て支援$": "・感染症などの症状が見られた時は、早めの受診をしてもらえるように話をする\n・汗をかき、服が汚れやすい時期なので、着替えの衣服を多めに用意してもらう", "$保育の実施に関わる配慮事項$": "沐浴の際は子どもから決して目を離さず、安全管理や保育士の役割について確認をとりながら行う", "healthygrow*aim": "褒められたり励ましてもらいながら、楽しく食事をする。\n夏の暑さに負けず健康的に過ごす。", "healthygrow*content": "水分補給や休息をこまめに取り、暑い夏を元気に過ごす", "healthygrow*$内容の取り扱い$": "活動の前後にこまめに水分補給をし、快適な環境の中で休息をとる", "withfeelings*aim": "保育士と触れ合い，安定感を持って遊ぶ\n特定の保育者に愛着を持ち、リラックスして過ごす。", "withfeelings*content": "気温の高い日には室内のプレイマットやボールプール等で体を十分に動かしていく。", "withfeelings*$内容の取り扱い$": "保育士と触れ合いながら自分の好きな遊びを十分に味わえるようにする", "sensitivity*aim": "・保育士に見守られながら、喜んでつかまり立ちや伝い歩きをする。", "sensitivity*content": "はいはい、伝え歩き、手つなぎ歩き、歩行等、個々の発達に合った動きを存分に行う。", "sensitivity*$内容の取り扱い$": "・体操の曲や手遊び歌など様々な音楽を流して興味を持てるようにする。", "health*aim": "・ 保育士に見守られながらお座りをして遊ぶことを楽しむ\n ・特定の保育士とので関わりの中で、安心して過ごす", "health*content": "・沐浴をした後は十分に休息を取る。", "health*$内容の取り扱い$": "室温を適温に設定したり、水遊びをしたり沐浴をしたりして、暑い夏を心地良く過ごせるようにする。", "relations*aim": "・保育士に見守られながら、喜んでつかまり立ちや伝い歩きをする。", "relations*content": "保育者と簡単な言葉でやり取りをしたり、名前を呼ばれて笑顔で反応をしたりする。", "relations*$内容の取り扱い$": "子どもの思いを受け止め安心感を与えられる様にする", "environment*aim": "・伝い歩きなど、十分に体を動かして遊ぶ。\n・食事の時間を楽しみにし、食べることに興味を持つ。", "environment*content": "ハイハイや伝い歩きなどで動き回り、口や手で探索行動を楽しむ。", "environment*$内容の取り扱い$": "・水の感触を十分に楽しめるように道具を用意したり遊び方の工夫をする。", "lang*aim": "・呼びかけに反応したり手振りで返事したりする。", "lang*content": "言葉のくり返しのある絵本を見て楽しさを知り、言葉を覚えていく。", "lang*$内容の取り扱い$": "・喃語や発語のタイミングを逃さないように、ゆっくり話しかけたり聞いたりする。", "expression*aim": "・水の感触を感じながら遊ぶことを楽しむ\n・表情や手振りで楽しさを伝えようとする", "expression*content": "水、氷などにふれて遊ぶ。", "expression*$内容の取り扱い$": "・同じ動きでも個々の月齢に合わせた声掛けや動作をしていき安全に考慮し広いスペースでのびのびと身体を動かして遊べるような環境作りをする。"}'::jsonb, template_id=v_tmpl, age_variant='age0' where id=v_plan;
    end if;
    -- 個人案(はな・6名)
    for rec in select * from (values
      ('北島楓', '{"kidsstate": "・つかまり立ちが安定してくる。\n・『いないいないばぁ』言うと、顔を隠して簡単なやり取りを保育士と楽しんでいる。", "aim": "・保育士と一緒に体を動かす事を楽しむ。\n・沐浴を通して清潔を保ち、心地よく過ごす", "consideration": "・マットやトンネルなどを活用し、這う・くぐる等の動きが楽しめる環境を整える。\n・十分な活動スペースを確保し、転倒や衝突等に配慮して安全に遊べるようにする。\n・沐浴前後の体温や顔色等、健康状態を確認して行う。", "reflection": "・沐浴後少量だが吐き戻す事が何度かある。体温が高かったり顔色などもいつもと変わりない様子である。\n・運動会リハーサルは笑顔で参加し、保育士とふれあい体操をたのしんでいた。ハイハイレースは、部屋だと特定（担任）の保育士に向かって進んでいたが、リハーサルの際は人見知りからか泣く姿が見られた。"}'::jsonb),
      ('川上慧翔', '{"kidsstate": "・座った状態を維持できるようになり、腹ばいの体制で前後に動くなど活発な行動ができるようになる。", "aim": "・発達に応じた運動遊びをしていく中で、十分に体を動かす。\n・決まった時間に眠り、生活リズムを整える。", "consideration": "・トンネル遊びや、ハイハイなど体を動かせる環境を整え、運動遊びを楽しめるようにする。\n・眠たくなるタイミングを逃さずスムーズに入眠に誘えるようにしていき、無理のないリズムをつくっていく。", "reflection": "•体調を合わせて午前寝の時間をコントロールするよう心がけた。時間の調節をすることで午睡もスムーズに入眠できるようになってきている。\n•体調を崩して休む事も多かったが、園生活では元気に過ごす姿が見られた。つかまり立ちをしたいようで保育士の膝元やパーテーションにつかまり力を入れている事が多い。怪我のないよう安全面に配慮しながら保育にあたりたい。"}'::jsonb),
      ('水嶋楽波', '{"kidsstate": "・つかまり立ちが盛んで、立ったり座ったりの繰り返しを楽しんだり、バランスを崩しながらも1人で立とうと挑戦する姿が見られるようになる。\n・体を動かす活動に興味を持ち、笑顔を見せて遊ぶようになる。\n・少しずつ食べることに意欲的になり、掴み食べもすすむ。", "aim": "・発達に応じた運動遊びをしていく中で、十分に体を動かす。\n・ミルク卒業と同時に完了食の食事に慣れ、喜んで食べる。", "consideration": "・トンネル遊びや、ハイハイなど体を動かせる環境を整え、運動遊びを楽しめるようにする。\n・皿に適量取り分けて、口に運ぶ量・速さを見守る。", "reflection": "•つかまり立ちや伝い歩きを楽しむ姿が見られる。\n•おやつを好み、積極的につかみ食べをする姿が見られる。お給食ではだいたい量食べ満足すると、途中から気が逸れてしまいがちで椅子から強引に降りようとすることが多かった。"}'::jsonb),
      ('福嶺詩季', '{"kidsstate": "・一人で立ち上がり、一歩を踏み出そうとする。\n・生活リズムが整い初め、午前寝無しでも過ごせる日が増えてくる。\n・苦手な食べ物は口から出したり、嫌がる様子を見せたりする。", "aim": "・手づかみやスプーンを使って自分で食べようとする。\n ・保育士の手を借りて数歩ずつ歩く事を楽しむ。", "consideration": "・スプーンや手づかみしやすい大きさ・硬さの食材を用意し、自分で食べやすい環境を整える。\n・導線に玩具や荷物を置かず、見通しのよい空間を確保する。", "reflection": "・月初め食事を介助すると嫌がって食べない事が増えてきているので、別皿に少量づつ配膳してつかみ食べを促すが、全部床に落としてしまう。スプーンやコップを持たせて、その間に口まで運ぶと食べる事ができる。・一人で歩く歩数が増えているが、まだ安定しない為保育士が横につき、安全に歩行を行った。"}'::jsonb),
      ('吾妻飛和', '{"kidsstate": "『いただきます』の挨拶の時、お辞儀をする事ができる。\n・歩行の歩数が増えて、部屋を歩き楽しむ姿が見られる。", "aim": "・手づかみやスプーンを使い自分で食べようとする。\n・歌や手遊び・ふれあい遊びを楽しむ。", "consideration": "・自分で食べやすい大きさを、小皿に少量づつ入れて、一気食べしないように配慮する。\n・保育士が笑顔でゆったり関わり、安心して参加できるようにする。\n・手拍子や体を揺らすなど子どもの反応を認めながら、意欲的に繋げる。", "reflection": "・つかみやすい食材の際、本児の食べやすい大きさにしてお皿に置いておくと、手づかみで食べることができる。月初めは食事があまり進まず、途中から口をとじたり首を横に振り食べない事を表現していた。中旬あたりからは、汁物しか飲まなかった為、本児の様子を見ながら、量などは調整した。・"}'::jsonb),
      ('樋口葵', '{"kidsstate": "・意欲的に手づかみ食べをして口に運べるようになる。\n・1人でその場に立ち、数歩前に出ようと挑戦する。", "aim": "・食事の時間を楽しみにする。\n・立つ、座るなどの動きや姿勢を楽しむ中で、手放し状態の1人立ちに挑戦する。", "consideration": "・リラックスして食事を楽しむことができるよう「おいしいね」など声をかけていきゆっくりと食事を進める。\n・転倒など起こらないよう傍で見守り安全面に十分配慮する。", "reflection": "•食事の時間は残す事なくよく食べているが、咀嚼をあまりしてないようで、口に入れるとすぐに飲み込んでしまう為口に入れる量の調節を行なった。\n•手放しで立つことを楽しんでおり繰り返し1人で立とうとするが、前に進もうとすることはまだ難しいようであった。"}'::jsonb)
    ) as t(nm, content) loop
      v_norm := regexp_replace(rec.nm, '[[:space:]　]', '', 'g');
      select ch.id into v_child from children ch
        join child_class_enrollments e on e.child_id = ch.id and e.class_id = v_class and e.effective_end_date is null
        where ch.office_id = v_office
          and (regexp_replace(ch.display_name,'[[:space:]　]','','g') = v_norm
               or regexp_replace(ch.full_name,'[[:space:]　]','','g') = v_norm)
        limit 1;
      if v_child is null then
        raise notice '個人案: 児童が見つかりません(はな): %', rec.nm;
      else
        insert into guidance_plan_individual_entries (plan_id, child_id, content)
          values (v_plan, v_child, rec.content)
          on conflict (plan_id, child_id) do update set content = excluded.content, updated_at = now();
      end if;
    end loop;
  end if;


  -- ============ そら組（1歳） ============
  select id into v_class from childcare_classes
    where office_id = v_office and age_group = '1歳' and is_active
    order by (school_year = v_year) desc, school_year desc limit 1;
  if v_class is null then
    raise notice 'クラスが見つかりません: 1歳（そら）';
  else
    select id into v_tmpl from guidance_plan_templates
      where plan_type='monthly' and coalesce(age_variant,'')='age1plus'
      order by is_published desc, version desc limit 1;
    if v_tmpl is null then raise exception 'monthly age1plus テンプレ無し(285未適用?)'; end if;
    select id into v_plan from guidance_plans
      where office_id=v_office and class_id=v_class and plan_type='monthly'
        and fiscal_year=v_year and coalesce(month,0)=v_month and week_start_date is null;
    if v_plan is null then
      insert into guidance_plans (office_id, class_id, plan_type, age_variant, template_id, fiscal_year, month, content, status)
        values (v_office, v_class, 'monthly', 'age1plus', v_tmpl, v_year, v_month, '{"aim": "・夏ならではの遊びを十分に楽しみ、開放感を味わう\n・保育士と一緒に簡単な身の回りのことを少しずつ自分でしようとする。", "nursing": "・涼しく安全な環境を整えた中で、快適に過ごせるようにする。\n・着替えの際には自ら腕をあげたり、袖に通そうとしたりしようとし、保育士が手伝いながら意欲的に着替えられるようにする。", "$子育て支援$": "・暑さや家族との外出で生活リズムが乱れ、疲れが出やすいため、ゆったりと過ごせる時間を持って生活リズムに気をつけて過ごしてもらうよう声をかけていく。", "$保育の実施に関わる配慮事項$": "・遊びの後には十分な休息と水分補給を心がける。また室内の通気を良くしクーラーを使用するときは外気温との差に注意する。\n・着替えの際には子どもが着替えようとする姿を認め、一緒に着替えを進められるようにする。", "health*aim": "・1つの遊びをじっくり楽しむ\n・熱中指数を読み取りながら、戸外遊びをする時は安全性を優先して活動する。", "health*content": "・暑い夏を一人ひとりが心地よく過ごせるように、適切な空調温度管理、休憩、水分補給を行うなど、健康に留意する。\n・熱中指数を読み取りながら、戸外遊びをする時は安全性を優先して活動する。", "health*$内容の取り扱い$": "・水分補給をするとともに子どもの健康状態をしっかりと把握し、体調の変化を見逃さないようにする。", "relations*aim": "・身の回りの物や人に関心を持ち、名称や他児の名前を覚える。", "relations*content": "保育教諭と一緒に好きなあそびを楽しみ、友だちとも十分にかかわってあそぶ。", "relations*$内容の取り扱い$": "・保育教諭が仲立ちしながら、友だちとのやり取りが多く持てるようにする。", "environment*aim": "・夏の暑さに負けずに健康に過ごす。\n・自分でできたことが増え、やってみようと挑戦する。", "environment*content": "・水遊びをして水に親しみを持ち、冷たい感覚や気持ち良さを感じる", "environment*$内容の取り扱い$": "・水の感触を安全に楽しめるよう、個々の様子を見て誘いかける。\n衛生面において、保育教諭・子どもともに手洗い、消毒をしっかりと行う。", "lang*aim": "・簡単な言葉を覚え、自分なりに思いを伝えようとする。", "lang*content": "興味のある絵本を見る姿が見られる。", "lang*$内容の取り扱い$": "・子どもが真似しやすそうな言葉や絵本などを通して一緒にいうことを楽しみながら発語へと繋げていく。", "expression*aim": "保育者や友だちと一緒に、水や泥の感触の違いを楽しんだり、冷たい感触の心地よさを知ったりする。", "expression*content": "水に関心をもち、試行錯誤しながらじっくり遊びこむ中で、水の特徴などに気づいていく。", "expression*$内容の取り扱い$": "保育教諭も体いっぱいに表現する。"}'::jsonb, 'draft')
        returning id into v_plan;
    else
      update guidance_plans set content='{"aim": "・夏ならではの遊びを十分に楽しみ、開放感を味わう\n・保育士と一緒に簡単な身の回りのことを少しずつ自分でしようとする。", "nursing": "・涼しく安全な環境を整えた中で、快適に過ごせるようにする。\n・着替えの際には自ら腕をあげたり、袖に通そうとしたりしようとし、保育士が手伝いながら意欲的に着替えられるようにする。", "$子育て支援$": "・暑さや家族との外出で生活リズムが乱れ、疲れが出やすいため、ゆったりと過ごせる時間を持って生活リズムに気をつけて過ごしてもらうよう声をかけていく。", "$保育の実施に関わる配慮事項$": "・遊びの後には十分な休息と水分補給を心がける。また室内の通気を良くしクーラーを使用するときは外気温との差に注意する。\n・着替えの際には子どもが着替えようとする姿を認め、一緒に着替えを進められるようにする。", "health*aim": "・1つの遊びをじっくり楽しむ\n・熱中指数を読み取りながら、戸外遊びをする時は安全性を優先して活動する。", "health*content": "・暑い夏を一人ひとりが心地よく過ごせるように、適切な空調温度管理、休憩、水分補給を行うなど、健康に留意する。\n・熱中指数を読み取りながら、戸外遊びをする時は安全性を優先して活動する。", "health*$内容の取り扱い$": "・水分補給をするとともに子どもの健康状態をしっかりと把握し、体調の変化を見逃さないようにする。", "relations*aim": "・身の回りの物や人に関心を持ち、名称や他児の名前を覚える。", "relations*content": "保育教諭と一緒に好きなあそびを楽しみ、友だちとも十分にかかわってあそぶ。", "relations*$内容の取り扱い$": "・保育教諭が仲立ちしながら、友だちとのやり取りが多く持てるようにする。", "environment*aim": "・夏の暑さに負けずに健康に過ごす。\n・自分でできたことが増え、やってみようと挑戦する。", "environment*content": "・水遊びをして水に親しみを持ち、冷たい感覚や気持ち良さを感じる", "environment*$内容の取り扱い$": "・水の感触を安全に楽しめるよう、個々の様子を見て誘いかける。\n衛生面において、保育教諭・子どもともに手洗い、消毒をしっかりと行う。", "lang*aim": "・簡単な言葉を覚え、自分なりに思いを伝えようとする。", "lang*content": "興味のある絵本を見る姿が見られる。", "lang*$内容の取り扱い$": "・子どもが真似しやすそうな言葉や絵本などを通して一緒にいうことを楽しみながら発語へと繋げていく。", "expression*aim": "保育者や友だちと一緒に、水や泥の感触の違いを楽しんだり、冷たい感触の心地よさを知ったりする。", "expression*content": "水に関心をもち、試行錯誤しながらじっくり遊びこむ中で、水の特徴などに気づいていく。", "expression*$内容の取り扱い$": "保育教諭も体いっぱいに表現する。"}'::jsonb, template_id=v_tmpl, age_variant='age1plus' where id=v_plan;
    end if;
  end if;


  -- ============ かぜ組（2歳） ============
  select id into v_class from childcare_classes
    where office_id = v_office and age_group = '2歳' and is_active
    order by (school_year = v_year) desc, school_year desc limit 1;
  if v_class is null then
    raise notice 'クラスが見つかりません: 2歳（かぜ）';
  else
    select id into v_tmpl from guidance_plan_templates
      where plan_type='monthly' and coalesce(age_variant,'')='age1plus'
      order by is_published desc, version desc limit 1;
    if v_tmpl is null then raise exception 'monthly age1plus テンプレ無し(285未適用?)'; end if;
    select id into v_plan from guidance_plans
      where office_id=v_office and class_id=v_class and plan_type='monthly'
        and fiscal_year=v_year and coalesce(month,0)=v_month and week_start_date is null;
    if v_plan is null then
      insert into guidance_plans (office_id, class_id, plan_type, age_variant, template_id, fiscal_year, month, content, status)
        values (v_office, v_class, 'monthly', 'age1plus', v_tmpl, v_year, v_month, '{"aim": "夏の遊びや行事に興味を持ち、季節を感じながら楽しむ。", "nursing": "・こまめに水分補給をし、気温や子どもの状態によって活動時間を変更したり休憩を入れたりする。\n\n・長期の休み明けは、特に個々の健康状態に気を配る。", "$子育て支援$": "・汗をかきやすい時期なので、着替えを多めに用意してもらう。\n・暑さや疲れなどから食欲減退や睡眠不足 など体調を崩す前兆がないか家庭での様子を聞く。", "$保育の実施に関わる配慮事項$": "・暑さから体調を崩しやすいので、一人ひとりの状態をよく観察し報告し合う。\n\n・プールで危険のないよう配置に気をつけながら声を掛け合っていく。", "health*aim": "健康  ・自分からあるいは保育士に声を掛けてもらいながらトイレへ行き、排泄をする。", "health*content": "トイレトレーニングの子は、自ら保育士に尿意を伝えトイレに行く。オムツの子は、オムツに出ている出ていないを自分で感じ保育士に伝える。", "health*$内容の取り扱い$": "・トイレで排泄できた場合はたくさん褒め、間隔を確認しながらトレーニングパンツに移行できる様に援助していく。", "relations*aim": "遊びを通して友だちと関わる。", "relations*content": "友だちと順番や物の取り合いなどでトラブルになることはあるが、一緒に遊ぶ楽しさにも気づく。", "relations*$内容の取り扱い$": "ルールのある遊びをみんなで楽しめるよう工夫したり、友だちと関わり遊べるような声掛けや環境作りをしていく。", "environment*aim": "・水の感触を楽しみながらプール遊びを楽しむ。", "environment*content": "•全身をダイナミックに使って、夏ならではのプール遊びなどを楽しむ。", "environment*$内容の取り扱い$": "•水遊びをする前に、周囲を点検し、危ないものが落ちていないか、道具などが壊れていないかを確認する。", "lang*aim": "絵本に興味を持ち、出てくる言葉を楽しむ。", "lang*content": "・気に入った絵本を集中して見たり、繰り返し読み聞かせてもらう。", "lang*$内容の取り扱い$": "・少しずつ長いストーリーの絵本にも親しみ、楽しめる様にしていく。", "expression*aim": "・リズムに合わせて体を動かす事を楽しむ。", "expression*content": "音楽に合わせて、身体を使って静と動などの様々な表現を楽しむ。", "expression*$内容の取り扱い$": "準備体操やリズム遊びなどして、楽しんで身体を動かせる様にする。"}'::jsonb, 'draft')
        returning id into v_plan;
    else
      update guidance_plans set content='{"aim": "夏の遊びや行事に興味を持ち、季節を感じながら楽しむ。", "nursing": "・こまめに水分補給をし、気温や子どもの状態によって活動時間を変更したり休憩を入れたりする。\n\n・長期の休み明けは、特に個々の健康状態に気を配る。", "$子育て支援$": "・汗をかきやすい時期なので、着替えを多めに用意してもらう。\n・暑さや疲れなどから食欲減退や睡眠不足 など体調を崩す前兆がないか家庭での様子を聞く。", "$保育の実施に関わる配慮事項$": "・暑さから体調を崩しやすいので、一人ひとりの状態をよく観察し報告し合う。\n\n・プールで危険のないよう配置に気をつけながら声を掛け合っていく。", "health*aim": "健康  ・自分からあるいは保育士に声を掛けてもらいながらトイレへ行き、排泄をする。", "health*content": "トイレトレーニングの子は、自ら保育士に尿意を伝えトイレに行く。オムツの子は、オムツに出ている出ていないを自分で感じ保育士に伝える。", "health*$内容の取り扱い$": "・トイレで排泄できた場合はたくさん褒め、間隔を確認しながらトレーニングパンツに移行できる様に援助していく。", "relations*aim": "遊びを通して友だちと関わる。", "relations*content": "友だちと順番や物の取り合いなどでトラブルになることはあるが、一緒に遊ぶ楽しさにも気づく。", "relations*$内容の取り扱い$": "ルールのある遊びをみんなで楽しめるよう工夫したり、友だちと関わり遊べるような声掛けや環境作りをしていく。", "environment*aim": "・水の感触を楽しみながらプール遊びを楽しむ。", "environment*content": "•全身をダイナミックに使って、夏ならではのプール遊びなどを楽しむ。", "environment*$内容の取り扱い$": "•水遊びをする前に、周囲を点検し、危ないものが落ちていないか、道具などが壊れていないかを確認する。", "lang*aim": "絵本に興味を持ち、出てくる言葉を楽しむ。", "lang*content": "・気に入った絵本を集中して見たり、繰り返し読み聞かせてもらう。", "lang*$内容の取り扱い$": "・少しずつ長いストーリーの絵本にも親しみ、楽しめる様にしていく。", "expression*aim": "・リズムに合わせて体を動かす事を楽しむ。", "expression*content": "音楽に合わせて、身体を使って静と動などの様々な表現を楽しむ。", "expression*$内容の取り扱い$": "準備体操やリズム遊びなどして、楽しんで身体を動かせる様にする。"}'::jsonb, template_id=v_tmpl, age_variant='age1plus' where id=v_plan;
    end if;
    -- 個人案(かぜ・10名)
    for rec in select * from (values
      ('池田和心', '{"kidsstate": "・モゾモゾしながらもうんちが出そうと自ら言う姿が見られるようになってきた。", "aim": "・便意を自ら伝える。", "consideration": "・本人がムズムズしている際はこちらから声をかける。また、教えてくれた際は褒める。"}'::jsonb),
      ('佐藤奈緒', '{"kidsstate": "・ものを受け取る際などに自ら言える事が増えてきた。", "aim": "・自らありがとうが言えるようになる", "consideration": "・ものを受け取る際などに一緒になって言うようにしたり言うタイミング等を教えていく。"}'::jsonb),
      ('佐藤世梛', '{"kidsstate": "・だんだんと名前を呼ばれると反応する事が増えてきた。", "aim": "・名前を呼ばれると返事をする。", "consideration": "・活動の際などに名前を呼び返事をする場面を作る。"}'::jsonb),
      ('水嶋笑波', '{"kidsstate": "・涙する場面もあるが、「いや」「やめて」「かして」など、簡単な言葉が伝えられるようになってきた。", "aim": "・自分の気持ちを言葉やしぐさで相手に伝えられるようになる。", "consideration": "・子どもの気持ちを代弁し、「いやだったね、やめてって言ってみようか。」ときっかけをつくる。\n・伝えられた時には大いに褒める。"}'::jsonb),
      ('田口穂乃榎', '{"kidsstate": "・保育者に尿意を伝え、トイレへ向かうことができるようになった。", "aim": "・尿意を感じた際は、自分から保育者に伝え、トイレへ行こうとする。", "consideration": "・「トイレに行きたい。」と伝えられた時はすぐに受け止め、安心して排泄できるように関わる。"}'::jsonb),
      ('佐藤創真', '{"kidsstate": "・保育者の声かけを受けながら、相手が嫌がる行動を控え、適切に関わる事ができるようになった。", "aim": "・相手が嫌がる行動を控え、適切な関わり方ができるようになる。", "consideration": "・相手が嫌な気持ちになることを、その場で短く分かりやすい言葉で伝える。"}'::jsonb),
      ('須藤　斗偉', '{"kidsstate": "・保育者の声かけを受けながら、相手が嫌がる行動を控え、適切に関わる事ができるようになった。", "aim": "・相手が嫌がる行動を控え、適切な関わり方ができるようになる。", "consideration": "・相手が嫌な気持ちになることを、その場で短く分かりやすい言葉で伝える。"}'::jsonb),
      ('市村珠梨', '{"kidsstate": "・排尿後は自分で気づいて、すぐにトイレットペーパーで拭くことができるようになった。", "aim": "・排尿後は自分で気づいて、すぐにトイレットペーパーで拭くことができるようになる。", "consideration": "・排尿後は「拭こうね」とその都度声をかけ、自分で拭けたことを褒めながら習慣化につなげる。"}'::jsonb),
      ('五十嵐愛笑', '{"kidsstate": "・排尿後は自分で気づいて、すぐにトイレットペーパーで拭くことができるようになった。", "aim": "・排尿後は自分で気づいて、すぐにトイレットペーパーで拭くことができるようになる。", "consideration": "・排尿後は「拭こうね」とその都度声をかけ、自分で拭けたことを褒めながら習慣化につなげる。"}'::jsonb),
      ('樋口凪咲', '{"kidsstate": "・落ち着きがない姿も見られるが、楽しんで過ごす事ができた。", "aim": "・保育園での生活リズムを取り戻す。", "consideration": "・先月は体調不良での欠席が多かった為、本人のペースに寄り添いながらもリズムを取り戻せるよう促していく。", "reflection": "・今月もお盆期間があったこともあり数回しか登園できなかった。"}'::jsonb)
    ) as t(nm, content) loop
      v_norm := regexp_replace(rec.nm, '[[:space:]　]', '', 'g');
      select ch.id into v_child from children ch
        join child_class_enrollments e on e.child_id = ch.id and e.class_id = v_class and e.effective_end_date is null
        where ch.office_id = v_office
          and (regexp_replace(ch.display_name,'[[:space:]　]','','g') = v_norm
               or regexp_replace(ch.full_name,'[[:space:]　]','','g') = v_norm)
        limit 1;
      if v_child is null then
        raise notice '個人案: 児童が見つかりません(かぜ): %', rec.nm;
      else
        insert into guidance_plan_individual_entries (plan_id, child_id, content)
          values (v_plan, v_child, rec.content)
          on conflict (plan_id, child_id) do update set content = excluded.content, updated_at = now();
      end if;
    end loop;
  end if;


  -- ============ つき組（3歳） ============
  select id into v_class from childcare_classes
    where office_id = v_office and age_group = '3歳' and is_active
    order by (school_year = v_year) desc, school_year desc limit 1;
  if v_class is null then
    raise notice 'クラスが見つかりません: 3歳（つき）';
  else
    select id into v_tmpl from guidance_plan_templates
      where plan_type='monthly' and coalesce(age_variant,'')='age1plus'
      order by is_published desc, version desc limit 1;
    if v_tmpl is null then raise exception 'monthly age1plus テンプレ無し(285未適用?)'; end if;
    select id into v_plan from guidance_plans
      where office_id=v_office and class_id=v_class and plan_type='monthly'
        and fiscal_year=v_year and coalesce(month,0)=v_month and week_start_date is null;
    if v_plan is null then
      insert into guidance_plans (office_id, class_id, plan_type, age_variant, template_id, fiscal_year, month, content, status)
        values (v_office, v_class, 'monthly', 'age1plus', v_tmpl, v_year, v_month, '{"aim": "・夏ならではの遊びを、保育士や友だちと一緒に楽しむ。\n・遊びを通して友達とかかわり、自分の気持ちを言葉で伝えようとする。", "nursing": "・一人一人の健康状態を把握し、暑さによる疲れが出ないよう、十分な水分補給と休息をとれるようにする。\n・身の回りのことや生活の仕方など一人一人に応じて援助し、意欲や自信を育む。", "$子育て支援$": "・暑さによる疲れから体調を崩さないために、規則正しい生活を送るよう、協力をお願いする。\n・活動や遊びで汗をかくことも多いので、着替えの補充をお願いする。", "$保育の実施に関わる配慮事項$": "・活動と遊び、休息や午睡時などの時間配分を行い、生活リズムを整えていく。こまめの水分補給の声掛けをし、更に午睡の大切さを知らせ、安心して入眠出来るようにしていく。", "health*aim": "・夏の生活の仕方が分かり、身の回りのことを自分でしようとする。", "health*content": "・汗の始末や衣服の調節を保育士に促されながら自分で行い、十分な水分、休息をとる。", "health*$内容の取り扱い$": "・着替えなどは自分で出来るようにやりやすいやり方を知らせ、なるべく見守り、「自分で出来た」という喜びが意欲に繋がるようにする。", "relations*aim": "・気の合う友達と好きな遊びを楽しむ。", "relations*content": "・気の合う友達との関わりが増え、会話を楽しみながらごっこ遊びを一緒にする。", "relations*$内容の取り扱い$": "・友だちとの関わりが増える一方で、トラブルになった時は、お互いの思いを理解した上で、丁寧にかかわりながら仲立ちをする。", "environment*aim": "・プールに入り、水に触れて感触を楽しむ。", "environment*content": "・水の気持ち良さを味わい、プール遊びを楽しむ。", "environment*$内容の取り扱い$": "・水に対して恐怖心が芽生えないように楽しく安全に触れられるように援助していく。", "lang*aim": "・生活や遊びに必要な言葉を知り伝えていく。", "lang*content": "・「ありがとう」「ごめんね」「おはようございます」「さようなら」等自ら進んで相手に伝えようとする。", "lang*$内容の取り扱い$": "・生活に必要な言葉、会話を繰り返し伝え、伝えられた時には大いに褒め、自信が持てるようにする。", "expression*aim": "・運動会練習に積極的に参加する。", "expression*content": "・自分の位置や振り付けを覚え、楽しみながら運動会の練習を行う。", "expression*$内容の取り扱い$": "・子どもたちが楽しんで練習できるような声掛けを心がけ、集中力が続くよう時間も配慮する。"}'::jsonb, 'draft')
        returning id into v_plan;
    else
      update guidance_plans set content='{"aim": "・夏ならではの遊びを、保育士や友だちと一緒に楽しむ。\n・遊びを通して友達とかかわり、自分の気持ちを言葉で伝えようとする。", "nursing": "・一人一人の健康状態を把握し、暑さによる疲れが出ないよう、十分な水分補給と休息をとれるようにする。\n・身の回りのことや生活の仕方など一人一人に応じて援助し、意欲や自信を育む。", "$子育て支援$": "・暑さによる疲れから体調を崩さないために、規則正しい生活を送るよう、協力をお願いする。\n・活動や遊びで汗をかくことも多いので、着替えの補充をお願いする。", "$保育の実施に関わる配慮事項$": "・活動と遊び、休息や午睡時などの時間配分を行い、生活リズムを整えていく。こまめの水分補給の声掛けをし、更に午睡の大切さを知らせ、安心して入眠出来るようにしていく。", "health*aim": "・夏の生活の仕方が分かり、身の回りのことを自分でしようとする。", "health*content": "・汗の始末や衣服の調節を保育士に促されながら自分で行い、十分な水分、休息をとる。", "health*$内容の取り扱い$": "・着替えなどは自分で出来るようにやりやすいやり方を知らせ、なるべく見守り、「自分で出来た」という喜びが意欲に繋がるようにする。", "relations*aim": "・気の合う友達と好きな遊びを楽しむ。", "relations*content": "・気の合う友達との関わりが増え、会話を楽しみながらごっこ遊びを一緒にする。", "relations*$内容の取り扱い$": "・友だちとの関わりが増える一方で、トラブルになった時は、お互いの思いを理解した上で、丁寧にかかわりながら仲立ちをする。", "environment*aim": "・プールに入り、水に触れて感触を楽しむ。", "environment*content": "・水の気持ち良さを味わい、プール遊びを楽しむ。", "environment*$内容の取り扱い$": "・水に対して恐怖心が芽生えないように楽しく安全に触れられるように援助していく。", "lang*aim": "・生活や遊びに必要な言葉を知り伝えていく。", "lang*content": "・「ありがとう」「ごめんね」「おはようございます」「さようなら」等自ら進んで相手に伝えようとする。", "lang*$内容の取り扱い$": "・生活に必要な言葉、会話を繰り返し伝え、伝えられた時には大いに褒め、自信が持てるようにする。", "expression*aim": "・運動会練習に積極的に参加する。", "expression*content": "・自分の位置や振り付けを覚え、楽しみながら運動会の練習を行う。", "expression*$内容の取り扱い$": "・子どもたちが楽しんで練習できるような声掛けを心がけ、集中力が続くよう時間も配慮する。"}'::jsonb, template_id=v_tmpl, age_variant='age1plus' where id=v_plan;
    end if;
    -- 個人案(つき・4名)
    for rec in select * from (values
      ('野口真臣', '{"aim": "安心できる環境の中で遊びを楽しむ", "consideration": "好きな遊びを十分に保障する\n・成功しやすい活動を設定\n・気持ちが安定する環境を優先\n・刺激が強すぎないよう調整"}'::jsonb),
      ('北島樹', '{"kidsstate": "・言葉よりも手足で先に相手に伝える。", "aim": "・自分の思いを言葉で伝えられるようにする。", "consideration": "・本児の気持ちを受け止めながらも言葉で知らせていけるように促す。"}'::jsonb),
      ('稲葉湊斗', '{"kidsstate": "・保育士の指示が理解出来ず、他児とは別の行動をしてしまう。", "aim": "・保育士の話を聞いて行動に移す。", "consideration": "・質問を交えながら、自分でも行動に移せるように声掛けを行なっていき、自分で出来た際は大いに褒めて自信へと繋げる。"}'::jsonb),
      ('鈴木玲', '{"kidsstate": "・思い通りにいかないと不機嫌になって泣いたり、暴言を吐いてしまう。", "aim": "・活動毎に気持ちを切り替えて参加する。", "consideration": "・活動毎に細めに時間を知らせて、片付けや終わりになるということを本児に事前に知らせていき、気持ちの切り替えが出来る環境を整える。"}'::jsonb)
    ) as t(nm, content) loop
      v_norm := regexp_replace(rec.nm, '[[:space:]　]', '', 'g');
      select ch.id into v_child from children ch
        join child_class_enrollments e on e.child_id = ch.id and e.class_id = v_class and e.effective_end_date is null
        where ch.office_id = v_office
          and (regexp_replace(ch.display_name,'[[:space:]　]','','g') = v_norm
               or regexp_replace(ch.full_name,'[[:space:]　]','','g') = v_norm)
        limit 1;
      if v_child is null then
        raise notice '個人案: 児童が見つかりません(つき): %', rec.nm;
      else
        insert into guidance_plan_individual_entries (plan_id, child_id, content)
          values (v_plan, v_child, rec.content)
          on conflict (plan_id, child_id) do update set content = excluded.content, updated_at = now();
      end if;
    end loop;
  end if;


  -- ============ ほし組（4歳） ============
  select id into v_class from childcare_classes
    where office_id = v_office and age_group = '4歳' and is_active
    order by (school_year = v_year) desc, school_year desc limit 1;
  if v_class is null then
    raise notice 'クラスが見つかりません: 4歳（ほし）';
  else
    select id into v_tmpl from guidance_plan_templates
      where plan_type='monthly' and coalesce(age_variant,'')='age1plus'
      order by is_published desc, version desc limit 1;
    if v_tmpl is null then raise exception 'monthly age1plus テンプレ無し(285未適用?)'; end if;
    select id into v_plan from guidance_plans
      where office_id=v_office and class_id=v_class and plan_type='monthly'
        and fiscal_year=v_year and coalesce(month,0)=v_month and week_start_date is null;
    if v_plan is null then
      insert into guidance_plans (office_id, class_id, plan_type, age_variant, template_id, fiscal_year, month, content, status)
        values (v_office, v_class, 'monthly', 'age1plus', v_tmpl, v_year, v_month, '{"aim": "・活動と休憩のバランスをとりながら、元気に過ごす", "nursing": "・子ども一人ひとりの健康状態を把握し、健康に過ごせるようにする。\n・必要な物や場所が分かりやすい環境を整え、身の回りのことを自分で行えるようにする。", "$子育て支援$": "・家庭と連携を取り合う中で生活リズムの大切さを伝えるとともに夏の疲れが出やすい時期でもあるので体調管理を心がけてもらう。", "$保育の実施に関わる配慮事項$": "・室内外の温度差に留意し、冷房の調節を行い快適に過ごせるようにする。\n・プール遊びをする近くに危険物がないかの安全確認を行う。", "health*aim": "・活動と休憩のバランスをとりながら、元気に過ごす", "health*content": "・水を使った様々な遊びに積極的に挑戦し、水遊びを全身で楽しむ。室内では、座って遊べる遊びや静を意識した遊びなどし、体を休ませながら遊ぶ。", "health*$内容の取り扱い$": "・プールがある日には、メリハリをつけた遊びを促していき、無理なく過ごせるように誘いかけていく。また、座って遊べる遊びをする際には偏りが出てしまうのでさまざまなおもちゃや遊び方を提示していき、たくさん遊びを触れることで遊びの幅を広げる。", "relations*aim": "・生活や遊びの中でルールや約束を守りながら友だちと仲良く過ごす。", "relations*content": "・遊びなどを通して自分の意見や思いだけではなく、相手にも気持ちがあることを知ろうとする。", "relations*$内容の取り扱い$": "・意見を出す場所を作ったり、トラブル等の場でも子どもの話をしっかり聞き、思いを話す経験を積めるようにする。", "environment*aim": "・プール活動を通して、水に親しみながらルールを守って遊ぶ", "environment*content": "・プール内のルールをあらためて知り、ルールを守りながら安全に遊ぼうとする。", "environment*$内容の取り扱い$": "・子どもたちが安全にプール活動を楽しめるよう、保育士は監視役と指導役に分かれて担当業務を徹底して行う。", "lang*aim": "・経験したことや楽しかったことなど、保育士や友だちに伝え、会話を楽しむ。", "lang*content": "・夏休み中に経験した楽しかったことなどを友だちや保育士に伝えるとともに、他の人の経験を聞くことを楽しむ。", "lang*$内容の取り扱い$": "・子どもの思いを十分聞いて受け止め、楽しく会話ができるようにする。また、友だちの話を聞いたり、自分のことを話したりできる時間や場を持つ。", "expression*aim": "・運動会を通して、練習したことを披露する喜びを味わう", "expression*content": "・運動会本番への期待を持ちながら練習に取り組み、本番では自信を持って舞台に立つ", "expression*$内容の取り扱い$": "・楽しんで練習や本番に参加できるよう、子どもの気分が上がったりやる気に繋がるような声かけをおこなう。"}'::jsonb, 'draft')
        returning id into v_plan;
    else
      update guidance_plans set content='{"aim": "・活動と休憩のバランスをとりながら、元気に過ごす", "nursing": "・子ども一人ひとりの健康状態を把握し、健康に過ごせるようにする。\n・必要な物や場所が分かりやすい環境を整え、身の回りのことを自分で行えるようにする。", "$子育て支援$": "・家庭と連携を取り合う中で生活リズムの大切さを伝えるとともに夏の疲れが出やすい時期でもあるので体調管理を心がけてもらう。", "$保育の実施に関わる配慮事項$": "・室内外の温度差に留意し、冷房の調節を行い快適に過ごせるようにする。\n・プール遊びをする近くに危険物がないかの安全確認を行う。", "health*aim": "・活動と休憩のバランスをとりながら、元気に過ごす", "health*content": "・水を使った様々な遊びに積極的に挑戦し、水遊びを全身で楽しむ。室内では、座って遊べる遊びや静を意識した遊びなどし、体を休ませながら遊ぶ。", "health*$内容の取り扱い$": "・プールがある日には、メリハリをつけた遊びを促していき、無理なく過ごせるように誘いかけていく。また、座って遊べる遊びをする際には偏りが出てしまうのでさまざまなおもちゃや遊び方を提示していき、たくさん遊びを触れることで遊びの幅を広げる。", "relations*aim": "・生活や遊びの中でルールや約束を守りながら友だちと仲良く過ごす。", "relations*content": "・遊びなどを通して自分の意見や思いだけではなく、相手にも気持ちがあることを知ろうとする。", "relations*$内容の取り扱い$": "・意見を出す場所を作ったり、トラブル等の場でも子どもの話をしっかり聞き、思いを話す経験を積めるようにする。", "environment*aim": "・プール活動を通して、水に親しみながらルールを守って遊ぶ", "environment*content": "・プール内のルールをあらためて知り、ルールを守りながら安全に遊ぼうとする。", "environment*$内容の取り扱い$": "・子どもたちが安全にプール活動を楽しめるよう、保育士は監視役と指導役に分かれて担当業務を徹底して行う。", "lang*aim": "・経験したことや楽しかったことなど、保育士や友だちに伝え、会話を楽しむ。", "lang*content": "・夏休み中に経験した楽しかったことなどを友だちや保育士に伝えるとともに、他の人の経験を聞くことを楽しむ。", "lang*$内容の取り扱い$": "・子どもの思いを十分聞いて受け止め、楽しく会話ができるようにする。また、友だちの話を聞いたり、自分のことを話したりできる時間や場を持つ。", "expression*aim": "・運動会を通して、練習したことを披露する喜びを味わう", "expression*content": "・運動会本番への期待を持ちながら練習に取り組み、本番では自信を持って舞台に立つ", "expression*$内容の取り扱い$": "・楽しんで練習や本番に参加できるよう、子どもの気分が上がったりやる気に繋がるような声かけをおこなう。"}'::jsonb, template_id=v_tmpl, age_variant='age1plus' where id=v_plan;
    end if;
    -- 個人案(ほし・4名)
    for rec in select * from (values
      ('野間柊佑', '{"kidsstate": "・プール活動には積極的に参加する姿が見られる\n・一斉活動には保育士と一緒に挑戦するようになる\n・他児と一緒にトイレに行くことを嫌がる様子が見られるが、保育士が見守ることで自分のペースでトイレに行くことができるようになる", "aim": "・トイレに対して安心感を持ち、自発的にトイレに行ったり排泄をしようとする", "consideration": "・好きなキャラクターを壁に貼るなどして、トイレが落ち着く場所になるよう環境設定をおこなう\n・子どものペースを尊重し、焦らず待ち、成功体験を褒めて自信を育てる。\n・ 決まった時間や流れを作り、絵カードや歌で誘導する。", "reflection": "・タヒチアンダンス、英語、製作など一斉活動を拒否する様子が多く見られる。タヒチアンダンスと英語は全く参加しないことも少なくないが、メンタルプレイには積極的に参加することができている。クラスの製作では、準備の段階から遅れを取ることが多く、保育士と一緒に準備をしたり、やる気が出ないときには無理にやらせず見守っている。他児が終わる頃にやっとやる気になることも少なくない。その際は時間が許す限り1対1で対応しているが、途中で時間がなくなってしまって切り上げなくてはいけなくなると「やりたかった」「まだ○○をやっていない」と癇癪を起こしてしまうこともある。\n・給食とおやつの際椅子に座ろうとしない様子が多く見られる。保育士が代わりに座ろうとすると素早く座ることができる。\n・持参しているオムツがなくなってしまった日があり、その際に園のオムツを履くか、持参しているパンツを履くか選択肢を与えたところ「パンツ」と答えて自分からパンツを履くことができた。その後から園ではパンツ(パッドをつけて)を履くことができている。引き続きトイレに行くことに対しては抵抗があるのか、渋る様子はあるが「パンツが濡れちゃうから行ったほうがいいよ」などと伝えると今までと比べて圧倒的にスムーズにトイレに向かうことができている。"}'::jsonb),
      ('森優斗', '{"kidsstate": "・友だちに対して自分の気持ちを伝えようとする\n・身の回りのことは時間はかかるが自分でできる\n・周りの様子を見て、自分のすべきことに気付き、やろうとする", "aim": "・生活や遊びの中で、自分で考え、必要な行動をしようとする。", "consideration": "・子どもの考えを受け止めながら、自分で判断して行動できるよう見守る。\n ・必要な物や場所が分かりやすい環境を整え、自ら行動しやすくする。\n ・自分で考えて行動できたことを認め、自信や意欲につなげる。", "reflection": "・友だちとの関わりの中で、やめてほしいことがあっても言葉で伝えることが難しい。少しずつ表情に出るようにはなっているため、保育士が「やめてほしかったらやめてって言うんだよ」と伝えると、自分で相手に伝えることができる。自発的に伝える、というところが伸びてくると良いと思う。\n・一つ一つの行動の後に必ず「終わった」のみ伝えてくる。終わった人は何をしているか、を周りを見て理解し、行動することが難しい。"}'::jsonb),
      ('田端陽大', '{"kidsstate": "・ルーティン化していることは素早く自分でできる\n・周りの様子を見て、自分のすべきことに気付き、やろうとする", "aim": "・生活や遊びの中で、自分で考え、必要な行動をしようとする。", "consideration": "・子どもの考えを受け止めながら、自分で判断して行動できるよう見守る。\n ・必要な物や場所が分かりやすい環境を整え、自ら行動しやすくする。\n ・自分で考えて行動できたことを認め、自信や意欲につなげる。", "reflection": "・今までは朝の会や一斉活動の際に、周りに流されて一緒にふざけてしまう場面が多く見られていたが、ふざけている子に対して注意をしたり、流されずに自分は頑張ろうとする姿が見られるようになっている。しかし集中力が長く続かないため一斉活動での話を最後まで聞くことができなかったり、フラフラしたり上の空になってしまったりする様子が見られる。保育士が声掛けをすることで切り替えることができる場面も多くなってきている。"}'::jsonb),
      ('樋口瑠絃', '{"kidsstate": "・プールの準備や片付けへのやる気はあるが、チャックを1人で閉めるのが難しい。\n・出来ない事があるとすぐに「やってください」と助けを求める事ができる。\n・友達間でのトラブルの際に、気分によってその場で話し合うことができる時とできない時がある。\n・プール遊びで気持ちが向上する事で、次の活動も切り替えられずに落ち着きがなくなったり、動きが大きくなる。\n・活動の合間に集中が切れ、友達と一緒にふざけてしまう。\n・担任の指示を聞いて動く事ができる。\n・楽しくなりすぎると、職員の注意を素直に聞く事ができず、再び同じ行動を取ってしまう。", "aim": "プールや運動遊び後に、気持ちを落ち着かせて次の活動にスムーズに参加する", "consideration": "・身体を動かした後は、一度静かに過ごせる活動を入れてから、切り替えができるように工夫する。\n・プール遊びが楽しかったことを振り返り、頭の中を整理させてから、次の活動へと移行する。\n・1対1で対応し、気持ちを落ち着かせられるように促す。\n・落ち着く事ができるまで、1人になれる空間を作って様子を見る。", "reflection": "・1対1で対応することで、本児の気持ちが昂る前に抑えることができ、落ち着いて活動に参加することができることもあった。\n ・本児の中で1人の存在が大きく、その児童が欠席だと特に集団で過ごすことが難しく、 自分のやりたいように過ごそうとしている。周りの状況をよく見ていた。\n・勝ち負けのある遊びをした際、負けると悔しがり、相手の友達を押したり叩いてしまうことがあったため、注意が必要だった。 悔しいと感じる気持ちを大切にしつつ、その気持ちをどう対処すべきかを伝えていきたい。\n・一斉活動をやりたがらずに様子を見ることがあったが、他児が始めているのを見て「やっぱりやる！」 と切り替えて参加することが多かった。"}'::jsonb)
    ) as t(nm, content) loop
      v_norm := regexp_replace(rec.nm, '[[:space:]　]', '', 'g');
      select ch.id into v_child from children ch
        join child_class_enrollments e on e.child_id = ch.id and e.class_id = v_class and e.effective_end_date is null
        where ch.office_id = v_office
          and (regexp_replace(ch.display_name,'[[:space:]　]','','g') = v_norm
               or regexp_replace(ch.full_name,'[[:space:]　]','','g') = v_norm)
        limit 1;
      if v_child is null then
        raise notice '個人案: 児童が見つかりません(ほし): %', rec.nm;
      else
        insert into guidance_plan_individual_entries (plan_id, child_id, content)
          values (v_plan, v_child, rec.content)
          on conflict (plan_id, child_id) do update set content = excluded.content, updated_at = now();
      end if;
    end loop;
  end if;


  -- ============ にじ組（5歳） ============
  select id into v_class from childcare_classes
    where office_id = v_office and age_group = '5歳' and is_active
    order by (school_year = v_year) desc, school_year desc limit 1;
  if v_class is null then
    raise notice 'クラスが見つかりません: 5歳（にじ）';
  else
    select id into v_tmpl from guidance_plan_templates
      where plan_type='monthly' and coalesce(age_variant,'')='age1plus'
      order by is_published desc, version desc limit 1;
    if v_tmpl is null then raise exception 'monthly age1plus テンプレ無し(285未適用?)'; end if;
    select id into v_plan from guidance_plans
      where office_id=v_office and class_id=v_class and plan_type='monthly'
        and fiscal_year=v_year and coalesce(month,0)=v_month and week_start_date is null;
    if v_plan is null then
      insert into guidance_plans (office_id, class_id, plan_type, age_variant, template_id, fiscal_year, month, content, status)
        values (v_office, v_class, 'monthly', 'age1plus', v_tmpl, v_year, v_month, '{"aim": "・友だちと一緒に一つの活動に取り組み楽しさや達成感を味わう\n・暑い中でも夢中になれる、夏ならではの豊かな体験をする。", "nursing": "・安全な環境の下、夏ならではの遊びや活動を思いっきり楽しめるようにする\n ・頑張ったことややり遂げたことを認め、自信と達成感が持てるようにする", "$子育て支援$": "・規則正しい生活が夏を健康に過ごすことに繋がることを保護者に伝えていく", "$保育の実施に関わる配慮事項$": "・保育士も体を動かしたり、声掛けをしたりしながら楽しく参加する\n ・思いきり遊んだ後は、子どもの体調を確認し個々に合わせた休息が取れるようにしていく", "health*aim": "・友達と動きを合わせながら、意欲的に取り組む楽しさを感じる", "health*content": "・音楽に合わせて体を動かし、リズム感や身体の使い方を身につける。 隊形移動や友達との位置関係を意識しながら踊る", "health*$内容の取り扱い$": "・動きの意味やかっこよさを伝え、楽しみながら主体的に取り組めるようにする。 友達同士で励まし合い、協力しながら練習できる雰囲気をつくる。", "relations*aim": "・友達と一緒に考えを出し合いながら、工夫したり協力したりして充実感をもつ。", "relations*content": "・様々な遊びを通し互いに思いを出し合う中で、思いの違いからトラブルになるが、話し合うことで友だちの意見を受け入れる。", "relations*$内容の取り扱い$": "・相手の立場を認め、他児の良いところを見つける力が育つよう見守ったり、時には仲立ちをする。", "environment*aim": "・夏の自然や身近な事象に興味をもつ。", "environment*content": "・ 水遊びや泥遊びを通して、水の流れや量の変化などを感じる", "environment*$内容の取り扱い$": "・子どもの気付きや発見に共感し、一緒に考えたり調べたりできるよう援助する。 水や自然物に十分触れられる環境を整え、安全面に配慮する。", "lang*aim": "・夏の自然や遊びに関する言葉に興味をもち、語彙を豊かにする", "lang*content": "・夏の自然や生き物について知ったことを話し合う", "lang*$内容の取り扱い$": "・絵本や図鑑などを活用し、新しい言葉に触れる機会を設ける。 友達同士のやり取りを見守りながら、相手の話を聞く大切さも伝える。", "expression*aim": "・運動会の練習を通じて友だちや保育士と一緒に表現することを楽しむ。", "expression*content": "・共通の目的に向かって取り組み、息が合った時、できた時の喜びを感じる。", "expression*$内容の取り扱い$": "・子どもたちが頑張る姿を認め、動画に撮って見返し、良いところを褒めながら練習への意欲が高まるようにする。"}'::jsonb, 'draft')
        returning id into v_plan;
    else
      update guidance_plans set content='{"aim": "・友だちと一緒に一つの活動に取り組み楽しさや達成感を味わう\n・暑い中でも夢中になれる、夏ならではの豊かな体験をする。", "nursing": "・安全な環境の下、夏ならではの遊びや活動を思いっきり楽しめるようにする\n ・頑張ったことややり遂げたことを認め、自信と達成感が持てるようにする", "$子育て支援$": "・規則正しい生活が夏を健康に過ごすことに繋がることを保護者に伝えていく", "$保育の実施に関わる配慮事項$": "・保育士も体を動かしたり、声掛けをしたりしながら楽しく参加する\n ・思いきり遊んだ後は、子どもの体調を確認し個々に合わせた休息が取れるようにしていく", "health*aim": "・友達と動きを合わせながら、意欲的に取り組む楽しさを感じる", "health*content": "・音楽に合わせて体を動かし、リズム感や身体の使い方を身につける。 隊形移動や友達との位置関係を意識しながら踊る", "health*$内容の取り扱い$": "・動きの意味やかっこよさを伝え、楽しみながら主体的に取り組めるようにする。 友達同士で励まし合い、協力しながら練習できる雰囲気をつくる。", "relations*aim": "・友達と一緒に考えを出し合いながら、工夫したり協力したりして充実感をもつ。", "relations*content": "・様々な遊びを通し互いに思いを出し合う中で、思いの違いからトラブルになるが、話し合うことで友だちの意見を受け入れる。", "relations*$内容の取り扱い$": "・相手の立場を認め、他児の良いところを見つける力が育つよう見守ったり、時には仲立ちをする。", "environment*aim": "・夏の自然や身近な事象に興味をもつ。", "environment*content": "・ 水遊びや泥遊びを通して、水の流れや量の変化などを感じる", "environment*$内容の取り扱い$": "・子どもの気付きや発見に共感し、一緒に考えたり調べたりできるよう援助する。 水や自然物に十分触れられる環境を整え、安全面に配慮する。", "lang*aim": "・夏の自然や遊びに関する言葉に興味をもち、語彙を豊かにする", "lang*content": "・夏の自然や生き物について知ったことを話し合う", "lang*$内容の取り扱い$": "・絵本や図鑑などを活用し、新しい言葉に触れる機会を設ける。 友達同士のやり取りを見守りながら、相手の話を聞く大切さも伝える。", "expression*aim": "・運動会の練習を通じて友だちや保育士と一緒に表現することを楽しむ。", "expression*content": "・共通の目的に向かって取り組み、息が合った時、できた時の喜びを感じる。", "expression*$内容の取り扱い$": "・子どもたちが頑張る姿を認め、動画に撮って見返し、良いところを褒めながら練習への意欲が高まるようにする。"}'::jsonb, template_id=v_tmpl, age_variant='age1plus' where id=v_plan;
    end if;
  end if;

end $$;
