-- 191: 午睡チェックのグリッドに「記録者名」を返す(X4・コドモン準拠のセル・ポップアップ用)
--
-- 現状: nap_checks.checked_by は 169 の record_nap_check で my_employee_id() を保存済み
--       (=記録者は既にDBに保存されている)。しかし参照RPC fetch_nap_board が返す checks
--       jsonb には記録者名が含まれておらず、UIがセルに記録者を表示できない。
--
-- 変更: fetch_nap_board の checks jsonb に 'checked_by_name' キーを追加する
--       (nap_checks.checked_by → employees.name を left join)。
--
-- 非破壊: RETURNS TABLE の signature は不変(checks は jsonb のまま。jsonb オブジェクト内へ
--         キーを1つ追加するのみ)。よって drop 不要・create or replace のみ。既存の戻り列・型・
--         順序は変えないため admin_web / Ohana Kids の既存パースは影響を受けない(新キーは追加読み)。
-- 依存: 184〜190 のいずれのオブジェクトにも依存しない(169の関数を置換するのみ)。

create or replace function fetch_nap_board(p_office_id uuid, p_class_id uuid, p_session_date date)
returns table (
  session_id uuid,
  child_id uuid,
  display_name text,
  honorific_suffix text,
  class_id uuid,
  class_name text,
  is_required boolean,
  sleep_start_at timestamptz,
  wake_up_at timestamptz,
  checks jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not has_childcare_office_access(p_office_id) then
    raise exception 'not authorized';
  end if;

  return query
  select
    s.id, c.id, c.display_name, c.honorific_suffix_resolved, cc.id, cc.class_name,
    s.is_required, s.sleep_start_at, s.wake_up_at,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'slot_at', nc.slot_at, 'body_position', nc.body_position,
        'breathing', nc.breathing_checked, 'complexion', nc.complexion_checked,
        'bedding', nc.bedding_checked, 'source', nc.source,
        'checked_by_name', e.name) order by nc.slot_at)
      from nap_checks nc
      left join employees e on e.id = nc.checked_by
      where nc.session_id = s.id
    ), '[]'::jsonb)
  from nap_sessions s
  join children c on c.id = s.child_id
  join childcare_classes cc on cc.id = s.class_id
  where s.office_id = p_office_id and s.session_date = p_session_date
    and (p_class_id is null or s.class_id = p_class_id)
  order by cc.age_group, cc.class_name, c.display_name;
end;
$$;
