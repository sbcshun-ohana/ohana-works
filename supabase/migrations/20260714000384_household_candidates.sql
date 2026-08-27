-- 384: 請求決済 Phase 0/1 先行 — 世帯(households)移行候補の生成(読み取り専用・DDLなし)。
--   既存児は household_id 未割当(218は新規入園時のみ設定)。primary保護者集合が同一の在籍児を
--   「同一世帯候補」として提示し、管理者が確認して households 作成+割当できるようにする。
--   兄弟合算請求(世帯1本)の土台を実データで検証する最初の一歩。書き込み副作用なし。
--   権限=施設管理者以上(is_childcare_admin)。テーブル/列は218で既存のため新規DDLなし。
--   【v1の限界(Phase1割当UIで補完予定)】
--     (a)施設スコープ: 兄弟が別office在籍だと候補が施設ごとに割れる(householdsはoffice非スコープ)。将来 保護者ID横断のmerge補助が要。
--     (b)完全一致: primary集合の部分一致(片方の児のみ祖母がprimary等)は別候補になる。同一保護者が複数候補に出る場合の警告は将来対応。
--     (c)primaryなし児は本RPCに出ない。「primary未設定の在籍児」リストはPhase1 UIで別途補完。
create or replace function fetch_household_candidates(p_office_id uuid)
returns table (
  candidate_key text,             -- 同一primary保護者集合の識別(guardian_idソート連結)
  primary_guardian_names text,    -- primary保護者名(カンマ区切り)
  child_count bigint,             -- 候補内の在籍児数
  unassigned_count bigint,        -- うち household 未割当の児数
  children jsonb                  -- [{child_id, child_name, has_household}]
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_childcare_admin(p_office_id) then raise exception 'not authorized'; end if;
  return query
  with cp as (
    select
      c.id as child_id,
      c.display_name as child_name,
      c.household_id,
      coalesce(array_agg(gcl.guardian_id order by gcl.guardian_id)
               filter (where gcl.guardian_id is not null), '{}'::uuid[]) as pg,
      string_agg(g.name, ', ' order by g.name)
               filter (where g.name is not null) as pnames
    from children c
    left join guardian_child_links gcl on gcl.child_id = c.id and gcl.role = 'primary'
    left join guardians g on g.id = gcl.guardian_id
    where c.office_id = p_office_id and c.enrollment_status = '在籍中'
    group by c.id, c.display_name, c.household_id
  )
  select
    array_to_string(cp.pg, ',') as candidate_key,
    max(cp.pnames) as primary_guardian_names,
    count(*) as child_count,
    count(*) filter (where cp.household_id is null) as unassigned_count,
    jsonb_agg(jsonb_build_object(
      'child_id', cp.child_id,
      'child_name', cp.child_name,
      'household_id', cp.household_id,                          -- 既存世帯への追加割当・分裂検出のため返す
      'has_household', cp.household_id is not null
    ) order by cp.child_name, cp.child_id) as children         -- 同名児のタイブレーク
  from cp
  where cardinality(cp.pg) > 0                                  -- primary保護者がいる児のみ
  group by cp.pg
  having count(*) filter (where cp.household_id is null) > 0    -- 未割当が1人以上の候補のみ
  order by count(*) desc, max(cp.pnames);
end $$;
grant execute on function fetch_household_candidates(uuid) to authenticated, service_role;
