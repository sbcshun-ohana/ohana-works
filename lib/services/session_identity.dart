import 'package:supabase_flutter/supabase_flutter.dart';

/// ログイン中の職員の氏名と最上位役職コード。役職コードの日本語表示は
/// lib/constants/role_display.dart の roleDisplayName() で解決する。
class SessionIdentity {
  const SessionIdentity({required this.name, this.roleCode});
  final String name;
  final String? roleCode;
}

/// ログイン中職員の氏名＋最上位役職を取得する。
/// fetch_my_session_identity(マイグレーション148)を使う。148 未適用時は
/// 氏名のみ(employees_select_self)へフォールバックする(役職は null=一般職員扱い)。
Future<SessionIdentity?> fetchMySessionIdentity() async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) return null;
  try {
    final rows = await client.rpc('fetch_my_session_identity');
    final list = rows as List;
    if (list.isEmpty) return _nameOnlyFallback(client, user.id);
    final row = list.first as Map<String, dynamic>;
    return SessionIdentity(
      name: (row['name'] as String?) ?? '',
      roleCode: row['role_code'] as String?,
    );
  } catch (_) {
    return _nameOnlyFallback(client, user.id);
  }
}

Future<SessionIdentity?> _nameOnlyFallback(SupabaseClient client, String authUserId) async {
  try {
    final row = await client
        .from('employees')
        .select('name')
        .eq('auth_user_id', authUserId)
        .maybeSingle();
    if (row == null) return null;
    return SessionIdentity(name: (row['name'] as String?) ?? '', roleCode: null);
  } catch (_) {
    return null;
  }
}
