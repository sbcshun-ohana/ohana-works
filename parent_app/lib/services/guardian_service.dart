import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/class_photo.dart';
import '../models/communication_book_entry.dart';
import '../models/enrollment_form.dart';
import '../models/family_daily_report.dart';
import '../models/guardian_broadcast_notice.dart';
import '../models/guardian_profile.dart';
import '../models/guardian_qr_token.dart';
import '../models/linked_child.dart';
import '../models/parent_request.dart';
import '../models/pickup_person.dart';

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

  /// 施設・クラス単位の段階公開フラグ(feature_flags)。有効なfeature_keyの集合を返す。
  /// 例: 'attendance_qr'・'guardian_requests'・'family_daily_report'・'communication_book'・
  /// 'guardian_notices'・'class_photos'。マスタースイッチ'guardian_app'がOFFの施設では
  /// 他の全キーがfalseとして返る(RPC側is_guardian_feature_enabled()のロジック)。
  Future<Set<String>> fetchGuardianFeatureFlags(String childId) async {
    final rows = await _client.rpc('fetch_guardian_feature_flags', params: {'p_child_id': childId});
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .where((r) => r['enabled'] == true)
        .map((r) => r['feature_key'] as String)
        .toSet();
  }

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

  Future<List<LinkedChild>> fetchLinkedChildren({required String guardianId}) async {
    final links = await _client
        .from('guardian_child_links')
        .select('''
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
    ''')
        .eq('guardian_id', guardianId);
    final linkRows = (links as List).cast<Map<String, dynamic>>();
    if (linkRows.isEmpty) return [];

    final childIds = linkRows.map((r) => r['child_id'] as String).toSet().toList();
    final todayStr = _formatDate(DateTime.now());
    final results = await Future.wait([
      _client
          .from('daily_child_status')
          .select('child_id, status')
          .inFilter('child_id', childIds)
          .eq('business_date', todayStr),
      _client.rpc('fetch_my_children_office_names'),
    ]);
    final statusByChild = {
      for (final row in (results[0] as List).cast<Map<String, dynamic>>())
        row['child_id'] as String: row['status'] as String,
    };
    final officeNameByChild = {
      for (final row in (results[1] as List).cast<Map<String, dynamic>>())
        row['child_id'] as String: row['office_name'] as String,
    };

    return linkRows
        .map((row) => LinkedChild.fromJson(row, todayStatus: statusByChild[row['child_id']])
            .copyWithOfficeName(officeNameByChild[row['child_id']]))
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
    String? nightMood,
    String? morningMood,
    int? nightBowelCount,
    String? nightBowelCondition,
    int? morningBowelCount,
    String? morningBowelCondition,
    String? sleepStartAt,
    String? sleepEndAt,
    String? dinnerContent,
    String? dinnerAt,
    String? breakfastContent,
    String? breakfastAt,
    String? pickupPersonName,
    String? pickupPersonRelationship,
    String? pickupTimeFrom,
    String? pickupTimeTo,
    bool? poolParticipation,
  }) async {
    try {
      await _client.rpc('upsert_family_daily_report', params: {
        'p_child_id': childId,
        'p_business_date': _formatDate(businessDate),
        'p_temperature': temperature,
        'p_temperature_measured_at': temperatureMeasuredAt,
        'p_symptoms': symptoms,
        'p_home_notes': homeNotes,
        'p_night_mood': nightMood,
        'p_morning_mood': morningMood,
        'p_night_bowel_count': nightBowelCount,
        'p_night_bowel_condition': nightBowelCondition,
        'p_morning_bowel_count': morningBowelCount,
        'p_morning_bowel_condition': morningBowelCondition,
        'p_sleep_start_at': sleepStartAt,
        'p_sleep_end_at': sleepEndAt,
        'p_dinner_content': dinnerContent,
        'p_dinner_at': dinnerAt,
        'p_breakfast_content': breakfastContent,
        'p_breakfast_at': breakfastAt,
        'p_pickup_person_name': pickupPersonName,
        'p_pickup_person_relationship': pickupPersonRelationship,
        'p_pickup_time_from': pickupTimeFrom,
        'p_pickup_time_to': pickupTimeTo,
        'p_pool_participation': poolParticipation,
      });
    } on PostgrestException catch (e) {
      throw GuardianServiceException(_translateReportError(e.message));
    }
  }

  /// 施設でプール連絡(夏期)が有効か(家庭連絡帳のプール◯×欄の出し分け)。
  Future<bool> isPoolReportEnabledForOffice(String officeId) async {
    final result = await _client.rpc('is_pool_report_enabled_for_office', params: {'p_office_id': officeId});
    return result == true;
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

  // ============================================================
  // お知らせ(保護者向け一斉配信 = guardian_notices)。Phase D。
  //   閲覧は RLS 依存(保護者は自分が recipient の approved・未取消のみ SELECT 可)。
  //   宛先は自分の recipient 行から導出。既読は mark_guardian_notice_read RPC。
  // ============================================================

  /// お知らせ機能が「いずれかの園児の施設」で有効かを返す(ホームのカード出し分け用)。
  /// フラグ parent_broadcast_notices が未定義/OFF なら false=安全側(非表示)。
  Future<bool> isBroadcastNoticesEnabled(List<LinkedChild> children) async {
    for (final child in children) {
      final flags = await fetchGuardianFeatureFlags(child.childId);
      if (flags.contains('parent_broadcast_notices')) return true;
    }
    return false;
  }

  /// 園児横断のお知らせ一覧(新しい順)。1通=1行に集約し、宛先園児idを束ねる。
  Future<List<GuardianBroadcastNotice>> fetchBroadcastNotices(String guardianId) async {
    // recipient(自分の行)経由で notice を内部結合。RLS で approved・未取消のみが返る。
    final recips = await _client
        .from('guardian_notice_recipients')
        .select(
          'notice_id, child_id, '
          'guardian_notices!inner(id, title, body, sent_at, approved_at, created_at)',
        )
        .eq('guardian_id', guardianId);

    final reads = await _client
        .from('guardian_notice_reads')
        .select('notice_id')
        .eq('guardian_id', guardianId);
    final readIds = (reads as List)
        .cast<Map<String, dynamic>>()
        .map((r) => r['notice_id'] as String)
        .toSet();

    // notice_id ごとに集約。
    final byNotice = <String, Map<String, dynamic>>{};
    final wholeSchool = <String, bool>{};
    final childIds = <String, Set<String>>{};
    for (final row in (recips as List).cast<Map<String, dynamic>>()) {
      final notice = row['guardian_notices'] as Map<String, dynamic>?;
      if (notice == null) continue;
      final id = notice['id'] as String;
      byNotice[id] = notice;
      final childId = row['child_id'] as String?;
      if (childId == null) {
        wholeSchool[id] = true;
      } else {
        (childIds[id] ??= <String>{}).add(childId);
      }
    }

    final list = byNotice.entries.map((e) {
      final n = e.value;
      final ts = (n['sent_at'] ?? n['approved_at'] ?? n['created_at']) as String;
      return GuardianBroadcastNotice(
        id: e.key,
        title: n['title'] as String? ?? '',
        body: n['body'] as String? ?? '',
        sentAt: DateTime.parse(ts),
        isRead: readIds.contains(e.key),
        isWholeSchool: wholeSchool[e.key] ?? false,
        childIds: (childIds[e.key] ?? const <String>{}).toList(),
      );
    }).toList()
      ..sort((a, b) => b.sentAt.compareTo(a.sentAt));
    return list;
  }

  /// 未読件数(ホームのバッジ用)。
  Future<int> fetchBroadcastUnreadCount(String guardianId) async {
    final notices = await fetchBroadcastNotices(guardianId);
    return notices.where((n) => !n.isRead).length;
  }

  /// 既読化(詳細到達時)。RPC 側で二重INSERTを防止済み。
  Future<void> markBroadcastNoticeRead(String noticeId) async {
    await _client.rpc('mark_guardian_notice_read', params: {'p_notice_id': noticeId});
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
    DateTime? endDate,
    String? absenceKind,
    List<String>? medicationKinds,
    String? idDocumentPath,
    String? infectiousDiseaseMasterId,
  }) async {
    await _client.from('parent_requests').insert({
      'child_id': childId,
      'guardian_id': guardianId,
      'request_type': requestType,
      'target_date': _formatDate(targetDate),
      if (endDate != null) 'end_date': _formatDate(endDate),
      'absence_kind': ?absenceKind,
      if (medicationKinds != null && medicationKinds.isNotEmpty) 'medication_kinds': medicationKinds,
      'id_document_path': ?idDocumentPath,
      'infectious_disease_master_id': ?infectiousDiseaseMasterId,
      'details': details,
    });
  }

  /// 感染症管理(205)の機能フラグ。OFF/取得失敗は false(従来動作=案件を作らない)。
  Future<bool> isInfectionControlEnabled(String officeId) async {
    try {
      final data = await _client.rpc('is_infection_control_enabled_for_office', params: {'p_office_id': officeId});
      return data == true;
    } catch (_) {
      return false;
    }
  }

  /// 感染症の手続き表示(206)。進行中案件(病名・登園のめやす・必要書類・様式PDFパス)を返す。
  Future<List<({String caseId, String origin, String status, String? diseaseName, String? returnCriteria,
      String requiredDocument, String documentState, String? formTemplatePath})>>
      fetchMyChildInfectionCases(String childId) async {
    final rows = await _client.rpc('fetch_my_child_infection_cases', params: {'p_child_id': childId});
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      return (
        caseId: m['case_id'] as String,
        origin: m['origin'] as String,
        status: m['status'] as String,
        diseaseName: m['disease_name'] as String?,
        returnCriteria: m['return_criteria'] as String?,
        requiredDocument: m['required_document'] as String,
        documentState: m['document_state'] as String,
        formTemplatePath: m['form_template_path'] as String?,
      );
    }).toList();
  }

  /// 様式PDF(document-templatesバケット)の署名付きURL(5分)。
  Future<String> createDocumentTemplateUrl(String path) async {
    return _client.storage.from('document-templates').createSignedUrl(path, 300);
  }

  /// 一斉配信の添付(208)。RLSで自分宛の承認済みお知らせの分のみ返る。
  Future<List<({String filePath, String fileName, String? contentType})>>
      fetchBroadcastNoticeAttachments(String noticeId) async {
    final rows = await _client
        .from('guardian_notice_attachments')
        .select('file_path, file_name, content_type')
        .eq('notice_id', noticeId)
        .order('sort_order');
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      return (
        filePath: m['file_path'] as String,
        fileName: m['file_name'] as String,
        contentType: m['content_type'] as String?,
      );
    }).toList();
  }

  /// 引き継ぎカード(209)。case_idの最新版カードを返す(RLSで自分の子のみ)。
  Future<Map<String, dynamic>?> fetchLatestHandoverCard(String caseId) async {
    final rows = await _client
        .from('infection_handover_cards')
        .select('*')
        .eq('case_id', caseId)
        .order('version', ascending: false)
        .limit(1);
    final list = rows as List;
    return list.isEmpty ? null : list.first as Map<String, dynamic>;
  }

  /// 受診結果の提出(209)。案件が確定/終了/待ち継続へ遷移する。
  Future<void> submitMedicalVisitReport({
    required String caseId,
    required bool visited,
    DateTime? visitedAt,
    String? medicalInstitution,
    String? diseaseMasterId,
    bool noInfection = false,
    String? doctorNote,
    String? noteToSchool,
  }) async {
    await _client.rpc('submit_medical_visit_report', params: {
      'p_case_id': caseId,
      'p_visited': visited,
      'p_visited_at': visitedAt?.toUtc().toIso8601String(),
      'p_medical_institution': medicalInstitution,
      'p_disease_master_id': diseaseMasterId,
      'p_no_infection': noInfection,
      'p_doctor_note': doctorNote,
      'p_note_to_school': noteToSchool,
    });
  }

  /// 電子登園届(211): 案件のルール定義と既存の下書き/提出済み届を取得。
  Future<({String? diseaseName, String? returnCriteria, List<String> checks,
      String? dateConditionLabel, int? dateConditionMinHours,
      Map<String, dynamic>? notice})> fetchReturnNoticeContext(String caseId) async {
    final caseRow = await _client
        .from('infection_cases')
        .select('disease_master_id, infectious_disease_masters(name, return_criteria, rule_definition)')
        .eq('id', caseId)
        .maybeSingle();
    final master = caseRow?['infectious_disease_masters'] as Map<String, dynamic>?;
    final rule = (master?['rule_definition'] as Map<String, dynamic>?) ?? const {};
    final dateCond = rule['date_condition'] as Map<String, dynamic>?;
    final notice = await _client
        .from('infection_return_notices')
        .select('*')
        .eq('case_id', caseId)
        .maybeSingle();
    return (
      diseaseName: master?['name'] as String?,
      returnCriteria: master?['return_criteria'] as String?,
      checks: ((rule['checks'] as List?) ?? const []).cast<String>(),
      dateConditionLabel: dateCond?['base_label'] as String?,
      dateConditionMinHours: (dateCond?['min_hours'] as num?)?.toInt(),
      notice: notice,
    );
  }

  Future<void> saveReturnNoticeDraft(String caseId, Map<String, dynamic> inputs) async {
    await _client.rpc('save_return_notice_draft', params: {'p_case_id': caseId, 'p_inputs': inputs});
  }

  Future<void> submitReturnNotice(String caseId, Map<String, dynamic> inputs) async {
    await _client.rpc('submit_return_notice', params: {
      'p_case_id': caseId,
      'p_inputs': inputs,
      'p_confirmed': true,
    });
  }

  /// 一斉配信の添付の署名付きURL(5分)。
  Future<String> createBroadcastAttachmentUrl(String path) async {
    return _client.storage.from('guardian-notice-attachments').createSignedUrl(path, 300);
  }

  /// お迎え者身分証明書(202)の機能フラグ。OFF/取得失敗は false=アップロードUIを出さない(安全側)。
  Future<bool> isPickupIdDocumentEnabled(String officeId) async {
    try {
      final data = await _client.rpc('is_pickup_id_document_enabled_for_office', params: {'p_office_id': officeId});
      return data == true;
    } catch (_) {
      return false;
    }
  }

  /// お迎え者マスタ(202)。同一人物(園児×氏名)の既登録・確認済み状態の照合に使う。
  Future<List<PickupPerson>> fetchPickupPersonsForChild(String childId) async {
    final data = await _client.rpc('fetch_pickup_persons_for_child', params: {'p_child_id': childId});
    return (data as List<dynamic>).map((e) => PickupPerson.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 身分証明書画像をアップロードし、storageパスを返す(202)。
  /// パス規約 {child_id}/{ファイル名} はstorageポリシー(保護者=自分の関連児フォルダのみ)と一致させる。
  Future<String> uploadPickupIdDocument({
    required String childId,
    required Uint8List bytes,
  }) async {
    final path = '$childId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from('pickup-id-documents').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return path;
  }

  /// 服薬連絡(201)の機能フラグ。OFF/取得失敗は false=種類プルダウンに出さない(安全側)。
  Future<bool> isMedicationReportEnabled(String officeId) async {
    try {
      final data = await _client.rpc('is_medication_report_enabled_for_office', params: {'p_office_id': officeId});
      return data == true;
    } catch (_) {
      return false;
    }
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

  // ===== 入園時基本情報フォーム(M6 Phase 2・migration 218) =====

  /// フォーム機能が対象園児で有効か(施設フラグ+保護者リンク)。
  Future<bool> isEnrollmentFormEnabled(String childId) async {
    final result = await _client.rpc('is_enrollment_form_enabled_for_child', params: {'p_child_id': childId});
    return result == true;
  }

  /// 自分のフォーム(未作成ならnull)。
  Future<EnrollmentFormState?> fetchEnrollmentForm(String childId) async {
    final rows = await _client.rpc('fetch_my_enrollment_form', params: {'p_child_id': childId});
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return null;
    return EnrollmentFormState.fromJson(list.first);
  }

  /// 初期値(園の仮登録値+兄弟の承認済みフォームからの複製)。
  Future<Map<String, dynamic>> fetchEnrollmentPrefill(String childId) async {
    final result = await _client.rpc('fetch_enrollment_prefill', params: {'p_child_id': childId});
    return (result as Map<String, dynamic>?) ?? <String, dynamic>{};
  }

  /// 下書き保存(無ければ作成)。
  Future<void> saveEnrollmentDraft(String childId, Map<String, dynamic> formData, int currentStep) async {
    try {
      await _client.rpc('save_enrollment_form_draft', params: {
        'p_child_id': childId,
        'p_form_data': formData,
        'p_current_step': currentStep,
      });
    } on PostgrestException catch (e) {
      throw GuardianServiceException(_translateEnrollmentError(e.message));
    }
  }

  /// 提出。戻り値=提出版数。
  Future<int> submitEnrollmentForm(String childId) async {
    try {
      final result = await _client.rpc('submit_enrollment_form', params: {'p_child_id': childId});
      return (result as num).toInt();
    } on PostgrestException catch (e) {
      throw GuardianServiceException(_translateEnrollmentError(e.message));
    }
  }

  /// 変更申請の開始(221)。承認済みフォームを再編集可能な下書きに戻す(承認内容がコピーされる)。
  Future<void> startEnrollmentChangeRequest(String childId) async {
    try {
      await _client.rpc('start_enrollment_change_request', params: {'p_child_id': childId});
    } on PostgrestException catch (e) {
      throw GuardianServiceException(_translateEnrollmentError(e.message));
    }
  }

  // ===== 食材チェック(M6 Phase 4・migration 224) =====

  /// 食材チェックが対象園児で有効か(施設フラグ+保護者リンク)。
  Future<bool> isFoodCheckEnabled(String childId) async {
    final result = await _client.rpc('is_food_check_enabled_for_child', params: {'p_child_id': childId});
    return result == true;
  }

  /// チェックリスト(公開中の最新版+項目ごとの状態)。
  Future<List<Map<String, dynamic>>> fetchFoodChecklist(String childId) async {
    final rows = await _client.rpc('fetch_food_checklist', params: {'p_child_id': childId});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 食材経験の登録。症状ありは園の管理職へ通知される。
  Future<void> recordFoodIntake({
    required String childId,
    required String foodItemId,
    required DateTime intakeDate,
    required bool multipleConfirmed,
    required String result,
    String? symptoms,
    String? onsetNote,
    String? amountNote,
    String? medicalStatus,
    String? note,
  }) async {
    try {
      await _client.rpc('record_food_intake', params: {
        'p_child_id': childId,
        'p_food_item_id': foodItemId,
        'p_intake_date': _formatDate(intakeDate),
        'p_multiple_confirmed': multipleConfirmed,
        'p_result': result,
        'p_symptoms': symptoms,
        'p_onset_note': onsetNote,
        'p_amount_note': amountNote,
        'p_medical_status': medicalStatus,
        'p_note': note,
      });
    } on PostgrestException catch (e) {
      if (e.message.contains('symptoms required')) {
        throw GuardianServiceException('症状の内容を入力してください');
      }
      if (e.message.contains('invalid intake date')) {
        throw GuardianServiceException('摂取日が正しくありません(未来の日付は登録できません)');
      }
      throw GuardianServiceException('登録に失敗しました: ${e.message}');
    }
  }

  String _translateEnrollmentError(String message) {
    if (message.contains('required fields missing')) {
      return '必須項目が入力されていません。各ステップの必須項目をご確認ください';
    }
    if (message.contains('must be acknowledged')) {
      return '平熱が37.5℃以上のため、注意事項の確認にチェックしてから提出してください';
    }
    if (message.contains('not editable') || message.contains('not submittable')) {
      return '現在のフォームの状態では操作できません(園の確認中または承認済みです)';
    }
    return '処理に失敗しました: $message';
  }
}
