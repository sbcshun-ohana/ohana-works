import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/qr_token.dart';

/// QRトークンの発行呼び出しに失敗した場合の例外。
class QrAttendanceException implements Exception {
  QrAttendanceException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 9.2 ワンタイムQR発行・状態監視を扱うサービス。
/// トークンの発行自体はサーバー(Edge Function)が行い、クライアントは要求と表示のみを担う。
class QrAttendanceService {
  QrAttendanceService(this._client);

  final SupabaseClient _client;

  /// Edge Function `issue-qr-token` を呼び出し、新しいQRトークンを取得する。
  /// 発行時、当該職員の未使用トークンはサーバー側で自動的に失効させる。
  Future<QrToken> issueToken() async {
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke('issue-qr-token');
    } catch (_) {
      throw QrAttendanceException('QRコードの発行に失敗しました。通信状況を確認してください。');
    }

    if (response.status != 200) {
      throw QrAttendanceException('QRコードの発行に失敗しました。しばらくしてから再度お試しください。');
    }

    return QrToken.fromJson(response.data as Map<String, dynamic>);
  }

  /// ログイン中ユーザーに対応する employees.id を取得する。
  Future<String?> fetchOwnEmployeeId() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final row = await _client
        .from('employees')
        .select('id')
        .eq('auth_user_id', userId)
        .maybeSingle();

    return row?['id'] as String?;
  }

  /// 自分のQRトークンが「使用済み」に変化したことをリアルタイム検知し、自動で再発行できるようにする。
  RealtimeChannel watchTokenUsage({
    required String employeeId,
    required void Function() onTokenUsed,
  }) {
    final channel = _client.channel('qr_tokens_employee_$employeeId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'qr_tokens',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'employee_id',
            value: employeeId,
          ),
          callback: (payload) {
            final status = payload.newRecord['status'] as String?;
            if (status == 'used') {
              onTokenUsed();
            }
          },
        )
        .subscribe();
    return channel;
  }
}
