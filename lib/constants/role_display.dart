/// 役職コード → 日本語表示名の対応(職員アプリ・保育業務アプリ共通の1箇所)。
/// マイグレーション20260710160002 の roles と、20260714000147 で追加した
/// executive_director(統括園長)・area_manager(統括管理者)を含む。
///
/// 一般職員(staff)は役職行を持たずに運用されることがある(本番実測でstaff割当0名)。
/// そのため role_code が null の場合は「一般職員」を既定表示とする。
library;

const Map<String, String> kRoleDisplayNames = {
  'system_admin': 'システム管理者',
  'labor_manager': '労務管理者',
  'executive_director': '統括園長',
  'director': '園長',
  'area_manager': '統括管理者',
  'chief': '主任',
  'office_manager': '管理者',
  'viewer': '閲覧者',
  'staff': '一般職員',
};

/// 役職コードの表示名。null(役職行なし)や未知コードは「一般職員」にフォールバックする。
String roleDisplayName(String? roleCode) {
  if (roleCode == null) return '一般職員';
  return kRoleDisplayNames[roleCode] ?? '一般職員';
}
