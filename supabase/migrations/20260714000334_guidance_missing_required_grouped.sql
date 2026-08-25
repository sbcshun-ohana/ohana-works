-- 334: 申請時の「必須項目が未入力」メッセージを読みやすく(俊指示 2026-08-25)。
--   年間指導計画は複数セクション(子どもの姿/ねらい/養護/教育/保育者の援助/子育ての支援/園行事)が
--   それぞれ「1期(4〜6月)〜4期(1〜3月)」の必須欄を持つため、従来はフィールドラベルを素朴に列挙して
--   「1期(4〜6月)、2期…」が何度も繰り返され分かりづらかった。セクション単位に集約し
--   「子どもの姿(4件)、ねらい(4件)…」の形で返す。文言(prefix「必須項目が未入力です:」)は呼び出し側のまま。
create or replace function guidance_plan_missing_required(p_id uuid)
returns text language sql stable security definer set search_path = public as $$
  with missing as (
    select s.value->>'label' as sec_label, s.ordinality as sord
    from guidance_plans gp
    join guidance_plan_templates t on t.id = gp.template_id,
         jsonb_array_elements(t.sections) with ordinality as s(value, ordinality),
         jsonb_array_elements(s.value->'fields') as f
    where gp.id = p_id
      and coalesce((f->>'required')::boolean, false)
      and coalesce(nullif(btrim(coalesce(gp.content->>(f->>'key'), '')), ''), '') = ''
  ),
  grouped as (
    select sec_label, count(*) as cnt, min(sord) as sord
    from missing group by sec_label
  )
  select string_agg(
    case when cnt > 1 then sec_label || '(' || cnt || '件)' else sec_label end,
    '、' order by sord)
  from grouped;
$$;
grant execute on function guidance_plan_missing_required(uuid) to authenticated, service_role;
