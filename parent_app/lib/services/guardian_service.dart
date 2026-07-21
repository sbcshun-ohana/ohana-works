import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/class_photo.dart';
import '../models/communication_book_entry.dart';
import '../models/family_daily_report.dart';
import '../models/guardian_profile.dart';
import '../models/guardian_qr_token.dart';
import '../models/linked_child.dart';
import '../models/parent_request.dart';

String _formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

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
        office_id,
        display_name,
        honorific_suffix,
        child_class_enrollments (
          effective_end_date,
          class_id,
          childcare_classes ( class_name, age_group )
        )
      )
    ''');
    final linkRows = (links as List).cast<Map<String, dynamic>>();
    if (linkRows.isEmpty) return [];

    final childIds = linkRows.map((r) => r['child_id'] as String).toSet().toList();
    final todayStr = _formatDate(DateTime.now());
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

  /// 指定日の家庭連絡帳(未作成ならnull)。
  Future<FamilyDailyReport?> fetchFamilyDailyReport(String childId, DateTime businessDate) async {
    final row = await _client
        .from('family_daily_reports')
        .select()
        .eq('child_id', childId)
        .eq('business_date', _formatDate(businessDate))
        .maybeSingle();
    if (row == null) return null;
    return FamilyDailyReport.fromJson(row);
  }

  /// 提出済みの家庭連絡帳履歴(新しい日付順)。
  Future<List<FamilyDailyReport>> fetchFamilyDailyReportHistory(
    String childId, {
    int limit = 30,
  }) async {
    final rows = await _client
        .from('family_daily_reports')
        .select()
        .eq('child_id', childId)
        .eq('status', 'submitted')
        .order('business_date', ascending: false)
        .limit(limit);
    return (rows as List).cast<Map<String, dynamic>>().map(FamilyDailyReport.fromJson).toList();
  }

  /// 家庭連絡帳が当日登園に必須のクラス/園児かどうか。
  Future<bool> isFamilyDailyReportRequired(String childId, DateTime businessDate) async {
    final result = await _client.rpc('is_family_daily_report_required', params: {
      'p_child_id': childId,
      'p_business_date': _formatDate(businessDate),
    });
    return result as bool;
  }

  /// 家庭連絡帳の保存(下書き中のみ編集可)。
  Future<void> upsertFamilyDailyReport({
    required String childId,
    required DateTime businessDate,
    double? temperature,
    String? temperatureMeasuredAt,
    String? symptoms,
    String? homeNotes,
  }) async {
    try {
      await _client.rpc('upsert_family_daily_report', params: {
        'p_child_id': childId,
        'p_business_date': _formatDate(businessDate),
        'p_temperature': temperature,
        'p_temperature_measured_at': temperatureMeasuredAt,
        'p_symptoms': symptoms,
        'p_home_notes': homeNotes,
      });
    } on PostgrestException catch (e) {
      throw GuardianServiceException(_translateReportError(e.message));
    }
  }

  Future<void> submitFamilyDailyReport(String reportId) async {
    try {
      await _client.rpc('submit_family_daily_report', params: {'p_report_id': reportId});
    } on PostgrestException catch (e) {
      throw GuardianServiceException(_translateReportError(e.message));
    }
  }

  String _translateReportError(String message) {
    if (message.contains('cannot be edited') || message.contains('cannot be submitted')) {
      return '提出済みのため編集できません';
    }
    if (message.contains('temperature')) return '体温は35.0〜42.0℃の範囲で入力してください';
    return '保存に失敗しました。もう一度お試しください';
  }

  /// 承認済みの園連絡帳の一覧(新しい日付順)。
  Future<List<CommunicationBookEntry>> fetchCommunicationBookHistory(
    String childId, {
    int limit = 30,
  }) async {
    final rows = await _client
        .from('child_daily_contacts')
        .select()
        .eq('child_id', childId)
        .eq('status', 'approved')
        .order('business_date', ascending: false)
        .limit(limit);
    return (rows as List).cast<Map<String, dynamic>>().map(CommunicationBookEntry.fromJson).toList();
  }

  /// 個別お知らせ・備品利用も含めた詳細を取得する。
  Future<CommunicationBookEntry> fetchCommunicationBookEntryDetail(String entryId) async {
    final row = await _client.from('child_daily_contacts').select().eq('id', entryId).single();
    final entry = CommunicationBookEntry.fromJson(row);

    final noticeRows = await _client
        .from('child_daily_contact_notice_checks')
        .select('individual_notice_masters(label)')
        .eq('contact_id', entryId);
    final labels = (noticeRows as List)
        .cast<Map<String, dynamic>>()
        .map((r) => (r['individual_notice_masters'] as Map?)?['label'] as String?)
        .whereType<String>()
        .toList();

    final supplyRows = await _client
        .from('child_daily_contact_supply_items')
        .select('item_name, quantity')
        .eq('contact_id', entryId);
    final supplies = (supplyRows as List)
        .cast<Map<String, dynamic>>()
        .map((r) => SupplyItem(itemName: r['item_name'] as String, quantity: r['quantity'] as int))
        .toList();

    return entry.copyWith(noticeLabels: labels, supplyItems: supplies);
  }

  /// 個別お知らせが1件以上ある承認済み連絡帳の一覧(新しい日付順)。
  Future<List<CommunicationBookEntry>> fetchCommunicationBookNoticeHistory(
    String childId, {
    int limit = 30,
  }) async {
    final rows = await _client
        .from('child_daily_contacts')
        .select('*, child_daily_contact_notice_checks!inner(individual_notice_masters(label))')
        .eq('child_id', childId)
        .eq('status', 'approved')
        .order('business_date', ascending: false)
        .limit(limit);
    return (rows as List).cast<Map<String, dynamic>>().map((row) {
      final noticeRows = (row['child_daily_contact_notice_checks'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final labels = noticeRows
          .map((r) => (r['individual_notice_masters'] as Map?)?['label'] as String?)
          .whereType<String>()
          .toList();
      return CommunicationBookEntry.fromJson(row).copyWith(noticeLabels: labels);
    }).toList();
  }

  /// 未読件数(本文/個別お知らせ)をまとめて取得する。閲覧履歴(communication_book_reads)は
  /// 連絡帳(child_daily_contacts)1行単位で共有されており、本文と個別お知らせを独立には
  /// 既読管理していない。そのためどちらか一方を既読にすると、その日の両方のバッジが消える。
  Future<({int communicationBook, int notice})> fetchUnreadCounts({
    required String childId,
    required String guardianId,
  }) async {
    final contacts = await _client
        .from('child_daily_contacts')
        .select('id, current_text')
        .eq('child_id', childId)
        .eq('status', 'approved');
    final contactRows = (contacts as List).cast<Map<String, dynamic>>();
    if (contactRows.isEmpty) return (communicationBook: 0, notice: 0);

    final contactIds = contactRows.map((r) => r['id'] as String).toList();
    final readRows = await _client
        .from('communication_book_reads')
        .select('child_daily_contact_id')
        .eq('guardian_id', guardianId)
        .inFilter('child_daily_contact_id', contactIds);
    final readIds = (readRows as List)
        .cast<Map<String, dynamic>>()
        .map((r) => r['child_daily_contact_id'] as String)
        .toSet();
    final unreadContacts = contactRows.where((r) => !readIds.contains(r['id'] as String)).toList();
    if (unreadContacts.isEmpty) return (communicationBook: 0, notice: 0);

    final unreadIds = unreadContacts.map((r) => r['id'] as String).toList();
    final noticeRows = await _client
        .from('child_daily_contact_notice_checks')
        .select('contact_id')
        .inFilter('contact_id', unreadIds);
    final unreadIdsWithNotice = (noticeRows as List)
        .cast<Map<String, dynamic>>()
        .map((r) => r['contact_id'] as String)
        .toSet();

    final unreadTextCount =
        unreadContacts.where((r) => (r['current_text'] as String?)?.trim().isNotEmpty ?? false).length;
    return (communicationBook: unreadTextCount, notice: unreadIdsWithNotice.length);
  }

  /// 閲覧履歴を記録する(1名でも閲覧すれば家庭確認済みとする判定は職員側画面で行う)。
  Future<void> markCommunicationBookRead({required String entryId, required String guardianId}) async {
    await _client.from('communication_book_reads').upsert(
      {
        'child_daily_contact_id': entryId,
        'guardian_id': guardianId,
        'read_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'child_daily_contact_id,guardian_id',
    );
  }

  Future<void> confirmImportantMatter({required String entryId, required String guardianId}) async {
    await _client.from('communication_book_confirmations').upsert(
      {
        'child_daily_contact_id': entryId,
        'guardian_id': guardianId,
        'confirmation_type': 'important_matter_ack',
        'confirmed_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'child_daily_contact_id,guardian_id,confirmation_type',
    );
  }

  Future<bool> hasConfirmedImportantMatter({required String entryId, required String guardianId}) async {
    final row = await _client
        .from('communication_book_confirmations')
        .select('id')
        .eq('child_daily_contact_id', entryId)
        .eq('guardian_id', guardianId)
        .eq('confirmation_type', 'important_matter_ack')
        .maybeSingle();
    return row != null;
  }

  /// 国基準・自治体・当該園の感染症マスタ(office_idがnull=共通、一致=園独自)。
  Future<List<InfectiousDiseaseMaster>> fetchInfectiousDiseaseMasters(String officeId) async {
    final rows = await _client
        .from('infectious_disease_masters')
        .select()
        .eq('is_active', true)
        .or('office_id.is.null,office_id.eq.$officeId')
        .order('name');
    return (rows as List).cast<Map<String, dynamic>>().map(InfectiousDiseaseMaster.fromJson).toList();
  }

  Future<List<ParentRequest>> fetchParentRequests(String childId) async {
    final rows = await _client
        .from('parent_requests')
        .select()
        .eq('child_id', childId)
        .order('created_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>().map(ParentRequest.fromJson).toList();
  }

  Future<void> createParentRequest({
    required String childId,
    required String guardianId,
    required String requestType,
    required DateTime targetDate,
    required Map<String, dynamic> details,
  }) async {
    await _client.from('parent_requests').insert({
      'child_id': childId,
      'guardian_id': guardianId,
      'request_type': requestType,
      'target_date': _formatDate(targetDate),
      'details': details,
    });
  }

  Future<List<ParentRequestMessage>> fetchParentRequestMessages(String requestId) async {
    final rows = await _client
        .from('parent_request_messages')
        .select()
        .eq('request_id', requestId)
        .order('created_at');
    return (rows as List).cast<Map<String, dynamic>>().map(ParentRequestMessage.fromJson).toList();
  }

  Future<void> sendParentRequestMessage({required String requestId, required String guardianId, required String message}) async {
    await _client.from('parent_request_messages').insert({
      'request_id': requestId,
      'sender_type': 'guardian',
      'sender_guardian_id': guardianId,
      'message': message,
    });
  }

  /// 公開済みのクラス写真一覧(新しい日付順)。
  Future<List<ClassPhoto>> fetchClassPhotos(String classId, {int limit = 60}) async {
    final rows = await _client
        .from('class_daily_photos')
        .select('id, business_date, storage_path')
        .eq('class_id', classId)
        .eq('status', 'published')
        .order('business_date', ascending: false)
        .limit(limit);
    return (rows as List).cast<Map<String, dynamic>>().map(ClassPhoto.fromJson).toList();
  }

  /// 写真表示用の署名付きURL(5分間有効)。RLS(class_photos_storage_read_guardian)により、
  /// 公開済み・自分の園児のクラスの写真のみ発行できる。
  Future<String?> createClassPhotoSignedUrl(String storagePath) async {
    final url = await _client.storage.from('class-photos').createSignedUrl(storagePath, 300);
    return url;
  }
}
