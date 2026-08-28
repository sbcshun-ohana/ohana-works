-- 392: 世帯割当RPC【保留・2026-08-28俊決定で請求は園児個別方式へ変更】。
--   本RPC群はstagingに適用済みのため記録として残すが、UI(世帯管理画面)は撤去済み・未使用。
--   請求(Phase7以降)は園児単位で設計する(請求書・支払い・入金確認すべて園児ごと)。
--   households自体は重要事項説明書の世帯同意(310)・入園手続き(218)で存続(変更なし)。
--   世帯合算請求を将来復活させる場合はこのRPC群+撤去したUI(git履歴参照)を再利用できる。
-- 以下は当初の設計メモ(参考):
-- 392: 世帯割当UI用RPC(請求Phase3.5・2026-08-28俊承認)。
--   兄弟合算請求(世帯1本=詳細設計§1)の宛先となる世帯を、384の候補から確認して確定する。
--   権限写像(2026-08-28確定): 世帯の確定・変更=請求管理の日常操作=主任以上 manages_childcare
--   +請求フラグON。384(fetch_household_candidates)も同写像に合わせて権限を更新する。
--   世帯の削除は行わない: important_matter_consents(310)が household に on delete cascade で
--   ぶら下がるため(同意記録の保全)。最後の園児を解除しても世帯行は残す(画面に出ないだけ)。
--   保護者の household_id は「未所属の場合のみ」設定する(218の入園フローと同一規則。
--   共同親権等で別世帯の保護者は上書きしない=閲覧は guardian_child_links で担保)。

-- (0) 384の権限を確定写像へ更新(本体ロジックは変更なし・主任以上+フラグONに緩和)
create or replace function fetch_household_candidates(p_office_id uuid)
returns table (
  candidate_key text,
  primary_guardian_names text,
  child_count bigint,
  unassigned_count bigint,
  children jsonb
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  if not is_billing_enabled_for_office(p_office_id) then raise exception 'feature disabled'; end if;
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
      'household_id', cp.household_id,
      'has_household', cp.household_id is not null
    ) order by cp.child_name, cp.child_id) as children
  from cp
  where cardinality(cp.pg) > 0
  group by cp.pg
  having count(*) filter (where cp.household_id is null) > 0
  order by count(*) desc, max(cp.pnames);
end $$;

-- ============================================================
-- (1) fetch_household_page — 世帯管理画面の1画面分を一括返却
-- ============================================================
create or replace function fetch_household_page(p_office_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  if not is_billing_enabled_for_office(p_office_id) then raise exception 'feature disabled'; end if;

  return jsonb_build_object(
    -- ① 世帯候補(primary保護者集合が同一の在籍児・未割当が1人以上)。代表候補の保護者ID付き
    'candidates', coalesce((
      with cp as (
        select
          c.id as child_id,
          c.display_name as child_name,
          c.household_id,
          coalesce(array_agg(gcl.guardian_id order by gcl.guardian_id)
                   filter (where gcl.guardian_id is not null), '{}'::uuid[]) as pg
        from children c
        left join guardian_child_links gcl on gcl.child_id = c.id and gcl.role = 'primary'
        where c.office_id = p_office_id and c.enrollment_status = '在籍中'
        group by c.id, c.display_name, c.household_id
      )
      select jsonb_agg(cand order by (cand->>'child_count')::int desc, cand->>'guardian_names')
      from (
        select jsonb_build_object(
          'candidate_key', array_to_string(cp.pg, ','),
          'guardian_names', (select string_agg(g.name, ', ' order by g.name)
                             from guardians g where g.id = any(cp.pg)),
          'guardians', (select jsonb_agg(jsonb_build_object('guardian_id', g.id, 'name', g.name)
                                         order by g.name)
                        from guardians g where g.id = any(cp.pg)),
          'child_count', count(*),
          'unassigned_count', count(*) filter (where cp.household_id is null),
          'children', jsonb_agg(jsonb_build_object(
            'child_id', cp.child_id, 'child_name', cp.child_name,
            'household_id', cp.household_id, 'has_household', cp.household_id is not null
          ) order by cp.child_name, cp.child_id),
          -- 児の一部が既に世帯所属の場合、その世帯(既存世帯へ追加の導線用。複数なら児名順で先頭の1件)
          'existing_household_id',
            (array_agg(cp.household_id order by cp.child_name, cp.child_id)
             filter (where cp.household_id is not null))[1],
          'existing_household_name', (
            select h.display_name from households h
            where h.id = (array_agg(cp.household_id order by cp.child_name, cp.child_id)
                          filter (where cp.household_id is not null))[1])
        ) as cand
        from cp
        where cardinality(cp.pg) > 0
        group by cp.pg
        having count(*) filter (where cp.household_id is null) > 0
      ) cands
    ), '[]'::jsonb),
    -- ② 確定済み世帯(この施設に園児がいる世帯)
    'households', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', h.id,
        'display_name', h.display_name,
        'representative_guardian_id', h.representative_guardian_id,
        'representative_name', rg.name,
        'notes', h.notes,
        'children', hc.children,
        'guardian_names', (select string_agg(g.name, ', ' order by g.name)
                           from guardians g where g.household_id = h.id),
        -- 編集UI(代表の変更)用の選択肢。代表のprimary検証はupdate_household側で行う
        'guardians', (select coalesce(jsonb_agg(jsonb_build_object('guardian_id', g.id, 'name', g.name)
                                                order by g.name), '[]'::jsonb)
                      from guardians g where g.household_id = h.id)
      ) order by h.display_name nulls last)
      from households h
      left join guardians rg on rg.id = h.representative_guardian_id
      join lateral (
        select jsonb_agg(jsonb_build_object(
          'child_id', c.id, 'child_name', c.display_name, 'enrollment_status', c.enrollment_status
        ) order by c.display_name, c.id) as children
        from children c
        where c.household_id = h.id and c.office_id = p_office_id
      ) hc on hc.children is not null
    ), '[]'::jsonb),
    -- ③ primary保護者が未設定の在籍児(候補に出ない=先に保護者登録が必要)
    'no_primary_children', coalesce((
      select jsonb_agg(jsonb_build_object('child_id', c.id, 'child_name', c.display_name)
                       order by c.display_name)
      from children c
      where c.office_id = p_office_id and c.enrollment_status = '在籍中'
        and not exists (select 1 from guardian_child_links gcl
                        where gcl.child_id = c.id and gcl.role = 'primary')
    ), '[]'::jsonb)
  );
