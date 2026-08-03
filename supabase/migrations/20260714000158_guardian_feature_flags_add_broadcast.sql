-- お知らせ Phase D: fetch_guardian_feature_flags の許可リストに parent_broadcast_notices を追加。
-- 157でフラグ定義を追加したが、保護者向けフラグ取得RPCは許可キーをハードコードしており、
-- リストに含めないと大和ONでもフラグが返らずホームのお知らせカードが出ない。中身は107から
-- キー1つ追加のみ(認可・master switch・office override ロジックは is_guardian_feature_enabled のまま不変)。
create or replace function fetch_guardian_feature_flags(p_child_id uuid)
returns table(feature_key text, enabled boolean)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not guardian_has_child_access(p_child_id) then
    raise exception 'not authorized';
  end if;
  return query
    select ff.feature_key, is_guardian_feature_enabled(ff.feature_key, p_child_id)
    from feature_flags ff
    where ff.feature_key in (
      'guardian_app', 'guardian_notices', 'guardian_requests',
      'family_daily_report', 'communication_book', 'class_photos', 'attendance_qr',
      'parent_broadcast_notices'
    );
end;
$$;
