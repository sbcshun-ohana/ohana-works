import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/guardian_profile.dart';
import '../models/guardian_qr_token.dart';
import '../models/linked_child.dart';

class GuardianServiceException implements Exception {
  GuardianServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 保護者ドメイン(RLS上は職員・給与系テーブルに一切アクセスしない、guardians/children系のみ)。
class GuardianService {
  GuardianService(this._client);

  final SupabaseClient _client;

  /// 未登録(招待未受諾)の場合はnullを返す。
  Future<GuardianProfile?> fetchMyProfile() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _client
        .from('guardians')
        .select('id, name, name_kana, phone, email, status')
        .eq('auth_user_id', userId)
        .maybeSingle();
    if (row == null) return null;
    return GuardianProfile.fromJson(row);
  }

  Future<List<LinkedChild>> fetchLinkedChildren() async {
    final links = await _client.from('guardian_child_links').select('''
      child_id,
      role,
      children (
        display_name,
        honorific_suffix,
        child_class_enrollments (
          effective_end_date,
          childcare_classes ( class_name )
        )
      )
    ''');
    final linkRows = (links as List).cast<Map<String, dynamic>>();
    if (linkRows.isEmpty) return [];

    final childIds = linkRows.map((r) => r['child_id'] as String).toSet().toList();
    final today = DateTime.now();
    final todayStr =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final statusRows = await _client
        .from('daily_child_status')
        .select('child_id, status')
        .inFilter('child_id', childIds)
        .eq('business_date', todayStr);
    final statusByChild = {
      for (final row in (statusRows as List).cast<Map<String, dynamic>>())
        row['child_id'] as String: row['status'] as String,
    };

    return linkRows
        .map((row) => LinkedChild.fromJson(row, todayStatus: statusByChild[row['child_id']]))
        .toList();
  }

  /// 招待コードを受諾し、保護者アカウントと園児の紐付けを作成する。
  /// 呼び出し前にSupabase Auth側でログイン済みである必要がある。
  Future<void> acceptInvitation({
    required String token,
    required String name,
    String? nameKana,
    String? phone,
    String? email,
  }) async {
    try {
      await _client.rpc('accept_guardian_invitation', params: {
        'p_token': token,
        'p_name': name,
        'p_name_kana': nameKana,
        'p_phone': phone,
        'p_email': email,
      });
    } on PostgrestException catch (e) {
      throw GuardianServiceException(_translateInvitationError(e.message));
    }
  }

  String _translateInvitationError(String message) {
    if (message.contains('invalid invitation token')) return '招待コードが正しくありません';
    if (message.contains('expired')) return '招待コードの有効期限が切れています。園に再発行を依頼してください';
    if (message.contains('cannot be accepted')) return 'この招待コードは既に使用済み、または取り消されています';
    if (message.contains('primary guardian limit')) return '主たる保護者の登録上限(2名)に達しています';
    return '招待コードの確認に失敗しました。もう一度お試しください';
  }

  /// 登降園用の動的QRを発行する(issue-guardian-qr-token、90秒有効)。
  Future<GuardianQrToken> issueChildQrToken(String childId) async {
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'issue-guardian-qr-token',
        body: {'child_id': childId},
      );
    } catch (_) {
      throw GuardianServiceException('QRコードの発行に失敗しました。通信状況を確認してください');
    }
    if (response.status != 200) {
      final data = response.data;
      final message = data is Map ? data['error'] as String? : null;
      throw GuardianServiceException(message ?? 'QRコードの発行に失敗しました');
    }
    return GuardianQrToken.fromJson(response.data as Map<String, dynamic>);
  }

  /// 発行済みQRが消費(使用済み)されたことをリアルタイム検知する。
  RealtimeChannel watchQrTokenUsage({
    required String childId,
    required void Function() onTokenUsed,
  }) {
    final channel = _client.channel('guardian_qr_tokens_child_$childId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'guardian_qr_tokens',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'child_id',
            value: childId,
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