end;
$$;
grant execute on function fetch_household_page(uuid) to authenticated, service_role;

-- ============================================================
-- (2) assign_household — 新規世帯作成 or 既存世帯へ園児追加
-- ============================================================
create or replace function assign_household(
  p_office_id uuid,
  p_household_id uuid,               -- null = 新規作成
  p_child_ids uuid[],
  p_display_name text default null,  -- 新規時必須
  p_representative_guardian_id uuid default null,  -- 新規時必須
  p_notes text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_household uuid;
  v_child record;
  v_cnt int;
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  if not is_billing_enabled_for_office(p_office_id) then raise exception 'feature disabled'; end if;
  if p_child_ids is null or cardinality(p_child_ids) = 0 then
    raise exception '園児を1人以上指定してください';
  end if;
  -- 重複IDの正規化(同一IDが2回入っても誤検知しない)
  p_child_ids := (select array_agg(distinct t.id) from unnest(p_child_ids) t(id));

  -- 園児の検証(施設一致・在籍中ホワイトリスト・未割当)。for updateで同時割当を直列化
  for v_child in
    select c.id, c.display_name, c.office_id, c.enrollment_status, c.household_id
    from children c where c.id = any(p_child_ids)
    for update
  loop
    if v_child.office_id <> p_office_id then
      raise exception '「%」はこの施設の園児ではありません', v_child.display_name;
    end if;
    if v_child.enrollment_status not in ('在籍中', '退園予定') then
      raise exception '「%」は在籍中ではないため割当できません', v_child.display_name;
    end if;
    if v_child.household_id is not null then
      raise exception '「%」は既に世帯に割当済みです(先に解除してください)', v_child.display_name;
    end if;
  end loop;
  if (select count(*) from children where id = any(p_child_ids)) <> cardinality(p_child_ids) then
    raise exception 'not found';
  end if;

  if p_household_id is null then
    if p_display_name is null or btrim(p_display_name) = '' then
      raise exception '世帯名を入力してください';
    end if;
    if p_representative_guardian_id is null then
      raise exception '代表保護者を選択してください';
    end if;
    -- 代表は対象児いずれかのprimary保護者であること
    if not exists (select 1 from guardian_child_links gcl
                   where gcl.guardian_id = p_representative_guardian_id
                     and gcl.child_id = any(p_child_ids) and gcl.role = 'primary') then
      raise exception '代表保護者は対象園児のprimary保護者から選んでください';
    end if;
    insert into households (display_name, representative_guardian_id, notes)
    values (btrim(p_display_name), p_representative_guardian_id, p_notes)
    returning id into v_household;
  else
    select id into v_household from households where id = p_household_id;
    if v_household is null then raise exception 'not found'; end if;
    -- 無関係な世帯への合流を防ぐ: 対象児の保護者が既にその世帯に居る(or 代表)こと
    if not exists (
      select 1 from guardian_child_links gcl
      join guardians g on g.id = gcl.guardian_id
      where gcl.child_id = any(p_child_ids)
        and (g.household_id = v_household
             or g.id = (select representative_guardian_id from households where id = v_household))
    ) then
      raise exception 'この世帯と対象園児に共通の保護者がいません';
    end if;
  end if;

  -- 未割当条件つき更新+件数照合(検証後の並行割当も検出)
  update children set household_id = v_household
   where id = any(p_child_ids) and household_id is null;
  get diagnostics v_cnt = row_count;
  if v_cnt <> cardinality(p_child_ids) then
    raise exception '割当済みの園児が含まれます(画面を更新してください)';
  end if;
  -- 対象児に紐づく保護者(全role)のうち未所属の保護者を世帯へ(218入園フローと同一規則)
  update guardians g
     set household_id = v_household
   where g.household_id is null
     and exists (select 1 from guardian_child_links gcl
                 where gcl.guardian_id = g.id and gcl.child_id = any(p_child_ids));
  return v_household;
end;
$$;
grant execute on function assign_household(uuid, uuid, uuid[], text, uuid, text)
  to authenticated, service_role;

-- ============================================================
-- (3) update_household — 世帯名・代表・メモの変更
-- ============================================================
create or replace function update_household(
  p_household_id uuid,
  p_display_name text,
  p_representative_guardian_id uuid,
  p_notes text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  -- 権限: 世帯の園児が在籍するいずれかの施設を管理し、その施設で請求ONであること
  if not exists (
    select 1 from children c
    where c.household_id = p_household_id
      and manages_childcare(c.office_id)
      and is_billing_enabled_for_office(c.office_id)
  ) then raise exception 'not authorized'; end if;
  if p_display_name is null or btrim(p_display_name) = '' then
    raise exception '世帯名を入力してください';
  end if;
  if p_representative_guardian_id is null then
    raise exception '代表保護者を選択してください';
  end if;
  -- 代表は世帯の園児のprimary保護者であること(作成時と同一基準)
  if not exists (
    select 1 from guardian_child_links gcl
    join children c on c.id = gcl.child_id
    where gcl.guardian_id = p_representative_guardian_id
      and c.household_id = p_household_id
      and gcl.role = 'primary'
  ) then raise exception '代表保護者は世帯の園児のprimary保護者から選んでください'; end if;

  update households
     set display_name = btrim(p_display_name),
         representative_guardian_id = p_representative_guardian_id,
         notes = p_notes
   where id = p_household_id;
  if not found then raise exception 'not found'; end if;
end;
$$;
grant execute on function update_household(uuid, text, uuid, text) to authenticated, service_role;

-- ============================================================
-- (4) remove_child_from_household — 割当解除(訂正用)。
--     この児しか居なくなった保護者のリンクも外す。世帯行は削除しない(310同意記録の保全)。
-- ============================================================
create or replace function remove_child_from_household(p_child_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_child record;
begin
  select id, office_id, household_id into v_child from children where id = p_child_id;
  if v_child.id is null then raise exception 'not found'; end if;
  if not manages_childcare(v_child.office_id) then raise exception 'not authorized'; end if;
  if not is_billing_enabled_for_office(v_child.office_id) then raise exception 'feature disabled'; end if;
  if v_child.household_id is null then raise exception 'この園児は世帯に割当されていません'; end if;

  update children set household_id = null where id = p_child_id;
  -- この児経由でのみ世帯に居た保護者のリンクを外す(世帯内に他の児が残っていない保護者)
  update guardians g
     set household_id = null
   where g.household_id = v_child.household_id
     and exists (select 1 from guardian_child_links gcl
                 where gcl.guardian_id = g.id and gcl.child_id = p_child_id)
     and not exists (
       select 1 from guardian_child_links gcl2
       join children c2 on c2.id = gcl2.child_id
       where gcl2.guardian_id = g.id and c2.household_id = v_child.household_id
     );
  -- 外れた保護者が代表だった場合は代表をクリア(世帯行は残す方針と両立)
  update households h
     set representative_guardian_id = null
   where h.id = v_child.household_id
     and h.representative_guardian_id is not null
     and not exists (select 1 from guardians g
                     where g.id = h.representative_guardian_id
                       and g.household_id = h.id);
end;
$$;
grant execute on function remove_child_from_household(uuid) to authenticated, service_role;

-- 防御多層(388/390と同慣行)
revoke execute on function fetch_household_candidates(uuid) from public, anon;
revoke execute on function fetch_household_page(uuid) from public, anon;
revoke execute on function assign_household(uuid, uuid, uuid[], text, uuid, text) from public, anon;
revoke execute on function update_household(uuid, text, uuid, text) from public, anon;
revoke execute on function remove_child_from_household(uuid) from public, anon;
