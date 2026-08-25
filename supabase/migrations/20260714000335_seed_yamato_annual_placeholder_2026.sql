-- 335: 大和オハナ保育園 令和8年度(2026) 年間指導計画を全クラス分、仮の内容で穴埋め(俊指示 2026-08-25)。
--   月案はExcelから投入済みだが年間指導計画は空で、申請時に必須未入力になる。動作確認用に各欄を
--   セクションに応じた一般的な文言で埋める(空欄のみ・既入力は保持)。評価・反省(reflection)は空のまま。
--   クラスは office×age_group×is_active(2026優先)で解決し、年間計画が無ければ作成(status=draft)。冪等。
do $$
declare
  v_office uuid := 'c0a7010a-fd37-4cad-971b-6b3f2e80f842';
  v_year   int  := 2026;
  ages     text[] := array['0歳','1歳','2歳','3歳','4歳','5歳'];
  a        text;
  v_class  uuid;
  v_variant text;
  v_tmpl   guidance_plan_templates;
  v_id     uuid;
  v_content jsonb;
  sec      jsonb;
  fld      jsonb;
  v_key    text;
  v_sec    text;
  v_text   text;
begin
  foreach a in array ages loop
    select id into v_class from childcare_classes
      where office_id = v_office and age_group = a and is_active
      order by (school_year = v_year) desc, school_year desc limit 1;
    if v_class is null then raise notice '年間: クラスが見つかりません(%)', a; continue; end if;

    v_variant := guidance_age_variant('annual', v_class);
    v_tmpl := guidance_template_for('annual', v_variant);
    if v_tmpl.id is null then raise notice '年間: テンプレ無し(% %)', a, v_variant; continue; end if;

    select id, content into v_id, v_content from guidance_plans
      where office_id = v_office and class_id = v_class and plan_type = 'annual'
        and fiscal_year = v_year and month is null and week_start_date is null;
    if v_id is null then
      insert into guidance_plans (office_id, class_id, plan_type, age_variant, template_id, fiscal_year, content, status)
        values (v_office, v_class, 'annual', v_variant, v_tmpl.id, v_year, '{}'::jsonb, 'draft')
        returning id, content into v_id, v_content;
    end if;
    v_content := coalesce(v_content, '{}'::jsonb);

    for sec in select value from jsonb_array_elements(v_tmpl.sections) loop
      v_sec := sec->>'label';
      -- 評価・反省は空のまま(期末記入)。
      if (sec->>'key') = 'reflection' then continue; end if;
      for fld in select value from jsonb_array_elements(sec->'fields') loop
        v_key := fld->>'key';
        if v_key is null or v_key = '' or v_key = 'reflection' then continue; end if;
        -- 既に入力があるものは上書きしない。
        if coalesce(nullif(btrim(coalesce(v_content->>v_key, '')), ''), '') <> '' then continue; end if;
        v_text := case v_sec
          when '年間目標' then '健康で安全な環境の中で、一人ひとりが安心して過ごし、意欲的に遊びや生活に取り組む。'
          when '健康安全災害' then '毎月の避難訓練と定期的な安全点検・衛生管理を行い、子どもの健康と安全を守る。'
          when '小学校との連携' then '小学校との交流や情報共有を通じて、就学への円滑な接続を図る。'
          when '子どもの姿' then '身近な環境に関心を持ち、遊びや生活を通して心身ともに健やかに育っている。'
          when 'ねらい' then '安心できる環境の中で、身近な人や物と関わりながら遊びや生活を楽しむ。'
          when '養護' then '一人ひとりの健康状態や生活リズムを把握し、快適に安心して過ごせるようにする。'
          when '教育' then '友達や保育者と関わりながら、様々な遊びや経験を通して豊かな感性を育む。'
          when '保育者の援助' then '子どもの気持ちを受け止め、一人ひとりに応じて安心して活動できるよう見守り援助する。'
          when '子育ての支援' then '家庭と連携し、子どもの育ちや様子を共有しながら、保護者を支援する。'
          when '園行事及び園事業' then '季節の行事や園の取り組みを通して、豊かな経験ができるようにする。'
          else '（仮入力）'
        end;
        v_content := v_content || jsonb_build_object(v_key, v_text);
      end loop;
    end loop;

    update guidance_plans set content = v_content where id = v_id;
  end loop;
end $$;
