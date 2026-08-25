-- 331: 大和オハナ保育園 令和8年度(2026)9月分の月案(6クラス)＋個人案 seed(俊指示 2026-08-25)。
-- 添付Excel(月案 9月分)を guidance_plans(月案)と guidance_plan_individual_entries(個人案)へ投入。status='draft'。
-- 個人案は「氏名照合せず、在籍児へ順番に割当(ランダム可)」との俊指示。全体の指導案を埋める目的で、
--   内容と児童の対応が実際とずれても可。クラスは office×age_group×is_active(2026優先)で解決。冪等。
-- 3・4・5歳の週別欄はスキップ(月案テンプレに欄なし)。
do $$
declare
  v_office uuid := 'c0a7010a-fd37-4cad-971b-6b3f2e80f842';
  v_year int := 2026;
  v_month int := 9;
  v_class uuid; v_tmpl uuid; v_plan uuid;
  v_kids uuid[]; v_contents jsonb[]; i int;
begin
  -- ============ はな組（0歳） ============
  select id into v_class from childcare_classes
    where office_id=v_office and age_group='0歳' and is_active
    order by (school_year=v_year) desc, school_year desc limit 1;
  if v_class is null then
    raise notice 'クラスが見つかりません: 0歳（はな）';
  else
    select id into v_tmpl from guidance_plan_templates
      where plan_type='monthly' and coalesce(age_variant,'')='age0'
      order by is_published desc, version desc limit 1;
    if v_tmpl is null then raise exception 'monthly age0 テンプレ無し'; end if;
    select id into v_plan from guidance_plans
      where office_id=v_office and class_id=v_class and plan_type='monthly'
        and fiscal_year=v_year and coalesce(month,0)=v_month and week_start_date is null;
    if v_plan is null then
      insert into guidance_plans (office_id,class_id,plan_type,age_variant,template_id,fiscal_year,month,content,status)
        values (v_office,v_class,'monthly','age0',v_tmpl,v_year,v_month,'{"aim": "・つかまり立ちや伝い歩きを十分に楽しむ\n・戸外で伸び伸びと体を動かし、秋の移り変わりを感じる", "nursing": "・夏の疲れや気候の変化に留意し、一人ひとりの健康状態に合わせて生活リズムを整え、ゆったりと過ごす。", "$子育て支援$": "・夏の疲れによる体調の変化を見逃さないようにし、連絡帳や口頭で子どもの様子を伝え合う。", "$保育の実施に関わる配慮事項$": "・一人ひとりの体調について把握し、具合が悪い時にすぐに対応出来るように、職員間で園児の様子を共有する。\n・落ち着いた安心出来る環境を作り、ゆったりと過ごせるよう保育士の動きを話し合い、連携を図る。", "healthygrow*aim": "・気温の変化に留意し、一人一人の生活リズムを整え、快適に過ごす。", "healthygrow*content": "・顔や手が汚れた時は拭いてもらい、汗をかいた時は着替えるなどしてきれいになった心地よさを感じる。", "healthygrow*$内容の取り扱い$": "・拭かれることや着替えることを嫌がるときには子どもの気持ちを代弁しながら手際よく済ませる。", "withfeelings*aim": "保育者と関わり合うことを楽しむ。", "withfeelings*content": "保育者の声かけに応じて喃語などで返事をして楽しむ。", "withfeelings*$内容の取り扱い$": "・子どもの表現する姿を見逃さず、何を伝えたいか受け止められるようにする。また、思いを受け止められる心地よさを感じられるようにする。", "sensitivity*aim": "身近なものなどに興味・関心をひかれ、好奇心を満たしつつ遊ぶ。", "sensitivity*content": "・気に入ったら近づき握ったり、振ったりする。", "sensitivity*$内容の取り扱い$": "・「いい音がするね」と声をかけたり、保育者の真似をして音を鳴らしたりして喜びを共有する。", "health*aim": "戸外で伸び伸びと体を動かし、秋の移り変わりを感じながら探索遊びを楽しむ。", "health*content": "活発に動けるようになってくる子が多いので、転んだ時などに危ないものがないか、保育室内の環境を改めて確認する。", "health*$内容の取り扱い$": "その日の暑さ指数を確認した上で、遊ぶ場所、戸外遊びの時間などを考えていく。", "relations*aim": "・保育士との間で落ち着いて過ごす。\n・同じ玩具で友達と一緒に遊ぼうと関わりを持つ。", "relations*content": "・保育士と十分なスキンシップで気持ちを満たし、落ち着いて過ごす。\n・友達の使っている玩具を求めたり、同じ物で一緒に遊んでいる雰囲気を味わう。", "relations*$内容の取り扱い$": "・子どもの仕草や態度を優しい表情で受け止めて、安心して保育士とのふれあいができるような雰囲気を作る。", "environment*aim": "・好きな玩具を見つけ、手を伸ばしたり、触ったり舐めたりして感触を楽しむ", "environment*content": "様々な素材のものに触れたり、見たりすることを楽しむ。", "environment*$内容の取り扱い$": "・子どもが出す感情を「楽しかった」や「嫌だったね」と言葉にしながら、受け止めていく。", "lang*aim": "やりとり遊びを通して、喃語や言葉を発することを楽しむ。", "lang*content": "・繰り返しのある絵本を見たり聞いたりして、言葉を真似して言葉を獲得する。", "lang*$内容の取り扱い$": "・年齢に合った絵本を多く用意し、見たくなる聞きたくなるような絵本の読み方、見せ方をする。", "expression*aim": "・好きなものに向かって手を伸ばしたり自分で移動することを喜ぶ。", "expression*content": "・歌や手遊びを聴いてリズムに合わせて体を動かしたり、踊ったりすることを楽しむ。", "expression*$内容の取り扱い$": "・簡単な歌や手遊びを歌い、一緒に体を動かすことで、楽しさを味わえるようにする。"}'::jsonb,'draft')
        returning id into v_plan;
    else
      update guidance_plans set content='{"aim": "・つかまり立ちや伝い歩きを十分に楽しむ\n・戸外で伸び伸びと体を動かし、秋の移り変わりを感じる", "nursing": "・夏の疲れや気候の変化に留意し、一人ひとりの健康状態に合わせて生活リズムを整え、ゆったりと過ごす。", "$子育て支援$": "・夏の疲れによる体調の変化を見逃さないようにし、連絡帳や口頭で子どもの様子を伝え合う。", "$保育の実施に関わる配慮事項$": "・一人ひとりの体調について把握し、具合が悪い時にすぐに対応出来るように、職員間で園児の様子を共有する。\n・落ち着いた安心出来る環境を作り、ゆったりと過ごせるよう保育士の動きを話し合い、連携を図る。", "healthygrow*aim": "・気温の変化に留意し、一人一人の生活リズムを整え、快適に過ごす。", "healthygrow*content": "・顔や手が汚れた時は拭いてもらい、汗をかいた時は着替えるなどしてきれいになった心地よさを感じる。", "healthygrow*$内容の取り扱い$": "・拭かれることや着替えることを嫌がるときには子どもの気持ちを代弁しながら手際よく済ませる。", "withfeelings*aim": "保育者と関わり合うことを楽しむ。", "withfeelings*content": "保育者の声かけに応じて喃語などで返事をして楽しむ。", "withfeelings*$内容の取り扱い$": "・子どもの表現する姿を見逃さず、何を伝えたいか受け止められるようにする。また、思いを受け止められる心地よさを感じられるようにする。", "sensitivity*aim": "身近なものなどに興味・関心をひかれ、好奇心を満たしつつ遊ぶ。", "sensitivity*content": "・気に入ったら近づき握ったり、振ったりする。", "sensitivity*$内容の取り扱い$": "・「いい音がするね」と声をかけたり、保育者の真似をして音を鳴らしたりして喜びを共有する。", "health*aim": "戸外で伸び伸びと体を動かし、秋の移り変わりを感じながら探索遊びを楽しむ。", "health*content": "活発に動けるようになってくる子が多いので、転んだ時などに危ないものがないか、保育室内の環境を改めて確認する。", "health*$内容の取り扱い$": "その日の暑さ指数を確認した上で、遊ぶ場所、戸外遊びの時間などを考えていく。", "relations*aim": "・保育士との間で落ち着いて過ごす。\n・同じ玩具で友達と一緒に遊ぼうと関わりを持つ。", "relations*content": "・保育士と十分なスキンシップで気持ちを満たし、落ち着いて過ごす。\n・友達の使っている玩具を求めたり、同じ物で一緒に遊んでいる雰囲気を味わう。", "relations*$内容の取り扱い$": "・子どもの仕草や態度を優しい表情で受け止めて、安心して保育士とのふれあいができるような雰囲気を作る。", "environment*aim": "・好きな玩具を見つけ、手を伸ばしたり、触ったり舐めたりして感触を楽しむ", "environment*content": "様々な素材のものに触れたり、見たりすることを楽しむ。", "environment*$内容の取り扱い$": "・子どもが出す感情を「楽しかった」や「嫌だったね」と言葉にしながら、受け止めていく。", "lang*aim": "やりとり遊びを通して、喃語や言葉を発することを楽しむ。", "lang*content": "・繰り返しのある絵本を見たり聞いたりして、言葉を真似して言葉を獲得する。", "lang*$内容の取り扱い$": "・年齢に合った絵本を多く用意し、見たくなる聞きたくなるような絵本の読み方、見せ方をする。", "expression*aim": "・好きなものに向かって手を伸ばしたり自分で移動することを喜ぶ。", "expression*content": "・歌や手遊びを聴いてリズムに合わせて体を動かしたり、踊ったりすることを楽しむ。", "expression*$内容の取り扱い$": "・簡単な歌や手遊びを歌い、一緒に体を動かすことで、楽しさを味わえるようにする。"}'::jsonb, template_id=v_tmpl, age_variant='age0' where id=v_plan;
    end if;
    -- 個人案(はな・6件)を在籍児へ順番割当(氏名照合なし・俊指示)。
    v_contents := array[
      '{"kidsstate": "・他児のやっている遊びに興味を持ち、玩具をとってしまうことがある。\n・給食をを食べる際、口を大きく開けて咀嚼もしっかり行い食べる。\n・つかまり立ちが安定し、伝い歩きも するようになる。", "aim": "・つかまり立ちや伝い歩きを十分に楽しむ 。\n・指差しや声、身近な大人の言葉や仕草をまねようとする。", "consideration": "・つかまり立ちや伝い歩きをしている時には、すぐに手を出せるようそばで見守る。\n・指差しや声に丁寧に応答し、保育者が言葉や仕草を添えながら、やり取りや模倣を楽しめるようにする。"}'::jsonb,
      '{"kidsstate": "・友達に興味があり、目や口など相手の顔を触る。\n・掴まり立ちをしようと、掴める場所を探し保育室を探索する姿が見られる。", "aim": "身体を動かすことを楽しみ、意欲的につかまり立ちに挑戦する。", "consideration": "•安全面に十分配慮しながら本児の一つ一つの動作に「すごいね」「上手だね」と声掛けをし、温かく見守る。"}'::jsonb,
      '{"kidsstate": "•喃語の量も増え、保育士の模倣をする姿が見られるようになる。\n•つかまり立ちが安定し、伝い歩きをしては片手を離したり手を挙げて立ってバランスを取ったりする。", "aim": "午前寝も少しずつ減り、生活リズムを整えながら快適に過ごす。", "consideration": "•子どもの気持ちに寄り添いながら語りかけたり、スキンシップを取りながら保育士との信頼関係を築き安心して過ごせるようにする。"}'::jsonb,
      '{"kidsstate": "生活リズムが安定し、決まった時間に午睡を取れることが増えてきた。\n・歩ける歩数が増え、手をあげバランスを取りながら歩行を楽しむ。\n・保育者に名前を呼ばれると笑顔を見せる。\n・保育士に噛みつこうとする。", "aim": "・他児に興味を持ち、自らかかわろうとする。\n・指差しや喃語で、自分の思いを表そうとする。", "consideration": "・他児に関わろうとする姿を見守り、保育士が仲立ちをしながら安心して関われるようにする。\n・子どもの指差しや喃語を受け止め、「○○だね」「欲しいね」などと言葉を添えてやり取りを楽しむ。"}'::jsonb,
      '{"kidsstate": "・何もつかむ物がない状態から1人で立ち上がり、歩き始める。\n・歩く歩数は増えスピードも早くなったが、体が前に出る為転びやすい。\n・噛みつきはしないが、口を開ける事がある。", "aim": "・保育者の動きに興味を持ち、同じことをしようとする。\n・食具に興味を持ち保育者と一緒に使ってみる。", "consideration": "・簡単な動作や手遊びなど、保育士の動きを真似して楽しめる遊びを取り入れる。\n・自分で食べようとする気持ちを育てながらも、スプーンに食材を乗せたり口に運びやすいよう援助する。"}'::jsonb,
      '{"kidsstate": "・1人でその場に立ち、数歩前に出ることができるようになる。\n・満腹を感じると口から出してもういらないと意思表示をするようになる。", "aim": "•ゆっくりと咀嚼をする。\n•立つ、座るなどの動きや姿勢を楽しむ中で、手放し状態の1人立ちに挑戦する。", "consideration": "•保育士が声掛けをしながら食べる姿を示し、「もぐもぐ」の模倣ができるようにする。\n•本児の一つ一つの動作に「すごいね」「上手だね」と声掛けをしながら温かく見守る。"}'::jsonb
    ];
    select array_agg(ch.id order by ch.birth_date, ch.id) into v_kids
      from children ch
      join child_class_enrollments e on e.child_id=ch.id and e.class_id=v_class and e.effective_end_date is null
      where ch.office_id=v_office;
    for i in 1 .. array_length(v_contents,1) loop
      if i > coalesce(array_length(v_kids,1),0) then
        raise notice '個人案(はな): 在籍児が不足(6件中 % 件のみ割当)', coalesce(array_length(v_kids,1),0);
        exit;
      end if;
      insert into guidance_plan_individual_entries (plan_id, child_id, content)
        values (v_plan, v_kids[i], v_contents[i])
        on conflict (plan_id, child_id) do update set content=excluded.content, updated_at=now();
    end loop;
  end if;


  -- ============ そら組（1歳） ============
  select id into v_class from childcare_classes
    where office_id=v_office and age_group='1歳' and is_active
    order by (school_year=v_year) desc, school_year desc limit 1;
  if v_class is null then
    raise notice 'クラスが見つかりません: 1歳（そら）';
  else
    select id into v_tmpl from guidance_plan_templates
      where plan_type='monthly' and coalesce(age_variant,'')='age1plus'
      order by is_published desc, version desc limit 1;
    if v_tmpl is null then raise exception 'monthly age1plus テンプレ無し'; end if;
    select id into v_plan from guidance_plans
      where office_id=v_office and class_id=v_class and plan_type='monthly'
        and fiscal_year=v_year and coalesce(month,0)=v_month and week_start_date is null;
    if v_plan is null then
      insert into guidance_plans (office_id,class_id,plan_type,age_variant,template_id,fiscal_year,month,content,status)
        values (v_office,v_class,'monthly','age1plus',v_tmpl,v_year,v_month,'{"aim": "・散歩などを通して自然に触れ、季節の変化を感じる。\n・夏の疲れに留意し、水分補給や休息をとりながら快適に過ごす。", "nursing": "・休息と活動のバランスをとり、快適に生活できるようにする。\n・それぞれの子どもの思いを受けとめて、安心しながら過ごせるようにする。", "$子育て支援$": "体調面について家庭と連絡を取り合い、健康へ気を付けていく。", "$保育の実施に関わる配慮事項$": "保育士同士・保護者との連携を取りながら、子どもが快適で健康的に過ごせるようにする。", "health*aim": "夏の疲れから体調を崩しやすい時期なので、生活リズムを整えたり、こまめな水分補給や休息などを行うなどして快適に生活できるようにする。", "health*content": "・戸外から園に戻った際は手を洗い、清潔にする。\n・衛生的な環境の中で快適に過ごす。", "health*$内容の取り扱い$": "・気温の変化に応じて、衣服の調節を行っていく。", "relations*aim": "保育教諭や友だちのまねをしたり、玩具の貸し借りをしたりすることなどを通して、友だちに興味を持ち、相手の存在に気づいていく。", "relations*content": "簡単な言葉を使って保育者や友だちとをやりとりをして、伝わることを楽しむ。", "relations*$内容の取り扱い$": "玩具の取り合いの際は、「かして」という言葉の仲立ちをして、順番に使うように促す。", "environment*aim": "・戸外活動で身近な秋の自然を見たりする。", "environment*content": "発見したことを指差しや簡単な言葉で友だちや保育者に伝えて、一緒に発見を楽しむ。", "environment*$内容の取り扱い$": "水分補給を行い、危険物が落ちていないか、危ない虫がいないか細心の注意を払い、安全確保をした上で、戸外遊びを楽しめるようにする。", "lang*aim": "・簡単な言葉や色々な仕草で、自分の思いを表現する。", "lang*content": "絵本に関心を持ち、くり返しの言葉を喜ぶ。", "lang*$内容の取り扱い$": "絵本や紙芝居を選ぶとき、くり返しの言葉、オノマトペなどの簡単なものを選ぶ。", "expression*aim": "保育教諭と一緒に歌ったり、リズムに合わせて体を動かしたりしてあそぶ。", "expression*content": "音楽に合わせ体を動かし、全身を動かして楽しむ。", "expression*$内容の取り扱い$": "わらべうたなど、子どもが親しめる歌や手あそびを、数多く準備する。"}'::jsonb,'draft')
        returning id into v_plan;
    else
      update guidance_plans set content='{"aim": "・散歩などを通して自然に触れ、季節の変化を感じる。\n・夏の疲れに留意し、水分補給や休息をとりながら快適に過ごす。", "nursing": "・休息と活動のバランスをとり、快適に生活できるようにする。\n・それぞれの子どもの思いを受けとめて、安心しながら過ごせるようにする。", "$子育て支援$": "体調面について家庭と連絡を取り合い、健康へ気を付けていく。", "$保育の実施に関わる配慮事項$": "保育士同士・保護者との連携を取りながら、子どもが快適で健康的に過ごせるようにする。", "health*aim": "夏の疲れから体調を崩しやすい時期なので、生活リズムを整えたり、こまめな水分補給や休息などを行うなどして快適に生活できるようにする。", "health*content": "・戸外から園に戻った際は手を洗い、清潔にする。\n・衛生的な環境の中で快適に過ごす。", "health*$内容の取り扱い$": "・気温の変化に応じて、衣服の調節を行っていく。", "relations*aim": "保育教諭や友だちのまねをしたり、玩具の貸し借りをしたりすることなどを通して、友だちに興味を持ち、相手の存在に気づいていく。", "relations*content": "簡単な言葉を使って保育者や友だちとをやりとりをして、伝わることを楽しむ。", "relations*$内容の取り扱い$": "玩具の取り合いの際は、「かして」という言葉の仲立ちをして、順番に使うように促す。", "environment*aim": "・戸外活動で身近な秋の自然を見たりする。", "environment*content": "発見したことを指差しや簡単な言葉で友だちや保育者に伝えて、一緒に発見を楽しむ。", "environment*$内容の取り扱い$": "水分補給を行い、危険物が落ちていないか、危ない虫がいないか細心の注意を払い、安全確保をした上で、戸外遊びを楽しめるようにする。", "lang*aim": "・簡単な言葉や色々な仕草で、自分の思いを表現する。", "lang*content": "絵本に関心を持ち、くり返しの言葉を喜ぶ。", "lang*$内容の取り扱い$": "絵本や紙芝居を選ぶとき、くり返しの言葉、オノマトペなどの簡単なものを選ぶ。", "expression*aim": "保育教諭と一緒に歌ったり、リズムに合わせて体を動かしたりしてあそぶ。", "expression*content": "音楽に合わせ体を動かし、全身を動かして楽しむ。", "expression*$内容の取り扱い$": "わらべうたなど、子どもが親しめる歌や手あそびを、数多く準備する。"}'::jsonb, template_id=v_tmpl, age_variant='age1plus' where id=v_plan;
    end if;
    -- 個人案(そら・8件)を在籍児へ順番割当(氏名照合なし・俊指示)。
    v_contents := array[
      '{"kidsstate": "・拍手や両手を動かしてリズムに乗ってみたり、歌に合わせて全身を動かして楽しむ\n・部屋の移動の階段を少しずつ降りられる", "aim": "・自分でできたことが増え、やってみようと挑戦する\n・保育士と一緒に歌ったり、リズムに合わせて体を動かしたりして遊ぶ。", "consideration": "・本児とやりとりを楽しんだり、保育士からたくさん話しかけていき、少しずつと言葉の取得や幅を広げていけるようにする。\n・いつでも水分補給を行えるよう、準備しておく。"}'::jsonb,
      '{"kidsstate": "・指差しや喃語を発して相手に想いを伝えようとする。思いが通らなかったり伝わらないと身体をそって怒っている。\n\n・友達にも自ら関わろうとする姿が見られる。", "aim": "・「ママ」「わんわん」などの簡単な単語を話そうとす。\n\n・散歩などで自然に触れ、季節の変化を感じる。", "consideration": "・本児とやりとりを楽しんだり、保育士からたくさん話しかけていき、少しずつ言葉の取得や幅を広げていけるようにする。"}'::jsonb,
      '{"kidsstate": "・給食時には、食べることに焦って手づかみで食べることが多い。\n\n・友達に対して玩具を取ったり隠したりすることがあるが、友達のことを気にかけ、泣いてる子に寄り添ってあげる様子も見られる。", "aim": "・スプーンやフォークを使ってゆっくり落ち着いて食べる。\n\n・散歩などで自然に触れ、季節の変化を感じる。", "consideration": "・食事のマナーをその都度伝え、よく噛んで食べる事、ゆっくり食べる事を保育士も一緒に食事を摂りながら手本となって見せていく。「おいしいね」など声をかけながら楽しい雰囲気の中で食事ができるように"}'::jsonb,
      '{"kidsstate": "・おもちゃを取られたくないと友達を押したり、保育士に甘えたり抱っこを求めたりと少しずつ意思表示をするようになってきている。\n\n・投げる、回す、走る遊びを好み、製作や玩具ではあまり遊ぶ様子が見られない。", "aim": "・保育士や友達の真似をして遊んでみようとする。\n\n・散歩などで自然に触れ、季節の変化を感じる。", "consideration": "・本児に合った言葉掛けや気持ちの受け止めを行う。また、活動がより楽しめるように本地に合った玩具を出したりする日を作る。"}'::jsonb,
      '{"kidsstate": "・着脱や手洗いなど自分でやろうとしている姿ある。そのため、自分でやると意欲的ではあるができないと泣いて怒ってしまうなど態度ででてしまう。", "aim": "・自分でできたことが増え、やってみようと挑戦する\n・知っている言葉や保育士の言った言葉を発しながら、自分の気持ちを表現する。", "consideration": "・時間が許す限りは自分でやらせてあげたり、認めてあげていく。できない時にはそっとやってあげていき、できた時には大いに褒めていき自信へと繋げる。"}'::jsonb,
      '{"kidsstate": "・お友達の真似をなんでもする(良い事も悪い事も)\n・やめてと言われてもしつこくついていく、同じことを真似するなどあるためトラブルになりやすい", "aim": "・自分でオムツやズボンの上げ下ろしをしようとする。\n・簡単な言葉や色々な仕草で、自分の思いを表現する。", "consideration": "・代弁、仲立ちを行い、気持ちを汲み取る。発語がしやすい雰囲気作りをする。\n  ・怪我のないよう見守り、物的環境配置に細心の注意を払い、活動が楽しめるようにする。"}'::jsonb,
      '{"kidsstate": "・靴下等の着脱などまだ自ら手が出る事が少ない。\n\n・食事の時間に眠くなってしまう事が多く、体力があまりない様子。", "aim": "・身の回りの簡単な事を自分でやってみようとする。\n\n・散歩などで自然に触れ、季節の変化を感じる。", "consideration": "・見守りつつ、難しいところは途中まで援助し、できた時は大いに褒め、「やってみよう」とする気持ちに繋げていく。"}'::jsonb,
      '{"kidsstate": "・使いたい気持ちが強くお友達から無理やりとってしまう、手が出てしまう事がある\n・僕のと言えるが手が出てしまうため保育士が気持ちを受け止めることで切り替えられる\n・しつこくされるとやめてと言える", "aim": "・簡単な言葉や色々な仕草で、自分の思いを表現する。\n・自分でできたことが増え、やってみようと挑戦する", "consideration": "・時間が許す限りは自分でやらせてあげたり、認めてあげていく。できない時にはそっとやってあげていき、できた時には大いに褒めていき自信へと繋げる。\n・本児に合った言葉掛けや気持ちの受け止めを行う。また、活動がより楽しめるような雰囲気作りをする。\n・代弁や仲立ちを行い、子どもたちが楽しめるように配慮する。"}'::jsonb
    ];
    select array_agg(ch.id order by ch.birth_date, ch.id) into v_kids
      from children ch
      join child_class_enrollments e on e.child_id=ch.id and e.class_id=v_class and e.effective_end_date is null
      where ch.office_id=v_office;
    for i in 1 .. array_length(v_contents,1) loop
      if i > coalesce(array_length(v_kids,1),0) then
        raise notice '個人案(そら): 在籍児が不足(8件中 % 件のみ割当)', coalesce(array_length(v_kids,1),0);
        exit;
      end if;
      insert into guidance_plan_individual_entries (plan_id, child_id, content)
        values (v_plan, v_kids[i], v_contents[i])
        on conflict (plan_id, child_id) do update set content=excluded.content, updated_at=now();
    end loop;
  end if;


  -- ============ かぜ組（2歳） ============
  select id into v_class from childcare_classes
    where office_id=v_office and age_group='2歳' and is_active
    order by (school_year=v_year) desc, school_year desc limit 1;
  if v_class is null then
    raise notice 'クラスが見つかりません: 2歳（かぜ）';
  else
    select id into v_tmpl from guidance_plan_templates
      where plan_type='monthly' and coalesce(age_variant,'')='age1plus'
      order by is_published desc, version desc limit 1;
    if v_tmpl is null then raise exception 'monthly age1plus テンプレ無し'; end if;
    select id into v_plan from guidance_plans
      where office_id=v_office and class_id=v_class and plan_type='monthly'
        and fiscal_year=v_year and coalesce(month,0)=v_month and week_start_date is null;
    if v_plan is null then
      insert into guidance_plans (office_id,class_id,plan_type,age_variant,template_id,fiscal_year,month,content,status)
        values (v_office,v_class,'monthly','age1plus',v_tmpl,v_year,v_month,'{"aim": "・夏から秋への自然の変化に気付く。 ・夏の疲れを癒やし、生活リズムを整えながら、心身ともに安定して過ごす。 ・全身を使った遊びや戸外遊びを十分に楽しむ", "nursing": "残暑や、朝夕の冷え込みで疲れがたまって、機嫌が悪くなったりすることがあるので快適に過ごせるように、室温や風通しなどに気を配り、落ち着いて生活できるようにする。", "$子育て支援$": "・季節の変化に伴い、気温に応じて調節がしやすい衣服の準備をしてもらうように伝えていく。", "$保育の実施に関わる配慮事項$": "・季節の変わり目なので体調の変化に気をつける。 ・伸び伸びと身体を動かして遊べるようにスペースを確保していく。", "health*aim": "自分から尿意を伝え、トイレで排泄に行こうとする。", "health*content": "少しずつオムツやパンツが濡れることに不快感を覚え、進んでトイレに向かおうとする。", "health*$内容の取り扱い$": "感覚がつかめるまで定期的にトイレに誘ってみながら、自分に合ったタイミングが分かるようにしていく。また、子どものペースに合わせて家庭と連携し園でもパンツで過ごす時間を作っていく。", "relations*aim": "挨拶を通して周囲の人との関わりを深める。", "relations*content": "「おはよう」「さようなら」など、挨拶を友達や保育士などとお互いに交わして気持ちよさを感じる。また戸外活動中には地域の人やすれ違う人にも元気に挨拶をする。", "relations*$内容の取り扱い$": "毎日の挨拶を欠かさず交わし、子どもが気持ちよさを感じられるようにしていく。", "environment*aim": "過ごしやすい日には戸外で伸び伸びと体を動かして遊ぶ。", "environment*content": "秋の虫や草花を観察してみたり、友達と追いかけっこをして体を思いっきり動かして遊んだりする。", "environment*$内容の取り扱い$": "久しぶりの公園やお散歩で気持ちが高まり、保育士の話を聞くことが出来ない姿がある。話を聞いて活動に乗れるように声掛けを行っていく。", "lang*aim": "言葉  ・友だちに対し思いを言葉で伝える。", "lang*content": "・ごっこ遊びを通じて、友達同士の言葉のやり取りを楽しみ、お互いに気持ちを伝え合う。", "lang*$内容の取り扱い$": "会話をする楽しさを感じられるように、保育士と子どもの間での言葉のキャッチボールを丁寧にする。", "expression*aim": "様々な色を違いや特徴に興味を持つ。", "expression*content": "たくさんの色の絵の具やクレヨンを使ったり、色見本の図鑑を読んだりして、色の違いや特徴に興味を示す。", "expression*$内容の取り扱い$": "様々なところで色を意識できるように、「葉っぱが緑から茶色になったね」など声かけをする。"}'::jsonb,'draft')
        returning id into v_plan;
    else
      update guidance_plans set content='{"aim": "・夏から秋への自然の変化に気付く。 ・夏の疲れを癒やし、生活リズムを整えながら、心身ともに安定して過ごす。 ・全身を使った遊びや戸外遊びを十分に楽しむ", "nursing": "残暑や、朝夕の冷え込みで疲れがたまって、機嫌が悪くなったりすることがあるので快適に過ごせるように、室温や風通しなどに気を配り、落ち着いて生活できるようにする。", "$子育て支援$": "・季節の変化に伴い、気温に応じて調節がしやすい衣服の準備をしてもらうように伝えていく。", "$保育の実施に関わる配慮事項$": "・季節の変わり目なので体調の変化に気をつける。 ・伸び伸びと身体を動かして遊べるようにスペースを確保していく。", "health*aim": "自分から尿意を伝え、トイレで排泄に行こうとする。", "health*content": "少しずつオムツやパンツが濡れることに不快感を覚え、進んでトイレに向かおうとする。", "health*$内容の取り扱い$": "感覚がつかめるまで定期的にトイレに誘ってみながら、自分に合ったタイミングが分かるようにしていく。また、子どものペースに合わせて家庭と連携し園でもパンツで過ごす時間を作っていく。", "relations*aim": "挨拶を通して周囲の人との関わりを深める。", "relations*content": "「おはよう」「さようなら」など、挨拶を友達や保育士などとお互いに交わして気持ちよさを感じる。また戸外活動中には地域の人やすれ違う人にも元気に挨拶をする。", "relations*$内容の取り扱い$": "毎日の挨拶を欠かさず交わし、子どもが気持ちよさを感じられるようにしていく。", "environment*aim": "過ごしやすい日には戸外で伸び伸びと体を動かして遊ぶ。", "environment*content": "秋の虫や草花を観察してみたり、友達と追いかけっこをして体を思いっきり動かして遊んだりする。", "environment*$内容の取り扱い$": "久しぶりの公園やお散歩で気持ちが高まり、保育士の話を聞くことが出来ない姿がある。話を聞いて活動に乗れるように声掛けを行っていく。", "lang*aim": "言葉  ・友だちに対し思いを言葉で伝える。", "lang*content": "・ごっこ遊びを通じて、友達同士の言葉のやり取りを楽しみ、お互いに気持ちを伝え合う。", "lang*$内容の取り扱い$": "会話をする楽しさを感じられるように、保育士と子どもの間での言葉のキャッチボールを丁寧にする。", "expression*aim": "様々な色を違いや特徴に興味を持つ。", "expression*content": "たくさんの色の絵の具やクレヨンを使ったり、色見本の図鑑を読んだりして、色の違いや特徴に興味を示す。", "expression*$内容の取り扱い$": "様々なところで色を意識できるように、「葉っぱが緑から茶色になったね」など声かけをする。"}'::jsonb, template_id=v_tmpl, age_variant='age1plus' where id=v_plan;
    end if;
    -- 個人案(かぜ・8件)を在籍児へ順番割当(氏名照合なし・俊指示)。
    v_contents := array[
      '{"kidsstate": "・拍手や両手を動かしてリズムに乗ってみたり、歌に合わせて全身を動かして楽しむ\n・部屋の移動の階段を少しずつ降りられる", "aim": "・自分でできたことが増え、やってみようと挑戦する\n・保育士と一緒に歌ったり、リズムに合わせて体を動かしたりして遊ぶ。", "consideration": "・本児とやりとりを楽しんだり、保育士からたくさん話しかけていき、少しずつと言葉の取得や幅を広げていけるようにする。\n・いつでも水分補給を行えるよう、準備しておく。"}'::jsonb,
      '{"kidsstate": "・指差しや喃語を発して相手に想いを伝えようとする。思いが通らなかったり伝わらないと身体をそって怒っている。\n\n・友達にも自ら関わろうとする姿が見られる。", "aim": "・「ママ」「わんわん」などの簡単な単語を話そうとす。\n\n・散歩などで自然に触れ、季節の変化を感じる。", "consideration": "・本児とやりとりを楽しんだり、保育士からたくさん話しかけていき、少しずつ言葉の取得や幅を広げていけるようにする。"}'::jsonb,
      '{"kidsstate": "・給食時には、食べることに焦って手づかみで食べることが多い。\n\n・友達に対して玩具を取ったり隠したりすることがあるが、友達のことを気にかけ、泣いてる子に寄り添ってあげる様子も見られる。", "aim": "・スプーンやフォークを使ってゆっくり落ち着いて食べる。\n\n・散歩などで自然に触れ、季節の変化を感じる。", "consideration": "・食事のマナーをその都度伝え、よく噛んで食べる事、ゆっくり食べる事を保育士も一緒に食事を摂りながら手本となって見せていく。「おいしいね」など声をかけながら楽しい雰囲気の中で食事ができるように"}'::jsonb,
      '{"kidsstate": "・おもちゃを取られたくないと友達を押したり、保育士に甘えたり抱っこを求めたりと少しずつ意思表示をするようになってきている。\n\n・投げる、回す、走る遊びを好み、製作や玩具ではあまり遊ぶ様子が見られない。", "aim": "・保育士や友達の真似をして遊んでみようとする。\n\n・散歩などで自然に触れ、季節の変化を感じる。", "consideration": "・本児に合った言葉掛けや気持ちの受け止めを行う。また、活動がより楽しめるように本地に合った玩具を出したりする日を作る。"}'::jsonb,
      '{"kidsstate": "・着脱や手洗いなど自分でやろうとしている姿ある。そのため、自分でやると意欲的ではあるができないと泣いて怒ってしまうなど態度ででてしまう。", "aim": "・自分でできたことが増え、やってみようと挑戦する\n・知っている言葉や保育士の言った言葉を発しながら、自分の気持ちを表現する。", "consideration": "・時間が許す限りは自分でやらせてあげたり、認めてあげていく。できない時にはそっとやってあげていき、できた時には大いに褒めていき自信へと繋げる。"}'::jsonb,
      '{"kidsstate": "・お友達の真似をなんでもする(良い事も悪い事も)\n・やめてと言われてもしつこくついていく、同じことを真似するなどあるためトラブルになりやすい", "aim": "・自分でオムツやズボンの上げ下ろしをしようとする。\n・簡単な言葉や色々な仕草で、自分の思いを表現する。", "consideration": "・代弁、仲立ちを行い、気持ちを汲み取る。発語がしやすい雰囲気作りをする。\n  ・怪我のないよう見守り、物的環境配置に細心の注意を払い、活動が楽しめるようにする。"}'::jsonb,
      '{"kidsstate": "・靴下等の着脱などまだ自ら手が出る事が少ない。\n\n・食事の時間に眠くなってしまう事が多く、体力があまりない様子。", "aim": "・身の回りの簡単な事を自分でやってみようとする。\n\n・散歩などで自然に触れ、季節の変化を感じる。", "consideration": "・見守りつつ、難しいところは途中まで援助し、できた時は大いに褒め、「やってみよう」とする気持ちに繋げていく。"}'::jsonb,
      '{"kidsstate": "・使いたい気持ちが強くお友達から無理やりとってしまう、手が出てしまう事がある\n・僕のと言えるが手が出てしまうため保育士が気持ちを受け止めることで切り替えられる\n・しつこくされるとやめてと言える", "aim": "・簡単な言葉や色々な仕草で、自分の思いを表現する。\n・自分でできたことが増え、やってみようと挑戦する", "consideration": "・時間が許す限りは自分でやらせてあげたり、認めてあげていく。できない時にはそっとやってあげていき、できた時には大いに褒めていき自信へと繋げる。\n・本児に合った言葉掛けや気持ちの受け止めを行う。また、活動がより楽しめるような雰囲気作りをする。\n・代弁や仲立ちを行い、子どもたちが楽しめるように配慮する。"}'::jsonb
    ];
    select array_agg(ch.id order by ch.birth_date, ch.id) into v_kids
      from children ch
      join child_class_enrollments e on e.child_id=ch.id and e.class_id=v_class and e.effective_end_date is null
      where ch.office_id=v_office;
    for i in 1 .. array_length(v_contents,1) loop
      if i > coalesce(array_length(v_kids,1),0) then
        raise notice '個人案(かぜ): 在籍児が不足(8件中 % 件のみ割当)', coalesce(array_length(v_kids,1),0);
        exit;
      end if;
      insert into guidance_plan_individual_entries (plan_id, child_id, content)
        values (v_plan, v_kids[i], v_contents[i])
        on conflict (plan_id, child_id) do update set content=excluded.content, updated_at=now();
    end loop;
  end if;


  -- ============ つき組（3歳） ============
  select id into v_class from childcare_classes
    where office_id=v_office and age_group='3歳' and is_active
    order by (school_year=v_year) desc, school_year desc limit 1;
  if v_class is null then
    raise notice 'クラスが見つかりません: 3歳（つき）';
  else
    select id into v_tmpl from guidance_plan_templates
      where plan_type='monthly' and coalesce(age_variant,'')='age1plus'
      order by is_published desc, version desc limit 1;
    if v_tmpl is null then raise exception 'monthly age1plus テンプレ無し'; end if;
    select id into v_plan from guidance_plans
      where office_id=v_office and class_id=v_class and plan_type='monthly'
        and fiscal_year=v_year and coalesce(month,0)=v_month and week_start_date is null;
    if v_plan is null then
      insert into guidance_plans (office_id,class_id,plan_type,age_variant,template_id,fiscal_year,month,content,status)
        values (v_office,v_class,'monthly','age1plus',v_tmpl,v_year,v_month,'{"aim": "・自分の興味ある遊びを友だちと楽しみながら言葉で気持ちを伝え合う。\n・保育士の声かけで、落ち着いて活動に参加できる時間を増やす", "nursing": "・体を動かした後は休息や水分を十分に摂れるようにする。\n・個々の行動を認めたり、励ましたり、頑張ろうとする気持ちを育てる。", "$子育て支援$": "・夏の疲れが出やすい時期なので、小まめに健康状態を伝え合い、体調管理をしていく。", "$保育の実施に関わる配慮事項$": "・夏の疲れに負けないよう、十分な睡眠、食事を摂れるよう配慮する。\n・生活習慣を見直し、個々に関わり、自信や達成感を持てるようにする。", "health*aim": "・簡単なルールのある遊びを、保育士や友だちと一緒に楽しむ。", "health*content": "・友だちとの遊びを通して、気持ちの伝え方が分かり楽しい雰囲気で遊ぶ。", "health*$内容の取り扱い$": "・保育士も一緒に体を動かし、楽しさを共感するとともに、やってみようとする意欲が持てるように言葉掛けをしていく。", "relations*aim": "・当番活動や保育士の手伝いを進んで行う。", "relations*content": "・人の役に立つ喜びを知る。", "relations*$内容の取り扱い$": "・自ら進んで出来た時にはたくさん褒め、自信に繋げていく。", "environment*aim": "・活動を最後まで続けようとする。", "environment*content": "・共通の目標に向かって活動する事を通して、友だちと協力し合う。", "environment*$内容の取り扱い$": "・最後まで活動に取り組めるように保育士も一緒に楽しみ促していく。", "lang*aim": "・絵本の読み聞かせで、言葉のやり取りを楽しむ。", "lang*content": "・絵本を通して様々な言葉を知り、友だちや保育士とのやりとりを楽しむ。", "lang*$内容の取り扱い$": "・絵本を通して生活や遊びのルールなども楽しく覚えられるように絵本選びも行っていく。", "expression*aim": "・リズムや音楽に合わせて表現する。", "expression*content": "・リトミックや音楽に合わせて体を動かしたりダンスを楽しんだりする。", "expression*$内容の取り扱い$": "・表現ゲームなども取り入れたり、人前での表現する楽しさを味わせていく。"}'::jsonb,'draft')
        returning id into v_plan;
    else
      update guidance_plans set content='{"aim": "・自分の興味ある遊びを友だちと楽しみながら言葉で気持ちを伝え合う。\n・保育士の声かけで、落ち着いて活動に参加できる時間を増やす", "nursing": "・体を動かした後は休息や水分を十分に摂れるようにする。\n・個々の行動を認めたり、励ましたり、頑張ろうとする気持ちを育てる。", "$子育て支援$": "・夏の疲れが出やすい時期なので、小まめに健康状態を伝え合い、体調管理をしていく。", "$保育の実施に関わる配慮事項$": "・夏の疲れに負けないよう、十分な睡眠、食事を摂れるよう配慮する。\n・生活習慣を見直し、個々に関わり、自信や達成感を持てるようにする。", "health*aim": "・簡単なルールのある遊びを、保育士や友だちと一緒に楽しむ。", "health*content": "・友だちとの遊びを通して、気持ちの伝え方が分かり楽しい雰囲気で遊ぶ。", "health*$内容の取り扱い$": "・保育士も一緒に体を動かし、楽しさを共感するとともに、やってみようとする意欲が持てるように言葉掛けをしていく。", "relations*aim": "・当番活動や保育士の手伝いを進んで行う。", "relations*content": "・人の役に立つ喜びを知る。", "relations*$内容の取り扱い$": "・自ら進んで出来た時にはたくさん褒め、自信に繋げていく。", "environment*aim": "・活動を最後まで続けようとする。", "environment*content": "・共通の目標に向かって活動する事を通して、友だちと協力し合う。", "environment*$内容の取り扱い$": "・最後まで活動に取り組めるように保育士も一緒に楽しみ促していく。", "lang*aim": "・絵本の読み聞かせで、言葉のやり取りを楽しむ。", "lang*content": "・絵本を通して様々な言葉を知り、友だちや保育士とのやりとりを楽しむ。", "lang*$内容の取り扱い$": "・絵本を通して生活や遊びのルールなども楽しく覚えられるように絵本選びも行っていく。", "expression*aim": "・リズムや音楽に合わせて表現する。", "expression*content": "・リトミックや音楽に合わせて体を動かしたりダンスを楽しんだりする。", "expression*$内容の取り扱い$": "・表現ゲームなども取り入れたり、人前での表現する楽しさを味わせていく。"}'::jsonb, template_id=v_tmpl, age_variant='age1plus' where id=v_plan;
    end if;
    -- 個人案(つき・10件)を在籍児へ順番割当(氏名照合なし・俊指示)。
    v_contents := array[
      '{"kidsstate": "・甘える姿は見られるがその中で頑張っている姿も多く見られる。", "aim": "・保育士に十分に甘えながら安心して過ごし、自分でやってみようとする。", "consideration": "・甘えたい時には気持ちを受け止め、十分に甘えられるようにする。一方で、自分で頑張ろうとする姿を見守り、必要に応じて援助しながら達成感につなげる。"}'::jsonb,
      '{"kidsstate": "・だんだんと名前を呼ばれるまで待てるようになってきた。", "aim": "・名前を呼ばれるまで順番を待つ", "consideration": "・待てたことを認め言葉にして褒める。"}'::jsonb,
      '{"kidsstate": "・動こうとしたりする姿はまだ見られるが、声をかけると落ち着く事ができる。", "aim": "・午睡中寝れなくても静かに過ごす。", "consideration": "・他児の睡眠を妨げないよう、眠れない時に過ごせる場所をあらかじめ決めておく。"}'::jsonb,
      '{"kidsstate": "・着脱をできるところまでは自分で行うようになる。", "aim": "・衣服の着脱に興味を持ち、自分でできるところまで取り組もうとする。", "consideration": "・自分で取り組む時間を確保し、すぐに手を出さず、必要なときに援助できるようにする。\n・できた際には大いに褒める。"}'::jsonb,
      '{"kidsstate": "・保育士や友達に対して、自分が嫌だと感じたことを「嫌だ」「やめて」と言葉で伝えようとする", "aim": "・自分が嫌だと感じたことを「嫌だ」「やめて」などの言葉で伝えようとする。", "consideration": "・子ども同士のやりとりを近くで見守り、必要に応じて仲立ちする。\n・保育士が気持ちを代弁しながら、少しずつ自分の言葉で伝えられるよう援助する。"}'::jsonb,
      '{"kidsstate": "・トイレに行くことに慣れ、便器に座る姿が見られる。", "aim": "・保育者に見守られながら安心してトイレに行き、便器に座ることに慣れる。", "consideration": "・「座れたね」「トイレに来られたね」と安心感や自信につなげる。\n・ 無理に排泄を促さず、子どもの気持ちやペースを大切にする。"}'::jsonb,
      '{"kidsstate": "・保育者に尿意を伝え、トイレへ向かうことができるようになった。", "aim": "・尿意を感じたときに保育者に伝え、トイレへ行こうとする。", "consideration": "・尿意を感じた際にすぐに伝えられるよう、保育者が近くで見守る。\n・自分から伝えてトイレに行けた際には、「教えてくれたね」「トイレに行けたね」と認め、自信につなげる。"}'::jsonb,
      '{"kidsstate": "・保育者や他児からの呼びかけに気づき、顔を向けたり返事をするようになってきた。", "aim": "・遊んでいる際、保育者や他児からの呼びかけに気づき、顔を向けたり返事をしたりしようとする。", "consideration": "・子どもの視界に入り、目線を合わせながら、穏やかに名前を呼びかける\n・遊びに集中していることを大切にし、無理に遊びを中断させるのではなく、区切りを見ながら声をかける。"}'::jsonb,
      '{"kidsstate": "・眠そうにする様子は見られることもあるが、いつも通り穏やかに過ごす。", "aim": "・生活リズムの変化に配慮し、無理なく園生活を過ごせるようにする。", "consideration": "体調や眠気の様子を見ながら、無理なく活動に参加できるようにする。安心して過ごせるよう、ゆったりと関わる。"}'::jsonb,
      '{"kidsstate": "・久しぶりの登園でも変わらず過ごす事ができたが、微熱近くなることも多々あった。", "aim": "体調の変化に配慮し、安心して無理なく園生活を過ごせるようにする。", "consideration": "登園時の体調や様子を丁寧に確認し、無理のない活動や休息を取り入れながら、少しずつ園生活のリズムを取り戻せるようにする。"}'::jsonb
    ];
    select array_agg(ch.id order by ch.birth_date, ch.id) into v_kids
      from children ch
      join child_class_enrollments e on e.child_id=ch.id and e.class_id=v_class and e.effective_end_date is null
      where ch.office_id=v_office;
    for i in 1 .. array_length(v_contents,1) loop
      if i > coalesce(array_length(v_kids,1),0) then
        raise notice '個人案(つき): 在籍児が不足(10件中 % 件のみ割当)', coalesce(array_length(v_kids,1),0);
        exit;
      end if;
      insert into guidance_plan_individual_entries (plan_id, child_id, content)
        values (v_plan, v_kids[i], v_contents[i])
        on conflict (plan_id, child_id) do update set content=excluded.content, updated_at=now();
    end loop;
  end if;


  -- ============ ほし組（4歳） ============
  select id into v_class from childcare_classes
    where office_id=v_office and age_group='4歳' and is_active
    order by (school_year=v_year) desc, school_year desc limit 1;
  if v_class is null then
    raise notice 'クラスが見つかりません: 4歳（ほし）';
  else
    select id into v_tmpl from guidance_plan_templates
      where plan_type='monthly' and coalesce(age_variant,'')='age1plus'
      order by is_published desc, version desc limit 1;
    if v_tmpl is null then raise exception 'monthly age1plus テンプレ無し'; end if;
    select id into v_plan from guidance_plans
      where office_id=v_office and class_id=v_class and plan_type='monthly'
        and fiscal_year=v_year and coalesce(month,0)=v_month and week_start_date is null;
    if v_plan is null then
      insert into guidance_plans (office_id,class_id,plan_type,age_variant,template_id,fiscal_year,month,content,status)
        values (v_office,v_class,'monthly','age1plus',v_tmpl,v_year,v_month,'{"aim": "・身の回りのことを自分で進んでやったり、お当番の仕事を楽しみながら行う", "nursing": "・季節の変化に気付き、興味や関心を持てるようにする。\n・活動と休息のバランスに留意し、快適に過ごせるようにする。", "$子育て支援$": "・まだ残暑が続くことが予想されるので引き続きこまめに水分補給を摂ったり、規則正しい生活を心がけてしっかりと睡眠がとれるようにする。体調に変化のある時には連絡を取り合う。", "$保育の実施に関わる配慮事項$": "・達成感を味わえるように出来た時は褒めるということを大切にしていく。\n・なるべく子ども自身で行えるよう見守ることを心掛ける。", "health*aim": "・たくさん体を動かす一方で、午睡など休むときにはしっかりと体を休めて、健康に過ごす。", "health*content": "・いろいろな活動や運動で元気に体を動かして遊ぶとともに、午睡など休むときにはしっかりと体を休めて、健康に過ごす。", "health*$内容の取り扱い$": "・水分補給や休息をとるタイミングを、必要に応じて声かけしていく。体調に変化が見られた場合には、ゆっくり過ごせる時間がとれるようにする。", "relations*aim": "・友だちとのやり取りの中で相手の気持ちも聞き、その気持ちに気付く。", "relations*content": "・活動や遊びのなかで友だちとの関わりを持ち、自分の気持ちを伝えるだけでなく、相手の気持ちも聞こうとする", "relations*$内容の取り扱い$": "・子ども同士のやりとりを見守りながら、双方が意見を言えるよう必要に応じて介入する。", "environment*aim": "・季節の変化に気付き、興味や関心を持つ。", "environment*content": "・気候の変化などで夏から秋に季節が移り変わっていくのを感じつつ、秋の植物や虫などの自然に親しむ。", "environment*$内容の取り扱い$": "・自然の移り変わりについて、保育士が気づいたことを子どもたちに伝えたり、子どもたちの気付きに耳を傾け、クラスで話す機会をつくる。", "lang*aim": "・自分の思ったことや感じたことを保育士や友だちと話すだけでなく、友だちの話を聞いて会話を楽しむ。", "lang*content": "・友だちが話している時には自分の話をせず、その話題で会話を楽しむ。", "lang*$内容の取り扱い$": "・自分の話したいことをうまく表現できない子には寄り添いながら言葉を引き出せるよう助言する。", "expression*aim": "・自分で考えて形にしたり、絵に描いたりすることを楽しむ", "expression*content": "・好きな材料を使ったり、絵を描いたりし、思い思いに製作をする。", "expression*$内容の取り扱い$": "・廃材や画用紙、折り紙などの様々な材料を用意して、自由に製作できるようにする。"}'::jsonb,'draft')
        returning id into v_plan;
    else
      update guidance_plans set content='{"aim": "・身の回りのことを自分で進んでやったり、お当番の仕事を楽しみながら行う", "nursing": "・季節の変化に気付き、興味や関心を持てるようにする。\n・活動と休息のバランスに留意し、快適に過ごせるようにする。", "$子育て支援$": "・まだ残暑が続くことが予想されるので引き続きこまめに水分補給を摂ったり、規則正しい生活を心がけてしっかりと睡眠がとれるようにする。体調に変化のある時には連絡を取り合う。", "$保育の実施に関わる配慮事項$": "・達成感を味わえるように出来た時は褒めるということを大切にしていく。\n・なるべく子ども自身で行えるよう見守ることを心掛ける。", "health*aim": "・たくさん体を動かす一方で、午睡など休むときにはしっかりと体を休めて、健康に過ごす。", "health*content": "・いろいろな活動や運動で元気に体を動かして遊ぶとともに、午睡など休むときにはしっかりと体を休めて、健康に過ごす。", "health*$内容の取り扱い$": "・水分補給や休息をとるタイミングを、必要に応じて声かけしていく。体調に変化が見られた場合には、ゆっくり過ごせる時間がとれるようにする。", "relations*aim": "・友だちとのやり取りの中で相手の気持ちも聞き、その気持ちに気付く。", "relations*content": "・活動や遊びのなかで友だちとの関わりを持ち、自分の気持ちを伝えるだけでなく、相手の気持ちも聞こうとする", "relations*$内容の取り扱い$": "・子ども同士のやりとりを見守りながら、双方が意見を言えるよう必要に応じて介入する。", "environment*aim": "・季節の変化に気付き、興味や関心を持つ。", "environment*content": "・気候の変化などで夏から秋に季節が移り変わっていくのを感じつつ、秋の植物や虫などの自然に親しむ。", "environment*$内容の取り扱い$": "・自然の移り変わりについて、保育士が気づいたことを子どもたちに伝えたり、子どもたちの気付きに耳を傾け、クラスで話す機会をつくる。", "lang*aim": "・自分の思ったことや感じたことを保育士や友だちと話すだけでなく、友だちの話を聞いて会話を楽しむ。", "lang*content": "・友だちが話している時には自分の話をせず、その話題で会話を楽しむ。", "lang*$内容の取り扱い$": "・自分の話したいことをうまく表現できない子には寄り添いながら言葉を引き出せるよう助言する。", "expression*aim": "・自分で考えて形にしたり、絵に描いたりすることを楽しむ", "expression*content": "・好きな材料を使ったり、絵を描いたりし、思い思いに製作をする。", "expression*$内容の取り扱い$": "・廃材や画用紙、折り紙などの様々な材料を用意して、自由に製作できるようにする。"}'::jsonb, template_id=v_tmpl, age_variant='age1plus' where id=v_plan;
    end if;
    -- 個人案(ほし・4件)を在籍児へ順番割当(氏名照合なし・俊指示)。
    v_contents := array[
      '{"kidsstate": "・苦手な活動にも保育士と一緒に参加しようとする姿が見られるようになる\n・身の回りのことを自分からやろうとする", "aim": "・保育士と一緒に一斉活動に参加する", "consideration": "・落ち着ける場所（安心できるスペースや椅子）を用意する\n・活動に再参加しやすいよう、すぐに戻れる位置に席や場所を整える\n・気持ちが乱れた時にはすぐに受け止め、安心できる言葉をかける\n・気持ちを代弁し、共感的に声をかける"}'::jsonb,
      '{"kidsstate": "・保育士に促されながら、嫌なことは嫌と相手に伝えようとする", "aim": "友達に自分の気持ちを言葉で伝えようとする", "consideration": "・嫌なことは嫌だと自分の言葉で言えるように見守る。\n・気持ちを汲み取りつつ、自分の思いを言葉にできるように援助する。\n・自分で考えて行動できたことを認め、自信や意欲につなげる。"}'::jsonb,
      '{"kidsstate": "・やらなければいけない場面で、周りに流されず行動しようとする姿が見られる\n・相手に自分の気持ちを言葉で伝えようとする", "aim": "人や物に対しての適切な力加減を、保育士の声掛けによって知り、気付く", "consideration": "・人や物に対して力加減が難しい際に、正しい力加減をその都度伝えていく。\n・少しずつ力加減を調節できるように、できた時には大きく認め、覚えられるように促す。\n・自分で考えられるような環境、遊びを提案し、実践する。"}'::jsonb,
      '{"kidsstate": "・遊びのルールは理解できても、それが自分に不利だとルールを破る。\n・自分の順番を待つことが難しく、 目の前にある物をいじったり、友達にちょっかいを出す。\n ・本児の中で1人の存在が大きく、その児童が欠席だと特に集団で過ごすことが難しく、 自分のやりたいように過ごそうとする。\n・興味のないものはやりたがらず、一度様子を見てから参加する。\n・友達間でトラブルになった際、素直に謝る事ができる。\n・特定の友達にちょっかいを出し、一緒にやるべき事から逃げて遊び出す。\n・ルール説明など一度聞くだけで理解することができる。\n・友達と一緒に作る事を好み、楽しむ。\n・勝ち負けのある遊びをした際に、負けると悔しがり相手の友達 を押したり叩いてしまう。", "aim": "友だちと一緒に遊ぶ中で、簡単なルールを理解し、守ろうとする", "consideration": "① ルールのある遊びの設定\n・すごろく・カードゲーム・簡単な集団遊びを取り入れる\n・順番や交代が必要な遊びを用意する\n\n② 見て分かるルール提示\n・順番や使い方をイラストや写真で示す\n・遊びの場所ごとに簡単な約束を掲示する\n\n③ 少人数で関われる環境\n・2〜4人で遊べるようコーナーを分ける\n・ルールを理解しやすい人数設定にする\n\n④ 順番・共有が生まれる環境\n・数に限りのある玩具や道具を用意する\n・「待つ」「交代する」場面を自然に作る\n\n⑤ 保育者が関わりやすい配置\n・全体が見渡せるようにする\n・ルールの確認や仲立ちがしやすい位置にいる"}'::jsonb
    ];
    select array_agg(ch.id order by ch.birth_date, ch.id) into v_kids
      from children ch
      join child_class_enrollments e on e.child_id=ch.id and e.class_id=v_class and e.effective_end_date is null
      where ch.office_id=v_office;
    for i in 1 .. array_length(v_contents,1) loop
      if i > coalesce(array_length(v_kids,1),0) then
        raise notice '個人案(ほし): 在籍児が不足(4件中 % 件のみ割当)', coalesce(array_length(v_kids,1),0);
        exit;
      end if;
      insert into guidance_plan_individual_entries (plan_id, child_id, content)
        values (v_plan, v_kids[i], v_contents[i])
        on conflict (plan_id, child_id) do update set content=excluded.content, updated_at=now();
    end loop;
  end if;


  -- ============ にじ組（5歳） ============
  select id into v_class from childcare_classes
    where office_id=v_office and age_group='5歳' and is_active
    order by (school_year=v_year) desc, school_year desc limit 1;
  if v_class is null then
    raise notice 'クラスが見つかりません: 5歳（にじ）';
  else
    select id into v_tmpl from guidance_plan_templates
      where plan_type='monthly' and coalesce(age_variant,'')='age1plus'
      order by is_published desc, version desc limit 1;
    if v_tmpl is null then raise exception 'monthly age1plus テンプレ無し'; end if;
    select id into v_plan from guidance_plans
      where office_id=v_office and class_id=v_class and plan_type='monthly'
        and fiscal_year=v_year and coalesce(month,0)=v_month and week_start_date is null;
    if v_plan is null then
      insert into guidance_plans (office_id,class_id,plan_type,age_variant,template_id,fiscal_year,month,content,status)
        values (v_office,v_class,'monthly','age1plus',v_tmpl,v_year,v_month,'{"aim": "・友だちに自らの思いや考えを伝え、相手の思いを聞こうとする。\n・夏の疲れに配慮しながら生活リズムを整え、健康に過ごす", "nursing": "・一人一人の思いや気持ちを受け止め、安心して自分の考えを表現できるようにする。\n・健康状態や夏の疲れに留意し、休息や水分補給を十分に行い、生活リズムを整えて健康に過ごせるよう援助する。", "$子育て支援$": "・夏の疲れが出やすい時期なので、体調の変化に留意し、連携し合うようにする。", "$保育の実施に関わる配慮事項$": "・活動と休息のバランスを考え、水分を十分にとり、無理のない保育内容にしていく。", "health*aim": "・夏の疲れに配慮しながら生活リズムを整え、健康に過ごす", "health*content": "・夏の疲れから活動中に疲れや眠気を感じる姿が見られる", "health*$内容の取り扱い$": "・一人ひとりの体調や表情、食欲などを丁寧に把握し、無理のない活動内容や休息時間を確保する。 こまめな水分補給や汗の始末、気温に応じた衣服の調節ができるよう声をかける。", "relations*aim": "・友達の思いや考えを受け止め、自分の気持ちも言葉で伝えようとする。", "relations*content": "・相手の気持ちを考えながら、言葉で伝えたり折り合いをつけたりしようとする", "relations*$内容の取り扱い$": "・子ども同士が互いの思いや考えを伝え合えるよう、話し合う機会を大切にする。", "environment*aim": "・暑さによる環境の変化や季節の移り変わりに関心をもち、身近な自然に触れながら発見や気付きを楽しむ。", "environment*content": "・発見したことや気付いたことを友達や保育士に伝え合い、会話を楽しむ。", "environment*$内容の取り扱い$": "・窓から空や雲を観察したり、採集した木の実や葉、図鑑や写真などを活用したりして、室内でも季節を感じられるようにする。", "lang*aim": "・様々な感情を考えながら、セリフや言葉で表現しようとする。\n・友だちに自らの思いや考えを伝え、相手の思いを聞こうとする。", "lang*content": "・感情をイメージしながら、表情や声の大きさ、話し方を工夫して表現しようとする。\n・自分の思いや考えをはっきり言ったり、友だちや保育士の言葉をしっかり聞く。", "lang*$内容の取り扱い$": "・子どもがイメージしやすいよう、絵本や日常の出来事を例に挙げながら感情を共有する。また、 正解・不正解ではなく、一人ひとりの表現を認め、自信につながるよう温かく受け止める\n・トラブルのときは様子を見て仲立ちするが、自分たちで話し合って解決していけるよう助言をしたり見守ったりする。", "expression*aim": "・音楽やリズムに合わせて、友達と一緒にのびのびと表現する", "expression*content": "・音やリズムを感じながら、ピアニカを吹くことを楽しむ", "expression*$内容の取り扱い$": "・正しい姿勢や息の吹き方、指の使い方を分かりやすく伝え、丁寧に扱えるよう援助する。\n・一人ひとりの状況に合わせ、無理なく楽しみながら取り組めるようにする。"}'::jsonb,'draft')
        returning id into v_plan;
    else
      update guidance_plans set content='{"aim": "・友だちに自らの思いや考えを伝え、相手の思いを聞こうとする。\n・夏の疲れに配慮しながら生活リズムを整え、健康に過ごす", "nursing": "・一人一人の思いや気持ちを受け止め、安心して自分の考えを表現できるようにする。\n・健康状態や夏の疲れに留意し、休息や水分補給を十分に行い、生活リズムを整えて健康に過ごせるよう援助する。", "$子育て支援$": "・夏の疲れが出やすい時期なので、体調の変化に留意し、連携し合うようにする。", "$保育の実施に関わる配慮事項$": "・活動と休息のバランスを考え、水分を十分にとり、無理のない保育内容にしていく。", "health*aim": "・夏の疲れに配慮しながら生活リズムを整え、健康に過ごす", "health*content": "・夏の疲れから活動中に疲れや眠気を感じる姿が見られる", "health*$内容の取り扱い$": "・一人ひとりの体調や表情、食欲などを丁寧に把握し、無理のない活動内容や休息時間を確保する。 こまめな水分補給や汗の始末、気温に応じた衣服の調節ができるよう声をかける。", "relations*aim": "・友達の思いや考えを受け止め、自分の気持ちも言葉で伝えようとする。", "relations*content": "・相手の気持ちを考えながら、言葉で伝えたり折り合いをつけたりしようとする", "relations*$内容の取り扱い$": "・子ども同士が互いの思いや考えを伝え合えるよう、話し合う機会を大切にする。", "environment*aim": "・暑さによる環境の変化や季節の移り変わりに関心をもち、身近な自然に触れながら発見や気付きを楽しむ。", "environment*content": "・発見したことや気付いたことを友達や保育士に伝え合い、会話を楽しむ。", "environment*$内容の取り扱い$": "・窓から空や雲を観察したり、採集した木の実や葉、図鑑や写真などを活用したりして、室内でも季節を感じられるようにする。", "lang*aim": "・様々な感情を考えながら、セリフや言葉で表現しようとする。\n・友だちに自らの思いや考えを伝え、相手の思いを聞こうとする。", "lang*content": "・感情をイメージしながら、表情や声の大きさ、話し方を工夫して表現しようとする。\n・自分の思いや考えをはっきり言ったり、友だちや保育士の言葉をしっかり聞く。", "lang*$内容の取り扱い$": "・子どもがイメージしやすいよう、絵本や日常の出来事を例に挙げながら感情を共有する。また、 正解・不正解ではなく、一人ひとりの表現を認め、自信につながるよう温かく受け止める\n・トラブルのときは様子を見て仲立ちするが、自分たちで話し合って解決していけるよう助言をしたり見守ったりする。", "expression*aim": "・音楽やリズムに合わせて、友達と一緒にのびのびと表現する", "expression*content": "・音やリズムを感じながら、ピアニカを吹くことを楽しむ", "expression*$内容の取り扱い$": "・正しい姿勢や息の吹き方、指の使い方を分かりやすく伝え、丁寧に扱えるよう援助する。\n・一人ひとりの状況に合わせ、無理なく楽しみながら取り組めるようにする。"}'::jsonb, template_id=v_tmpl, age_variant='age1plus' where id=v_plan;
    end if;
    -- 個人案(にじ・3件)を在籍児へ順番割当(氏名照合なし・俊指示)。
    v_contents := array[
      '{"kidsstate": "・相手の気持ちがわからず自分の気持ちばかりで会話をする\n・具体的なことや説明することができず本心が相手に伝わらない\n・危険なことを予測して遊ぶことができず、危険な行為を行いそうになる\n・疲れを感じやすく気が散りやすい\n・座って食べる時間が少しずつ増えていた\n・製作が好きでしっかり座って取り組める", "aim": "・遊びの中で危険なことを予測し、安全な遊び方を考えながら行動する\n・自分の思いや要求を具体的な言葉で伝え、相手の気持ちにも目を向けながら、友だちとのやり取りを楽しむ", "consideration": "・危険予測が立てられるように事前に伝える。また、興奮して周囲が見えにくくなっているときには、保育士が近くで見守り、必要に応じて声をかけながら安全に遊べるよう援助する。\n・自分の思いをうまく言葉にできないときは、保育士が気持ちを汲み取り、「○○してほしいんだね」「○○が嫌だったんだね」などと代弁し、具体的な言葉で伝えられるよう援助する。"}'::jsonb,
      '{"kidsstate": "約束事を理解しながらも、自分の中で気持ちの切り替えをする事が難しく、他の事を始める。\n自分の気持ちが前に出てしまい、周りの意見を受け入れる事が難しい。\n製作遊びやお絵描きなど、好きなことには夢中になって取り組む。\n相手の気持ちを言葉から理解したり、自分の気持ちを言葉で表現する事ができる。\n家で描いた絵や、気に入ったものを活動中も肌身離さず持つ。\n朝の機嫌や、その日の気分にあった活動の流れだと、自分から活動に参加したり 穏やかに1日を過ごす事ができる。", "aim": "・ルールや約束を意識する", "consideration": "・ルールは具体的かつ少数に絞る\n・理由を含めて説明する（納得重視）\n・守れた場面をその都度フィードバック\n・難しい場面は事前に対応を共有"}'::jsonb,
      '{"kidsstate": "・集中していくが分散されやすく話が入ってこない様子\n・興味があることにもっと追求したいのか調べたりする\n・塗り絵に夢中になり、1時間ほど時間をかけてきれいに完成させる\n・給食後に椅子を片付けることを忘れてしまい繰り返し伝えても気づかない", "aim": "・提示された手順や見本を参考にしながら、自分で見通しをもち、最後まで活動に取り組もうとする。\n\n・保育士の言葉掛けを受けながら、自分の思いや困っていることを少しずつ言葉で表現しようとする。", "consideration": "・一度に多くの指示を伝えず、短く分かりやすい言葉で伝え、必要に応じて一緒に確認する。 また、自分でできたことを具体的に認め、自信をもって次の活動へ取り組めるようにする。\n・不安や戸惑いが見られた際は、すぐに答えを求めず、気持ちを受け止めながら状況を一緒に整理する"}'::jsonb
    ];
    select array_agg(ch.id order by ch.birth_date, ch.id) into v_kids
      from children ch
      join child_class_enrollments e on e.child_id=ch.id and e.class_id=v_class and e.effective_end_date is null
      where ch.office_id=v_office;
    for i in 1 .. array_length(v_contents,1) loop
      if i > coalesce(array_length(v_kids,1),0) then
        raise notice '個人案(にじ): 在籍児が不足(3件中 % 件のみ割当)', coalesce(array_length(v_kids,1),0);
        exit;
      end if;
      insert into guidance_plan_individual_entries (plan_id, child_id, content)
        values (v_plan, v_kids[i], v_contents[i])
        on conflict (plan_id, child_id) do update set content=excluded.content, updated_at=now();
    end loop;
  end if;

end $$;
