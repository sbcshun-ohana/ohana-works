import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/childcare.dart';
import '../models/development_record.dart';
import '../models/guardian_app.dart';
import '../models/nap.dart';

/// AI連絡帳生成の呼び出しに失敗した場合の例外。
class ContactAiException implements Exception {
  ContactAiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// AI生成結果(§11: 連絡帳本文+個人日誌の同時生成)。
class ContactAiResult {
  const ContactAiResult({required this.contactText, this.journalSections});
  final String contactText;
  final Map<String, String>? journalSections;
}

/// 保育業務(Phase1: 連絡帳ワークフロー)を扱うサービス。
/// 職員業務(給与・勤怠等)とは権限ドメインが分離されており、本サービスは
/// is_childcare_enabled_for_office/manages_childcare/has_childcare_office_access等の
/// 保育業務専用RLS・RPCのみを利用する。
class ChildcareService {
  ChildcareService(this._client);

  final SupabaseClient _client;

  static String dateOnly(DateTime date) => date.toIso8601String().substring(0, 10);

  Future<String?> fetchMyEmployeeId() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _client
        .from('employees')
        .select('id')
        .eq('auth_user_id', userId)
        .maybeSingle();
    return row?['id'] as String?;
  }

  /// 保育業務メニュー表示可否・施設選択用: 機能フラグが有効かつアクセス可能な施設一覧。
  Future<List<ChildcareOffice>> fetchMyChildcareOffices() async {
    final rows = await _client.rpc('fetch_my_childcare_offices');
    return (rows as List)
        .map((row) => ChildcareOffice.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Ohana Kids ホーム画面(childcare_home_enabled)が当該施設で有効か。
  /// フラグ未定義/OFF/取得失敗は false=安全側(従来メニュー維持)。
  Future<bool> isChildcareHomeEnabled(String officeId) async {
    try {
      final data = await _client.rpc('is_childcare_home_enabled_for_office', params: {'p_office_id': officeId});
      return data == true;
    } catch (_) {
      return false;
    }
  }


  Future<List<ChildcareClass>> fetchChildcareClasses(String officeId) async {
    final rows = await _client.rpc('fetch_childcare_classes', params: {'p_office_id': officeId});
    return (rows as List)
        .map((row) => ChildcareClass.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<ChildcareStaffMember>> fetchChildcareOfficeStaff(String officeId) async {
    final rows =
        await _client.rpc('fetch_childcare_office_staff', params: {'p_office_id': officeId});
    return (rows as List)
        .map((row) => ChildcareStaffMember.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  // ------------------------------------------------------------------
  // §7 当日の欠席選択
  // ------------------------------------------------------------------

  Future<List<ClassChild>> fetchClassChildren(String classId, DateTime businessDate) async {
    final rows = await _client.rpc('fetch_class_children', params: {
      'p_class_id': classId,
      'p_business_date': dateOnly(businessDate),
    });
    return (rows as List).map((row) => ClassChild.fromJson(row as Map<String, dynamic>)).toList();
  }

  Future<void> setChildDailyAttendance({
    required String childId,
    required DateTime businessDate,
    required bool isAbsent,
    String? absenceReason,
  }) async {
    await _client.rpc('set_child_daily_attendance', params: {
      'p_child_id': childId,
      'p_business_date': dateOnly(businessDate),
      'p_is_absent': isAbsent,
      'p_absence_reason': absenceReason,
    });
  }

  // ------------------------------------------------------------------
  // §8 クラス活動 入力・申請・承認
  // ------------------------------------------------------------------

  Future<List<ClassActivity>> fetchClassActivitiesForOffice(
    String officeId,
    DateTime businessDate,
  ) async {
    final rows = await _client.rpc('fetch_class_activities_for_office', params: {
      'p_office_id': officeId,
      'p_business_date': dateOnly(businessDate),
    });
    return (rows as List)
        .map((row) => ClassActivity.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<String> ensureClassDailyActivity(String classId, DateTime businessDate) async {
    final id = await _client.rpc('ensure_class_daily_activity', params: {
      'p_class_id': classId,
      'p_business_date': dateOnly(businessDate),
    });
    return id as String;
  }

  Future<ClassActivity> fetchClassActivityDetail(String activityId) async {
    final row = await _client
        .from('class_daily_activities')
        // employees への FK が複数(assignee/approved_by)あるため、埋め込みは FK 名で明示する
        // (無指定だと PostgREST が曖昧エラーを返し、詳細取得→claim後の再読込が失敗する)。
        .select('*, childcare_classes(class_name), employees!class_daily_activities_assignee_employee_id_fkey(name)')
        .eq('id', activityId)
        .single();
    final classInfo = row['childcare_classes'] as Map<String, dynamic>?;
    final assignee = row['employees'] as Map<String, dynamic>?;
    return ClassActivity.fromJson({
      'activity_id': row['id'],
      'class_id': row['class_id'],
      'class_name': classInfo?['class_name'] ?? '',
      'assignee_employee_id': row['assignee_employee_id'],
      'assignee_name': assignee?['name'],
      'status': row['status'],
      'today_theme': row['today_theme'],
      'activity_content': row['activity_content'],
      'class_overview': row['class_overview'],
      'class_announcement': row['class_announcement'],
      'other_notes': row['other_notes'],
      'submitted_at': row['submitted_at'],
      'rejected_reason': row['rejected_reason'],
    });
  }

  /// 連絡帳の担当を自分にする(200 claim_child_daily_contact)。未割当のみ・draft/rejectedのみ。
  Future<void> claimDailyContact(String contactId) async {
    await _client.rpc('claim_child_daily_contact', params: {'p_contact_id': contactId});
  }

  Future<void> claimClassActivity(String activityId) async {
    await _client.rpc('claim_class_activity', params: {'p_activity_id': activityId});
  }

  Future<void> reassignClassActivity(String activityId, String newAssigneeEmployeeId) async {
    await _client.rpc('reassign_class_activity', params: {
      'p_activity_id': activityId,
      'p_new_assignee_employee_id': newAssigneeEmployeeId,
    });
  }

  Future<void> updateClassActivityContent(
    String activityId, {
    required String? todayTheme,
    required String? activityContent,
    required String? classOverview,
    required String? classAnnouncement,
    required String? otherNotes,
  }) async {
    await _client.from('class_daily_activities').update({
      'today_theme': todayTheme,
      'activity_content': activityContent,
      'class_overview': classOverview,
      'class_announcement': classAnnouncement,
      'other_notes': otherNotes,
    }).eq('id', activityId);
  }

  Future<void> submitClassActivity(String activityId) async {
    await _client.rpc('submit_class_activity', params: {'p_activity_id': activityId});
  }

  Future<void> approveClassActivity(String activityId) async {
    await _client.rpc('approve_class_activity', params: {'p_activity_id': activityId});
  }

  Future<void> rejectClassActivity(String activityId, String reason) async {
    await _client.rpc('reject_class_activity', params: {
      'p_activity_id': activityId,
      'p_reason': reason,
    });
  }

  // ------------------------------------------------------------------
  // §10-13 連絡帳(個別メモ・AI生成・申請・承認・コピー)
  // ------------------------------------------------------------------

  Future<List<DailyContact>> fetchDailyContactsForOffice(
    String officeId,
    DateTime businessDate,
  ) async {
    final rows = await _client.rpc('fetch_daily_contacts_for_office', params: {
      'p_office_id': officeId,
      'p_business_date': dateOnly(businessDate),
    });
    return (rows as List).map((row) => DailyContact.fromJson(row as Map<String, dynamic>)).toList();
  }

  Future<String> ensureChildDailyContact(String childId, DateTime businessDate) async {
    final id = await _client.rpc('ensure_child_daily_contact', params: {
      'p_child_id': childId,
      'p_business_date': dateOnly(businessDate),
    });
    return id as String;
  }

  DailyContact _dailyContactFromRow(Map<String, dynamic> row) {
    final child = row['children'] as Map<String, dynamic>?;
    final assignee = row['assignee'] as Map<String, dynamic>?;
    final creator = row['creator'] as Map<String, dynamic>?;
    return DailyContact.fromJson({
      'contact_id': row['id'],
      'child_id': row['child_id'],
      'child_display_name': child?['display_name'] ?? '',
      'child_honorific_suffix': child?['honorific_suffix'],
      'class_name': null,
      'assignee_employee_id': row['assignee_employee_id'],
      'assignee_name': assignee?['name'],
      'created_by': row['created_by'],
      'created_by_name': creator?['name'],
      'status': row['status'],
      'guardian_message': row['guardian_message'],
      'child_today_notes': row['child_today_notes'],
      'free_notes': row['free_notes'],
      'ai_generated_text': row['ai_generated_text'],
      'current_text': row['current_text'],
      'admin_comment': row['admin_comment'],
      'rejected_reason': row['rejected_reason'],
      'submitted_at': row['submitted_at'],
      'approved_at': row['approved_at'],
      'copied_at': row['copied_at'],
      'is_absent': false,
      'requires_confirmation': row['requires_confirmation'],
    });
  }

  // employees への FK が複数(assignee/created_by/approved_by/copied_by)あるため FK 名で明示(曖昧エラー防止)。
  static const _dailyContactSelect =
      '*, children(display_name, honorific_suffix), '
      'assignee:employees!child_daily_contacts_assignee_employee_id_fkey(name), '
      'creator:employees!child_daily_contacts_created_by_fkey(name)';

  Future<DailyContact> fetchDailyContactDetail(String contactId) async {
    final row = await _client
        .from('child_daily_contacts')
        .select(_dailyContactSelect)
        .eq('id', contactId)
        .single();
    return _dailyContactFromRow(row);
  }

  /// 園児×営業日の連絡帳を取得(行が無ければ null)。作成ボタン方式のため、行を作らずに取得だけ行う。
  Future<DailyContact?> fetchDailyContactByChildDate(String childId, DateTime businessDate) async {
    final row = await _client
        .from('child_daily_contacts')
        .select(_dailyContactSelect)
        .eq('child_id', childId)
        .eq('business_date', dateOnly(businessDate))
        .maybeSingle();
    if (row == null) return null;
    return _dailyContactFromRow(row);
  }

  Future<List<NoticeMaster>> fetchNoticeMasters(String officeId) async {
    final rows = await _client
        .from('individual_notice_masters')
        .select('id, label, sort_order')
        .eq('office_id', officeId)
        .eq('is_active', true)
        .order('sort_order');
    return (rows as List)
        .map((row) => NoticeMaster.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<Set<String>> fetchCheckedNoticeIds(String contactId) async {
    final rows = await _client
        .from('child_daily_contact_notice_checks')
        .select('notice_master_id')
        .eq('contact_id', contactId);
    return (rows as List).map((row) => row['notice_master_id'] as String).toSet();
  }

  Future<void> setNoticeChecked({
    required String contactId,
    required String noticeMasterId,
    required bool checked,
  }) async {
    if (checked) {
      await _client.from('child_daily_contact_notice_checks').insert({
        'contact_id': contactId,
        'notice_master_id': noticeMasterId,
      });
    } else {
      await _client
          .from('child_daily_contact_notice_checks')
          .delete()
          .eq('contact_id', contactId)
          .eq('notice_master_id', noticeMasterId);
    }
  }

  Future<void> addSupplyItem({
    required String contactId,
    required String itemName,
    required int quantity,
  }) async {
    await _client.from('child_daily_contact_supply_items').insert({
      'contact_id': contactId,
      'item_name': itemName,
      'quantity': quantity,
    });
  }

  Future<List<({String itemName, int quantity})>> fetchSupplyItems(String contactId) async {
    final rows = await _client
        .from('child_daily_contact_supply_items')
        .select('item_name, quantity')
        .eq('contact_id', contactId)
        .order('created_at');
    return (rows as List)
        .map(
          (row) => (
            itemName: row['item_name'] as String,
            quantity: row['quantity'] as int,
          ),
        )
        .toList();
  }

  /// 担当者不在時等に他職員が追加する補足メモ(担当者の入力は上書きしない)。
  Future<void> addSupplement({required String contactId, required String content}) async {
    await _client.from('child_daily_contact_supplements').insert({
      'contact_id': contactId,
      'content': content,
    });
  }

  Future<void> updateDailyContactInput(
    String contactId, {
    required String? guardianMessage,
    required String? childTodayNotes,
    required String? freeNotes,
  }) async {
    await _client.from('child_daily_contacts').update({
      'guardian_message': guardianMessage,
      'child_today_notes': childTodayNotes,
      'free_notes': freeNotes,
    }).eq('id', contactId);
  }

  /// 重要事項として保護者の開封確認を求めるか(328)。true のときのみ保護者アプリに
  /// 「重要事項として確認しました」ボタンが表示される。
  Future<void> setDailyContactRequiresConfirmation(String contactId, bool value) async {
    await _client
        .from('child_daily_contacts')
        .update({'requires_confirmation': value}).eq('id', contactId);
  }

  Future<void> saveCurrentText(String contactId, String text, {required bool isInitial}) async {
    final payload = <String, dynamic>{'current_text': text};
    if (isInitial) payload['ai_generated_text'] = text;
    await _client.from('child_daily_contacts').update(payload).eq('id', contactId);
  }

  /// §11 AI連絡帳作成。generate-contact-note Edge Functionを呼び出す
  /// (現時点ではANTHROPIC_API_KEY未登録のためモック応答)。
  Future<ContactAiResult> generateContactNote({
    required String childId,
    required DateTime businessDate,
    required ContactAiAction action,
    String? currentText,
    String? instruction,
  }) async {
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'generate-contact-note',
        body: {
          'child_id': childId,
          'business_date': dateOnly(businessDate),
          'action': action.code,
          'current_text': ?currentText,
          'instruction': ?instruction,
        },
      );
    } catch (_) {
      throw ContactAiException('AI生成に失敗しました。通信状況を確認してください。');
    }

    if (response.status != 200) {
      throw ContactAiException('AI生成に失敗しました。しばらくしてから再度お試しください。');
    }

    final data = response.data as Map<String, dynamic>;
    final journalSections = data['journal_sections'] != null
        ? (data['journal_sections'] as Map<String, dynamic>).map(
            (key, value) => MapEntry(key, value as String),
          )
        : null;
    return ContactAiResult(contactText: data['contact_text'] as String, journalSections: journalSections);
  }

  /// §16 個人日誌の同時生成(連絡帳と同じ入力から、職員向けの文章を分けて保存する)。
  Future<void> saveGeneratedJournal({
    required String childId,
    required DateTime businessDate,
    required Map<String, String> sections,
  }) async {
    final existing = await _client
        .from('child_personal_journals')
        .select('id')
        .eq('child_id', childId)
        .eq('business_date', dateOnly(businessDate))
        .maybeSingle();

    final payload = {
      'content_fact': sections['fact'],
      'content_support': sections['support'],
      'content_reaction': sections['reaction'],
      'content_progress': sections['progress'],
      'content_consideration': sections['consideration'],
      'content_handover': sections['handover'],
    };

    if (existing != null) {
      await _client.from('child_personal_journals').update({
        ...payload,
        'ai_generated_text': sections.toString(),
        'current_text': sections.toString(),
      }).eq('id', existing['id'] as String);
    } else {
      await _client.from('child_personal_journals').insert({
        'child_id': childId,
        'business_date': dateOnly(businessDate),
        ...payload,
        'ai_generated_text': sections.toString(),
        'current_text': sections.toString(),
      });
    }
  }

  Future<void> submitChildDailyContact(String contactId) async {
    await _client.rpc('submit_child_daily_contact', params: {'p_contact_id': contactId});
  }

  Future<void> approveChildDailyContact(
    String contactId, {
    required String? finalText,
    String? adminComment,
  }) async {
    await _client.rpc('approve_child_daily_contact', params: {
      'p_contact_id': contactId,
      'p_final_text': finalText,
      'p_admin_comment': adminComment,
    });
  }

  Future<void> rejectChildDailyContact(String contactId, String reason) async {
    await _client.rpc('reject_child_daily_contact', params: {
      'p_contact_id': contactId,
      'p_reason': reason,
    });
  }

  Future<void> markChildDailyContactCopied(String contactId) async {
    await _client.rpc('mark_child_daily_contact_copied', params: {'p_contact_id': contactId});
  }

  // ------------------------------------------------------------------
  // 保護者アプリ・後続保育機能(Phase A): デイリーボード
  // ------------------------------------------------------------------

  Future<List<DailyBoardRow>> fetchDailyBoardForOffice(String officeId, DateTime businessDate) async {
    final rows = await _client.rpc('fetch_daily_board_for_office', params: {
      'p_office_id': officeId,
      'p_business_date': dateOnly(businessDate),
    });
    return (rows as List).map((row) => DailyBoardRow.fromJson(row as Map<String, dynamic>)).toList();
  }

  /// 198: デイリーボードの欠席期間表示。承認済み欠席(期間・absence_kind非NULL)のうち
  /// 対象営業日が期間内のものを園児あたり1件返す(在籍クリップ済)。childId→(start,end,kind)。
  /// fetch_daily_board_for_office とは別RPC(ボードRPCは不変)。行内バッジ表示の付加情報。
  Future<Map<String, ({DateTime start, DateTime end, String kind})>> fetchBoardAbsencePeriodsForOffice(
      String officeId, DateTime businessDate) async {
    final rows = await _client.rpc('fetch_board_absence_periods_for_office', params: {
      'p_office_id': officeId,
      'p_business_date': dateOnly(businessDate),
    });
    final map = <String, ({DateTime start, DateTime end, String kind})>{};
    for (final r in (rows as List)) {
      final m = r as Map<String, dynamic>;
      map[m['child_id'] as String] = (
        start: DateTime.parse(m['start_date'] as String),
        end: DateTime.parse(m['end_date'] as String),
        kind: (m['absence_kind'] as String?) ?? '',
      );
    }
    return map;
  }

  /// 在籍登園状況サマリー。classId=null で施設全体、指定でそのクラス単位。
  /// 集計はRPC側に一任し、admin_web/Ohana Kidsで数字を一致させる。
  Future<DailyBoardSummary> fetchDailyBoardSummary(
    String officeId,
    DateTime businessDate, {
    String? classId,
  }) async {
    final rows = await _client.rpc('fetch_daily_board_summary_for_office', params: {
      'p_office_id': officeId,
      'p_business_date': dateOnly(businessDate),
      'p_class_id': classId,
    });
    final list = rows as List;
    if (list.isEmpty) {
      return const DailyBoardSummary(enrolled: 0, expected: 0, attended: 0, absent: 0, presentNow: 0);
    }
    return DailyBoardSummary.fromJson(list.first as Map<String, dynamic>);
  }

  /// 天気記録(施設×日で1行)。RLS(施設アクセス)で直接select。未入力なら null。
  Future<WeatherRecord?> fetchDailyWeather(String officeId, DateTime businessDate) async {
    final row = await _client
        .from('daily_weather_records')
        .select('weather, temperature, humidity')
        .eq('office_id', officeId)
        .eq('record_date', dateOnly(businessDate))
        .maybeSingle();
    if (row == null) return null;
    return WeatherRecord.fromJson(row);
  }

  /// 天気の記録(upsert)。当日は誰でも、過去日/未来日は主任以上(RPC側でガード)。
  Future<void> upsertDailyWeather(
    String officeId,
    DateTime businessDate, {
    required String weather,
    double? temperature,
    double? humidity,
  }) async {
    await _client.rpc('upsert_daily_weather_record', params: {
      'p_office_id': officeId,
      'p_record_date': dateOnly(businessDate),
      'p_weather': weather,
      'p_temperature': temperature,
      'p_humidity': humidity,
    });
  }

  /// 代理登降園の登録(主任以上)。QRと区別して proxy_* で記録し、通知ON時は保護者へプッシュ。
  /// occurredAt は対象日+手入力時刻の実時刻(timestamptz)を渡す。
  Future<void> recordStaffManualAttendance({
    required String childId,
    required String eventType, // 'drop_off' | 'pick_up'
    required DateTime occurredAt,
    required bool notifyGuardian,
  }) async {
    await _client.rpc('record_staff_manual_attendance', params: {
      'p_child_id': childId,
      'p_event_type': eventType,
      'p_occurred_at': occurredAt.toUtc().toIso8601String(),
      'p_notify_guardian': notifyGuardian,
    });
  }

  /// 連絡帳(職員→保護者)の公開予約(既定17:00)。対象は approved かつ未公開の contact_id 群。
  /// scheduledAt は対象日+時刻(JST壁時計)を UTC 実時刻へ変換して渡す(端末TZ非依存)。
  Future<void> scheduleDailyContacts(List<String> contactIds, DateTime scheduledAt) async {
    if (contactIds.isEmpty) return;
    await _client.rpc('schedule_child_daily_contacts', params: {
      'p_contact_ids': contactIds,
      'p_scheduled_at': scheduledAt.toUtc().toIso8601String(),
    });
  }

  Future<void> publishDailyContactsNow(List<String> contactIds) async {
    if (contactIds.isEmpty) return;
    await _client.rpc('publish_child_daily_contacts_now', params: {'p_contact_ids': contactIds});
  }

  Future<void> cancelDailyContactsSchedule(List<String> contactIds) async {
    if (contactIds.isEmpty) return;
    await _client.rpc('cancel_child_daily_contacts_schedule', params: {'p_contact_ids': contactIds});
  }

  // ------------------------------------------------------------------
  // 午睡チェック(Phase 3): migration 168〜170
  // ------------------------------------------------------------------

  Future<List<NapSessionRow>> fetchNapBoard(String officeId, DateTime date, {String? classId}) async {
    final rows = await _client.rpc('fetch_nap_board', params: {
      'p_office_id': officeId,
      'p_class_id': classId,
      'p_session_date': dateOnly(date),
    });
    return (rows as List).map((r) => NapSessionRow.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// 午睡名簿(登園済み=present/picked_up かつ非欠席の在籍児のみ・258)。年齢順。
  Future<List<({String childId, String nameLabel, String className})>> fetchNapRoster(
    String officeId,
    DateTime date, {
    String? classId,
  }) async {
    final rows = await _client.rpc('fetch_nap_roster', params: {
      'p_office_id': officeId,
      'p_class_id': classId,
      'p_business_date': dateOnly(date),
    }) as List;
    return [
      for (final r in rows)
        (
          childId: (r as Map<String, dynamic>)['child_id'] as String,
          nameLabel: '${r['display_name']}${r['honorific_suffix'] ?? ''}',
          className: (r['class_name'] as String?) ?? '',
        ),
    ];
  }

  Future<List<NapMissing>> fetchNapMissingSlots(String officeId, DateTime date) async {
    final rows = await _client.rpc('fetch_nap_missing_slots', params: {
      'p_office_id': officeId,
      'p_session_date': dateOnly(date),
    });
    return (rows as List).map((r) => NapMissing.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<void> startNapSession(String childId, DateTime sleepStartAt) async {
    await _client.rpc('start_nap_session', params: {
      'p_child_id': childId,
      'p_sleep_start_at': sleepStartAt.toUtc().toIso8601String(),
    });
  }

  Future<void> startNapSessionsForClass(String classId, DateTime sleepStartAt) async {
    await _client.rpc('start_nap_sessions_for_class', params: {
      'p_class_id': classId,
      'p_sleep_start_at': sleepStartAt.toUtc().toIso8601String(),
    });
  }

  Future<void> endNapSession(String sessionId, DateTime wakeUpAt) async {
    await _client.rpc('end_nap_session', params: {
      'p_session_id': sessionId,
      'p_wake_up_at': wakeUpAt.toUtc().toIso8601String(),
    });
  }

  Future<int> endNapSessionsForClass(String classId, DateTime date, DateTime wakeUpAt) async {
    final r = await _client.rpc('end_nap_sessions_for_class', params: {
      'p_class_id': classId,
      'p_session_date': dateOnly(date),
      'p_wake_up_at': wakeUpAt.toUtc().toIso8601String(),
    });
    return (r as int?) ?? 0;
  }

  Future<void> recordNapCheck(
    String sessionId,
    DateTime slotAt, {
    required String bodyPosition,
    required bool breathing,
    required bool complexion,
    required bool bedding,
  }) async {
    await _client.rpc('record_nap_check', params: {
      'p_session_id': sessionId,
      'p_slot_at': slotAt.toUtc().toIso8601String(),
      'p_body_position': bodyPosition,
      'p_breathing': breathing,
      'p_complexion': complexion,
      'p_bedding': bedding,
    });
  }

  Future<void> copyPreviousNapCheck(String sessionId, DateTime slotAt) async {
    await _client.rpc('copy_previous_nap_check', params: {
      'p_session_id': sessionId,
      'p_slot_at': slotAt.toUtc().toIso8601String(),
    });
  }

  Future<int> copyPreviousNapChecksForClass(String classId, DateTime date, DateTime slotAt) async {
    final r = await _client.rpc('copy_previous_nap_checks_for_class', params: {
      'p_class_id': classId,
      'p_session_date': dateOnly(date),
      'p_slot_at': slotAt.toUtc().toIso8601String(),
    });
    return (r as int?) ?? 0;
  }

  // ------------------------------------------------------------------
  // 出欠状況/登降園実績/週次標準/園側検温 (migration 184〜188)
  // ------------------------------------------------------------------

  /// 出欠モーダルの保存(185)。種別/当日予定override/メモ。is_absentはRPC側で種別から同期。
  Future<void> setChildAttendanceStatus(
    String childId,
    DateTime businessDate,
    String? attendanceKind, {
    String? scheduledStart, // 'HH:MM'
    String? scheduledEnd,
    String? scheduledSlot,
    String? attendanceNote,
  }) async {
    await _client.rpc('set_child_attendance_status', params: {
      'p_child_id': childId,
      'p_business_date': dateOnly(businessDate),
      'p_attendance_kind': attendanceKind,
      'p_scheduled_start': scheduledStart,
      'p_scheduled_end': scheduledEnd,
      'p_scheduled_slot': scheduledSlot,
      'p_attendance_note': attendanceNote,
    });
  }

  /// 登降園実績の手動修正(187/381)。全置換=現在値を全4値プリフィルして渡すこと。NULL=クリア。
  /// outingReason=外出理由(therapy/checkup/other)。外時刻とセットで保存(381)。
  Future<void> setChildAttendanceActuals(
    String childId,
    DateTime businessDate, {
    String? inAt, // 'HH:MM'
    String? outAt,
    String? returnAt,
    String? departAt,
    String? outingReason,
  }) async {
    await _client.rpc('set_child_attendance_actuals', params: {
      'p_child_id': childId,
      'p_business_date': dateOnly(businessDate),
      'p_in': inAt,
      'p_out': outAt,
      'p_return': returnAt,
      'p_depart': departAt,
      'p_outing_reason': outingReason,
    });
  }

  /// 当日の外出理由(最新'out'の outing_reason)を取得(382・出欠編集のプリフィル用)。
  Future<String?> fetchChildOutReason(String childId, DateTime businessDate) async {
    final r = await _client.rpc('fetch_child_out_reason', params: {
      'p_child_id': childId,
      'p_business_date': dateOnly(businessDate),
    });
    return r as String?;
  }

  /// 園側検温の記録(188・upsert)。measuredAt='HH:MM'。
  Future<void> recordChildTemperature(
    String childId,
    DateTime businessDate,
    String measuredAt,
    double temperature,
  ) async {
    await _client.rpc('record_child_temperature', params: {
      'p_child_id': childId,
      'p_business_date': dateOnly(businessDate),
      'p_measured_at': measuredAt,
      'p_temperature': temperature,
    });
  }

  Future<void> deleteChildTemperature(String childId, DateTime businessDate, String measuredAt) async {
    await _client.rpc('delete_child_temperature', params: {
      'p_child_id': childId,
      'p_business_date': dateOnly(businessDate),
      'p_measured_at': measuredAt,
    });
  }

  /// 健康チェック一括取得(199)。施設×日の全在籍園児の 排便/ミルク/食事 と birth_date。
  /// childId→(birthDate, toileting, milk, meals)。排便のper-child並列取得(N+1)をこれで置換。
  Future<Map<String,
          ({
            DateTime birthDate,
            List<({String time, String type})> toileting,
            List<({String time, int amountMl})> milk,
            Map<String, String> meals
          })>>
      fetchHealthCheckForOffice(String officeId, DateTime businessDate) async {
    final rows = await _client.rpc('fetch_health_check_for_office', params: {
      'p_office_id': officeId,
      'p_business_date': dateOnly(businessDate),
    });
    final map = <String,
        ({
          DateTime birthDate,
          List<({String time, String type})> toileting,
          List<({String time, int amountMl})> milk,
          Map<String, String> meals
        })>{};
    for (final r in (rows as List)) {
      final m = r as Map<String, dynamic>;
      // 仮登録(入園予定)児は birth_date が null。健康チェック対象外なのでスキップ(217でnullable化)。
      if (m['birth_date'] == null) continue;
      final toileting = ((m['toileting_records'] as List?) ?? const [])
          .map((e) => (time: (e['time'] as String?) ?? '', type: (e['type'] as String?) ?? ''))
          .toList();
      final milk = ((m['milk_records'] as List?) ?? const [])
          .map((e) => (time: (e['time'] as String?) ?? '', amountMl: (e['amount_ml'] as num?)?.toInt() ?? 0))
          .toList();
      final meals = <String, String>{};
      final mealsRaw = m['meal_records'] as Map<String, dynamic>?;
      if (mealsRaw != null) {
        for (final e in mealsRaw.entries) {
          if (e.value is String) meals[e.key] = e.value as String;
        }
      }
      map[m['child_id'] as String] = (
        birthDate: DateTime.parse(m['birth_date'] as String),
        toileting: toileting,
        milk: milk,
        meals: meals,
      );
    }
    return map;
  }

  /// ミルク記録の追加(199 add_milk_record)。timeは "HH:MM"、amountMlは1〜500。
  Future<void> addMilkRecord(String childId, DateTime businessDate, String time, int amountMl) async {
    await _client.rpc('add_milk_record', params: {
      'p_child_id': childId,
      'p_business_date': dateOnly(businessDate),
      'p_time': time,
      'p_amount_ml': amountMl,
    });
  }

  /// ミルク記録の削除(199 delete_milk_record)。indexは milk_records 配列の位置。
  Future<void> deleteMilkRecord(String childId, DateTime businessDate, int index) async {
    await _client.rpc('delete_milk_record', params: {
      'p_child_id': childId,
      'p_business_date': dateOnly(businessDate),
      'p_index': index,
    });
  }

  /// 食事分量の設定(199 set_meal_record)。slot=am_snack/lunch/pm_snack。amount=nullで未記録に戻す。
  Future<void> setMealRecord(String childId, DateTime businessDate, String slot, String? amount) async {
    await _client.rpc('set_meal_record', params: {
      'p_child_id': childId,
      'p_business_date': dateOnly(businessDate),
      'p_slot': slot,
      'p_amount': amount,
    });
  }

  /// 排便記録の取得(194 fetch_toileting_records)。連絡帳の toileting_records と同一実体。
  Future<List<({String time, String type})>> fetchToiletingRecords(String childId, DateTime businessDate) async {
    final data = await _client.rpc('fetch_toileting_records', params: {
      'p_child_id': childId,
      'p_business_date': dateOnly(businessDate),
    });
    return (data as List).map((e) {
      final m = e as Map<String, dynamic>;
      return (time: (m['time'] as String?) ?? '', type: (m['type'] as String?) ?? '');
    }).toList();
  }

  /// 排便記録の追加(194 add_toileting_record)。timeは "HH:MM"。
  Future<void> addToiletingRecord(String childId, DateTime businessDate, String time, String type) async {
    await _client.rpc('add_toileting_record', params: {
      'p_child_id': childId,
      'p_business_date': dateOnly(businessDate),
      'p_time': time,
      'p_type': type,
    });
  }

  /// 排便記録の削除(194 delete_toileting_record)。indexは toileting_records 配列の位置。
  Future<void> deleteToiletingRecord(String childId, DateTime businessDate, int index) async {
    await _client.rpc('delete_toileting_record', params: {
      'p_child_id': childId,
      'p_business_date': dateOnly(businessDate),
      'p_index': index,
    });
  }

  /// 検温一覧(188)。園児×記録時刻の行。
  Future<List<ChildTemperatureRecord>> fetchChildTemperaturesForOffice(String officeId, DateTime businessDate) async {
    final rows = await _client.rpc('fetch_child_temperatures_for_office', params: {
      'p_office_id': officeId,
      'p_business_date': dateOnly(businessDate),
    });
    return (rows as List).map((r) => ChildTemperatureRecord.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// K8用: 園児ごとの園側検温の最新値(188)。childId→(temp, time)。
  Future<Map<String, ({double temperature, String measuredAt})>> fetchChildLatestTemperaturesForOffice(
      String officeId, DateTime businessDate) async {
    final rows = await _client.rpc('fetch_child_latest_temperatures_for_office', params: {
      'p_office_id': officeId,
      'p_business_date': dateOnly(businessDate),
    });
    final map = <String, ({double temperature, String measuredAt})>{};
    for (final r in (rows as List)) {
      final m = r as Map<String, dynamic>;
      map[m['child_id'] as String] = (
        temperature: double.parse(m['latest_temperature'].toString()),
        measuredAt: (m['latest_measured_at'] as String?) ?? '',
      );
    }
    return map;
  }

  /// 198方式: ボードの服薬表示(201)。承認済み服薬連絡を childId→(種類, 解熱剤フラグ, 様子)で返す。
  Future<Map<String, ({List<String> kinds, bool hasAntipyretic, String? symptom})>>
      fetchBoardMedicationForOffice(String officeId, DateTime businessDate) async {
    final rows = await _client.rpc('fetch_board_medication_for_office', params: {
      'p_office_id': officeId,
      'p_business_date': dateOnly(businessDate),
    });
    final map = <String, ({List<String> kinds, bool hasAntipyretic, String? symptom})>{};
    for (final r in (rows as List)) {
      final m = r as Map<String, dynamic>;
      map[m['child_id'] as String] = (
        kinds: ((m['medication_kinds'] as List?) ?? const []).cast<String>(),
        hasAntipyretic: m['has_antipyretic'] == true,
        symptom: m['symptom'] as String?,
      );
    }
    return map;
  }

  /// Phase C(315): 一時外出。指定日の「外出中」の児を childId→レコードで返す(バッジ用。戻り済は除外)。
  Future<Map<String, ({String id, String reason, String? reasonNote, DateTime? returnPlannedAt, DateTime? outAt, bool isOverdue})>>
      fetchChildOutingsForOffice(String officeId, DateTime businessDate) async {
    final rows = await _client.rpc('fetch_child_outings_for_office', params: {
      'p_office_id': officeId,
      'p_business_date': dateOnly(businessDate),
    });
    final map = <String, ({String id, String reason, String? reasonNote, DateTime? returnPlannedAt, DateTime? outAt, bool isOverdue})>{};
    for (final r in (rows as List)) {
      final m = r as Map<String, dynamic>;
      if (m['is_active'] != true) continue; // バッジ表示は外出中のみ
      map[m['child_id'] as String] = (
        id: m['id'] as String,
        reason: m['reason'] as String,
        reasonNote: m['reason_note'] as String?,
        returnPlannedAt: m['return_planned_at'] != null ? DateTime.parse(m['return_planned_at'] as String) : null,
        outAt: m['out_at'] != null ? DateTime.parse(m['out_at'] as String) : null,
        isOverdue: m['is_overdue'] == true,
      );
    }
    return map;
  }

  /// 一時外出を開始(職員明示操作・理由+戻り予定必須)。
  Future<void> startChildOuting(String childId, String reason, String? reasonNote, DateTime returnPlannedAt) async {
    await _client.rpc('start_child_outing', params: {
      'p_child_id': childId,
      'p_reason': reason,
      'p_reason_note': reasonNote,
      'p_return_planned_at': returnPlannedAt.toUtc().toIso8601String(),
    });
  }

  /// 一時外出の「戻り(再入室)」を記録。
  Future<void> endChildOuting(String outingId) async {
    await _client.rpc('end_child_outing', params: {'p_id': outingId});
  }

  /// 一時外出→降園変換(主任以上・降園記録込み)。
  Future<void> convertOutingToDeparture(String outingId) async {
    await _client.rpc('convert_outing_to_departure', params: {'p_id': outingId});
  }

  /// 198方式: ボードのお迎え変更表示(202)。承認済みお迎え変更を childId→リストで返す
  /// (同児で複数申請があり得るためリスト。氏名・時間・確認済み・書類有無)。
  Future<Map<String, List<({String? name, String? relationship, String? arrive, String? leave, bool idVerified, bool hasDocument})>>>
      fetchBoardPickupChangesForOffice(String officeId, DateTime businessDate) async {
    final rows = await _client.rpc('fetch_board_pickup_changes_for_office', params: {
      'p_office_id': officeId,
      'p_business_date': dateOnly(businessDate),
    });
    final map = <String, List<({String? name, String? relationship, String? arrive, String? leave, bool idVerified, bool hasDocument})>>{};
    for (final r in (rows as List)) {
      final m = r as Map<String, dynamic>;
      (map[m['child_id'] as String] ??= []).add((
        name: m['person_name'] as String?,
        relationship: m['relationship'] as String?,
        arrive: m['arrive_time'] as String?,
        leave: m['leave_time'] as String?,
        idVerified: m['id_verified'] == true,
        hasDocument: m['has_document'] == true,
      ));
    }
    return map;
  }

  /// お迎え者マスタ(202)。実物確認チェックの対象person_id解決に使う。
  Future<List<({String personId, String name, bool hasDocument, bool idVerified})>>
      fetchPickupPersonsForChild(String childId) async {
    final rows = await _client.rpc('fetch_pickup_persons_for_child', params: {'p_child_id': childId});
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      return (
        personId: m['person_id'] as String,
        name: m['name'] as String,
        hasDocument: m['has_document'] == true,
        idVerified: m['id_verified'] == true,
      );
    }).toList();
  }

  /// 身分証の実物確認済みチェック(202・主任以上)。
  Future<void> setPickupPersonIdVerified(String personId, bool verified) async {
    await _client.rpc('set_pickup_person_id_verified', params: {
      'p_person_id': personId,
      'p_verified': verified,
    });
  }

  /// 欠席児童一覧の「保護者からの連絡」。承認済み欠席申請の details['理由'] を
  /// child_id→コメントで返す(admin_webと同じ直接select・RLSでstaff読取可)。
  Future<Map<String, String>> fetchApprovedAbsenceCommentsForOffice(String officeId, DateTime businessDate) async {
    final date = dateOnly(businessDate);
    final rows = await _client
        .from('parent_requests')
        .select('child_id, details, target_date, end_date, children!inner(office_id)')
        .eq('children.office_id', officeId)
        .eq('status', 'approved')
        .eq('request_type', 'absence')
        .lte('target_date', date);
    final map = <String, String>{};
    for (final r in (rows as List)) {
      final m = r as Map<String, dynamic>;
      final end = (m['end_date'] as String?) ?? (m['target_date'] as String);
      if (end.compareTo(date) < 0) continue; // 対象日が期間内のもののみ
      final reason = (m['details'] as Map<String, dynamic>?)?['理由'] as String?;
      if (reason != null && reason.isNotEmpty) map[m['child_id'] as String] = reason;
    }
    return map;
  }

  /// ボードの遅刻・早退バッジ用。対象日の承認済み 遅刻(tardiness)/早退(early_leave) 申請を
  /// childId→リストで返す(details の 到着予定時刻/降園予定時刻・理由。直接select・RLSでstaff可)。
  Future<Map<String, List<({String type, String? time, String? reason})>>>
      fetchApprovedTimeChangeRequestsForOffice(String officeId, DateTime businessDate) async {
    final rows = await _client
        .from('parent_requests')
        .select('child_id, request_type, details, children!inner(office_id)')
        .eq('children.office_id', officeId)
        .eq('status', 'approved')
        .inFilter('request_type', ['tardiness', 'early_leave'])
        .eq('target_date', dateOnly(businessDate));
    final map = <String, List<({String type, String? time, String? reason})>>{};
    for (final r in (rows as List)) {
      final m = r as Map<String, dynamic>;
      final details = (m['details'] as Map<String, dynamic>?) ?? const {};
      final type = m['request_type'] as String;
      (map[m['child_id'] as String] ??= []).add((
        type: type,
        time: (type == 'tardiness' ? details['到着予定時刻'] : details['降園予定時刻']) as String?,
        reason: details['理由'] as String?,
      ));
    }
    return map;
  }

  /// ボードの感染症案件バッジ用(206/216・198方式)。進行中案件を childId→リストで返す。
  Future<Map<String, List<({String caseId, String status, String? diseaseName, String requiredDocument,
      String documentState, String? receivedByName, DateTime? receivedAt})>>>
      fetchBoardInfectionCasesForOffice(String officeId) async {
    final rows = await _client.rpc('fetch_board_infection_cases_for_office', params: {'p_office_id': officeId});
    final map = <String, List<({String caseId, String status, String? diseaseName, String requiredDocument,
        String documentState, String? receivedByName, DateTime? receivedAt})>>{};
    for (final r in (rows as List)) {
      final m = r as Map<String, dynamic>;
      (map[m['child_id'] as String] ??= []).add((
        caseId: m['case_id'] as String,
        status: m['status'] as String,
        diseaseName: m['disease_name'] as String?,
        requiredDocument: m['required_document'] as String,
        documentState: m['document_state'] as String,
        receivedByName: m['received_by_name'] as String?,
        receivedAt: m['received_at'] != null ? DateTime.parse(m['received_at'] as String).toLocal() : null,
      ));
    }
    return map;
  }

  /// 連絡帳の担当者変更(207)。下書き/差し戻し中のみ・施設在籍職員へ。
  Future<void> setDailyContactAssignee(String contactId, String employeeId) async {
    await _client.rpc('set_child_daily_contact_assignee', params: {
      'p_contact_id': contactId,
      'p_employee_id': employeeId,
    });
  }

  /// 引き継ぎカード(209): 起点Aの案件作成(進行中があれば再利用)。
  Future<String> createInfectionHandoverCase(String childId) async {
    final data = await _client.rpc('create_infection_handover_case', params: {'p_child_id': childId});
    return data as String;
  }

  /// 引き継ぎカード送信(209)。スナップショットはサーバー側で固定される。
  Future<String> sendHandoverCard({
    required String caseId,
    required String hives,
    required String rash,
    List<String>? rashLocations,
    String? rashLocationOther,
    String? freeNote,
    String? guardianMessage,
  }) async {
    final data = await _client.rpc('send_handover_card', params: {
      'p_case_id': caseId,
      'p_hives': hives,
      'p_rash': rash,
      'p_rash_locations': rashLocations,
      'p_rash_location_other': rashLocationOther,
      'p_free_note': freeNote,
      'p_guardian_message': guardianMessage,
    });
    return data as String;
  }

  /// 園内感染症の参考表示(209・同一施設・過去7日)。
  Future<List<({String disease, int count})>> fetchInfectionReferenceCounts(String officeId) async {
    final rows = await _client.rpc('fetch_infection_reference_counts', params: {'p_office_id': officeId});
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      return (disease: m['disease_name'] as String, count: (m['report_count'] as num).toInt());
    }).toList();
  }

  /// カード作成画面のプレビュー(209): 当日の検温・排便(RLS直接select)。
  Future<({List<({String time, double temperature})> temps, List<({String time, String type})> toileting})>
      fetchHandoverPreview(String childId, DateTime businessDate) async {
    final date = dateOnly(businessDate);
    final temps = await _client
        .from('child_temperature_records')
        .select('measured_at, temperature')
        .eq('child_id', childId)
        .eq('business_date', date)
        .order('measured_at');
    final contact = await _client
        .from('child_daily_contacts')
        .select('toileting_records')
        .eq('child_id', childId)
        .eq('business_date', date)
        .maybeSingle();
    final toilet = ((contact?['toileting_records'] as List?) ?? const [])
        .map((e) => (
              time: (e as Map<String, dynamic>)['time'] as String? ?? '',
              type: e['type'] as String? ?? '',
            ))
        .toList();
    return (
      temps: (temps as List)
          .map((r) => (
                time: ((r as Map<String, dynamic>)['measured_at'] as String).substring(0, 5),
                temperature: (r['temperature'] as num).toDouble(),
              ))
          .toList(),
      toileting: toilet,
    );
  }

  /// 紙書類の受領記録(211・一般職員可)。記録成立で書類充足(received_on_paper)。
  Future<void> recordPaperDocumentReceipt(String caseId, {String? note}) async {
    await _client.rpc('record_paper_document_receipt', params: {
      'p_case_id': caseId,
      'p_received_method': 'paper',
      'p_note': note,
    });
  }

  // ------------------------------------------------------------------
  // 園内連絡(156/213・職員間コミュニケーション)
  // ------------------------------------------------------------------

  /// 一覧(213)。既定=直近30日。宛先ラベル・自分宛て・確認状況込み。
  Future<List<({String messageId, String body, DateTime? targetDate, DateTime createdAt,
      String authorEmployeeId, String authorName, List<String> targetLabels,
      bool isAddressedToMe, bool acknowledgedByMe, int ackCount, int addressedCount})>>
      fetchStaffMessages(String officeId, {bool includeArchive = false}) async {
    final rows = await _client.rpc('fetch_staff_messages', params: {
      'p_office_id': officeId,
      'p_include_archive': includeArchive,
    });
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      return (
        messageId: m['message_id'] as String,
        body: m['body'] as String,
        targetDate: m['target_date'] != null ? DateTime.parse(m['target_date'] as String) : null,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        authorEmployeeId: m['author_employee_id'] as String,
        authorName: m['author_name'] as String,
        targetLabels: ((m['target_labels'] as List?) ?? const []).cast<String>(),
        isAddressedToMe: m['is_addressed_to_me'] == true,
        acknowledgedByMe: m['acknowledged_by_me'] == true,
        ackCount: (m['ack_count'] as num?)?.toInt() ?? 0,
        addressedCount: (m['addressed_count'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  /// 送信(156)。targets例: [{'type':'facility'},{'type':'individual','employee_id':...},
  /// {'type':'band','band_id':...},{'type':'class','class_id':...}]
  Future<String> createStaffMessage({
    required String officeId,
    required String body,
    DateTime? targetDate,
    required List<Map<String, dynamic>> targets,
  }) async {
    final data = await _client.rpc('create_staff_message', params: {
      'p_office_id': officeId,
      'p_body': body,
      'p_target_date': targetDate != null ? dateOnly(targetDate) : null,
      'p_targets': targets,
    });
    return data as String;
  }

  Future<void> acknowledgeStaffMessage(String messageId) async {
    await _client.rpc('acknowledge_staff_message', params: {'p_message_id': messageId});
  }

  Future<void> deleteStaffMessage(String messageId) async {
    await _client.rpc('delete_staff_message', params: {'p_message_id': messageId});
  }

  /// 自分宛て未確認件数(156)。ホームタイルのバッジ・ログイン後バナー用。
  Future<int> fetchMyUnacknowledgedStaffMessageCount(String officeId) async {
    final data = await _client
        .rpc('fetch_my_unacknowledged_staff_message_count', params: {'p_office_id': officeId});
    return (data as num?)?.toInt() ?? 0;
  }

  /// 時間帯マスタ(RLS直接select)。宛先選択用。
  Future<List<({String bandId, String name})>> fetchStaffTimeBands(String officeId) async {
    final rows = await _client
        .from('staff_time_bands')
        .select('id, name')
        .eq('office_id', officeId)
        .order('sort_order');
    return (rows as List)
        .map((r) => (bandId: (r as Map<String, dynamic>)['id'] as String, name: r['name'] as String))
        .toList();
  }

  /// クラス宛て機能フラグ(6.4・大和のみON)。
  Future<bool> isClassMessagingEnabled(String officeId) async {
    try {
      final data = await _client
          .rpc('is_feature_enabled_for_office', params: {'p_feature_key': 'class_messaging_enabled', 'p_office_id': officeId});
      return data == true;
    } catch (_) {
      return false;
    }
  }

  /// 週次標準保育時間の取得(184)。曜日(1:月..7:日)→(start,end)。
  Future<Map<int, ({String? start, String? end})>> fetchChildWeeklySchedule(String childId) async {
    final rows = await _client.rpc('fetch_child_weekly_schedule', params: {'p_child_id': childId});
    final map = <int, ({String? start, String? end})>{};
    for (final r in (rows as List)) {
      final m = r as Map<String, dynamic>;
      map[m['weekday'] as int] = (
        start: m['scheduled_start_at'] as String?,
        end: m['scheduled_end_at'] as String?,
      );
    }
    return map;
  }

  /// 週次標準の設定(184・主任以上)。weekday=1:月..7:日、時刻='HH:MM'。
  Future<void> setChildWeeklySchedule(String childId, int weekday, String start, String end) async {
    await _client.rpc('set_child_weekly_schedule', params: {
      'p_child_id': childId,
      'p_weekday': weekday,
      'p_start': start,
      'p_end': end,
    });
  }

  /// 週次標準の削除(184・主任以上)=その曜日は通わない。
  Future<void> deleteChildWeeklySchedule(String childId, int weekday) async {
    await _client.rpc('delete_child_weekly_schedule', params: {
      'p_child_id': childId,
      'p_weekday': weekday,
    });
  }

  /// 家庭連絡帳(保護者記入)の職員側閲覧。RLS(family_daily_reports_select)で
  /// staff_has_guardian_data_access(child_id)により保護のため直接SELECTでよい。
  Future<FamilyDailyReportSummary?> fetchFamilyDailyReportForStaff(
    String childId,
    DateTime businessDate,
  ) async {
    final row = await _client
        .from('family_daily_reports')
        .select()
        .eq('child_id', childId)
        .eq('business_date', dateOnly(businessDate))
        .maybeSingle();
    if (row == null) return null;
    return FamilyDailyReportSummary.fromJson(row);
  }

  /// 指定月に家庭連絡帳(提出済み)がある日付の集合(yyyy-MM-dd)。家庭連絡帳タブの日付一覧用。
  Future<Set<String>> fetchFamilyReportDatesInMonth(String childId, DateTime month) async {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0);
    final rows = await _client
        .from('family_daily_reports')
        .select('business_date, status')
        .eq('child_id', childId)
        .eq('status', 'submitted')
        .gte('business_date', dateOnly(start))
        .lte('business_date', dateOnly(end)) as List;
    return {
      for (final r in rows) (r as Map<String, dynamic>)['business_date'] as String,
    };
  }

  /// 家庭での様子 一覧: 施設×日の提出済み家庭連絡帳を全園児分。
  /// 新規RPCは作らず、既存RLS(family_daily_reports_select = staff_has_guardian_data_access)で保護された
  /// 直接selectを用いる(children!inner で office 絞り込み)。DB変更なし。
  Future<List<FamilyReportListItem>> fetchFamilyDailyReportsForOffice(
    String officeId,
    DateTime businessDate,
  ) async {
    final rows = await _client
        .from('family_daily_reports')
        .select('*, children!inner(display_name, honorific_suffix, office_id, enrollment_status)')
        .eq('business_date', dateOnly(businessDate))
        .eq('children.office_id', officeId)
        .eq('status', 'submitted');
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      final child = m['children'] as Map<String, dynamic>;
      return FamilyReportListItem(
        childId: m['child_id'] as String,
        displayName: child['display_name'] as String,
        honorificSuffix: child['honorific_suffix'] as String?,
        report: FamilyDailyReportSummary.fromJson(m),
      );
    }).toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  /// daily_child_statusの変更をRealtimeで購読する(登降園は保護者アプリ・キオスク端末など
  /// 複数端末から行われるため、複数端末への即時反映が必要)。呼び出し側でchannelを保持し、
  /// 画面破棄時にunsubscribe()すること。
  RealtimeChannel watchDailyChildStatus(String officeId, void Function() onChange) {
    final channel = _client.channel('daily_board_$officeId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'daily_child_status',
          callback: (payload) => onChange(),
        )
        .subscribe();
    return channel;
  }

  // ------------------------------------------------------------------
  // 保護者アプリ・後続保育機能(Phase A): 保護者管理・招待管理
  // ------------------------------------------------------------------

  Future<List<ChildForInvitation>> fetchChildrenForOffice(String officeId) async {
    final rows = await _client.rpc('fetch_children_for_office', params: {'p_office_id': officeId});
    return (rows as List)
        .map((row) => ChildForInvitation.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<GuardianRow>> fetchGuardiansForOffice(String officeId) async {
    final rows = await _client.rpc('fetch_guardians_for_office', params: {'p_office_id': officeId});
    return (rows as List).map((row) => GuardianRow.fromJson(row as Map<String, dynamic>)).toList();
  }

  Future<List<GuardianInvitationRow>> fetchPendingGuardianInvitations(String officeId) async {
    final rows = await _client.rpc('fetch_pending_guardian_invitations', params: {'p_office_id': officeId});
    return (rows as List)
        .map((row) => GuardianInvitationRow.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> suspendGuardianAccount(String guardianId, String reason) async {
    await _client.rpc('suspend_guardian_account', params: {
      'p_guardian_id': guardianId,
      'p_reason': reason,
    });
  }

  Future<void> reactivateGuardianAccount(String guardianId) async {
    await _client.rpc('reactivate_guardian_account', params: {'p_guardian_id': guardianId});
  }

  // ------------------------------------------------------------------
  // 園内記録(職員専用・保護者には一切表示しない)
  // ------------------------------------------------------------------

  Future<bool> isChildInternalNotesEnabledForOffice(String officeId) async {
    final result = await _client.rpc(
      'is_child_internal_notes_enabled_for_office',
      params: {'p_office_id': officeId},
    );
    return result as bool? ?? false;
  }

  /// 夏期のプール◯×連絡が施設で有効か(261)。有効時のみ一覧にプール列を出す。
  Future<bool> isPoolReportEnabledForOffice(String officeId) async {
    try {
      final result = await _client.rpc(
        'is_pool_report_enabled_for_office',
        params: {'p_office_id': officeId},
      );
      return result == true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------------
  // 発達記録(239/240/241)。閲覧=全職員、達成申請=担任・担当クラス。
  // ------------------------------------------------------------------

  Future<bool> isDevelopmentRecordsEnabledForOffice(String officeId) async {
    try {
      final result = await _client.rpc(
        'is_development_records_enabled_for_office',
        params: {'p_office_id': officeId},
      );
      return result == true;
    } catch (_) {
      return false;
    }
  }

  Future<DevelopmentHeader?> fetchChildDevelopmentHeader(String childId) async {
    final rows = await _client
        .rpc('fetch_child_development_header', params: {'p_child_id': childId}) as List;
    if (rows.isEmpty) return null;
    return DevelopmentHeader.fromJson(rows.first as Map<String, dynamic>);
  }

  Future<List<DevelopmentRecord>> fetchChildDevelopmentRecords(
    String childId, {
    String? ageBandCode,
  }) async {
    final rows = await _client.rpc('fetch_child_development_records', params: {
      'p_child_id': childId,
      'p_age_band_code': ageBandCode,
    }) as List;
    return rows
        .map((r) => DevelopmentRecord.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> submitDevelopmentAchievementRequest({
    required String childId,
    required String itemId,
    String? note,
  }) async {
    await _client.rpc('submit_development_achievement_request', params: {
      'p_child_id': childId,
      'p_item_id': itemId,
      'p_source': 'manual',
      'p_ai_candidate_id': null,
      'p_note': note,
    });
  }

  Future<void> withdrawDevelopmentAchievementRequest(String requestId) async {
    await _client.rpc('withdraw_development_achievement_request', params: {
      'p_request_id': requestId,
      'p_note': null,
    });
  }

  // ------------------------------------------------------------------
  // 登園メモ(244・職員内部・当日状況把握用。保護者非公開・連絡帳/AI非反映)。
  // ------------------------------------------------------------------

  Future<Map<String, String>> fetchArrivalNotesForOffice(
    String officeId,
    DateTime businessDate,
  ) async {
    final rows = await _client.rpc('fetch_arrival_notes_for_office', params: {
      'p_office_id': officeId,
      'p_business_date': dateOnly(businessDate),
    }) as List;
    final map = <String, String>{};
    for (final r in rows) {
      final m = r as Map<String, dynamic>;
      map[m['child_id'] as String] = m['body'] as String;
    }
    return map;
  }

  Future<void> upsertChildArrivalNote(
    String childId,
    DateTime businessDate,
    String body,
  ) async {
    await _client.rpc('upsert_child_arrival_note', params: {
      'p_child_id': childId,
      'p_business_date': dateOnly(businessDate),
      'p_body': body,
    });
  }

  // ------------------------------------------------------------------
  // 食数・厨房ボード(245・M6 Phase 7)。給食情報のみ。閲覧=所属施設の職員以上。
  // ------------------------------------------------------------------

  /// 当日の食数集計(5区分+提供数+職員食数)。
  Future<({int normal, int elimination, int bento, int hold, int pre, int provided, int staff})>
      fetchMealCountForOffice(String officeId, DateTime businessDate) async {
    final rows = await _client.rpc('fetch_meal_count_for_office', params: {
      'p_office_id': officeId,
      'p_business_date': dateOnly(businessDate),
    }) as List;
    final m = rows.first as Map<String, dynamic>;
    int v(String k) => (m[k] as num?)?.toInt() ?? 0;
    return (
      normal: v('normal_count'),
      elimination: v('elimination_count'),
      bento: v('bento_count'),
      hold: v('hold_count'),
      pre: v('pre_count'),
      provided: v('provided_count'),
      staff: v('staff_count'),
    );
  }

  /// 食数ボード(行区分×食事区分・258/257)。厨房ページ・食数ボード表示用。
  Future<List<Map<String, dynamic>>> fetchMealBoard(String officeId, DateTime businessDate) async {
    final rows = await _client.rpc('fetch_meal_board', params: {
      'p_office_id': officeId,
      'p_business_date': dateOnly(businessDate),
    });
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Mahalo Station固有欄(340): is_station・牛乳本数・明日のおやつ(翌日登園予定数)。
  Future<({bool isStation, int? milkBottles, int nextDaySnack})> fetchMealStationExtras(
      String officeId, DateTime businessDate) async {
    final rows = await _client.rpc('fetch_meal_station_extras',
        params: {'p_office': officeId, 'p_date': dateOnly(businessDate)});
    final r = (rows as List).cast<Map<String, dynamic>>().firstOrNull;
    return (
      isStation: (r?['is_station'] as bool?) ?? false,
      milkBottles: r?['milk_bottles'] as int?,
      nextDaySnack: (r?['next_day_snack'] as int?) ?? 0,
    );
  }

  /// 今日の牛乳本数を保存(Station固有・340)。
  Future<void> setMilkBottles(String officeId, DateTime businessDate, int? count) async {
    await _client.rpc('set_milk_bottles',
        params: {'p_office': officeId, 'p_date': dateOnly(businessDate), 'p_count': count});
  }

  // ===== 指導計画・保育安全計画(287-297)=====
  Future<bool> isGuidancePlansEnabledForOffice(String officeId) async {
    try {
      final d = await _client.rpc('is_guidance_plans_enabled_for_office', params: {'p_office_id': officeId});
      return d == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchGuidancePlansForOffice(String officeId, int fiscalYear, {String? planType}) async {
    final rows = await _client.rpc('fetch_guidance_plans_for_office',
        params: {'p_office_id': officeId, 'p_fiscal_year': fiscalYear, 'p_plan_type': planType});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<String> ensureGuidancePlan(String officeId, String? classId, String planType, int fiscalYear,
      {int? month, DateTime? weekStart}) async {
    final id = await _client.rpc('ensure_guidance_plan', params: {
      'p_office_id': officeId,
      'p_class_id': classId,
      'p_plan_type': planType,
      'p_fiscal_year': fiscalYear,
      'p_month': month,
      'p_week_start': weekStart != null ? dateOnly(weekStart) : null,
    });
    return id as String;
  }

  Future<Map<String, dynamic>> fetchGuidancePlan(String id) async {
    final d = await _client.rpc('fetch_guidance_plan', params: {'p_id': id});
    return (d as Map).cast<String, dynamic>();
  }

  Future<void> saveGuidancePlanContent(String id, Map<String, dynamic> content) async {
    await _client.rpc('save_guidance_plan_content', params: {'p_id': id, 'p_content': content});
  }

  Future<void> saveGuidancePlanEvaluation(String id, Map<String, dynamic> evaluation) async {
    await _client.rpc('save_guidance_plan_evaluation', params: {'p_id': id, 'p_evaluation': evaluation});
  }

  Future<void> upsertGuidancePlanIndividual(String planId, String childId, Map<String, dynamic> content) async {
    await _client.rpc('upsert_guidance_plan_individual',
        params: {'p_plan_id': planId, 'p_child_id': childId, 'p_content': content});
  }

  Future<List<Map<String, dynamic>>> fetchGuidanceIndividualTargets(String planId) async {
    final rows = await _client.rpc('fetch_guidance_individual_targets', params: {'p_plan_id': planId});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> submitGuidancePlan(String id) async => _client.rpc('submit_guidance_plan', params: {'p_id': id});
  Future<void> chiefCheckGuidancePlan(String id) async => _client.rpc('chief_check_guidance_plan', params: {'p_id': id});
  Future<void> approveGuidancePlan(String id) async => _client.rpc('approve_guidance_plan', params: {'p_id': id});
  Future<void> rejectGuidancePlan(String id, String reason) async =>
      _client.rpc('reject_guidance_plan', params: {'p_id': id, 'p_reason': reason});
  Future<void> copyPreviousGuidancePlan(String id) async => _client.rpc('copy_previous_guidance_plan', params: {'p_id': id});

  /// 承認可(統括園長・園長)の判定。一括承認ボタンの表示制御に使う(332/333)。
  Future<bool> canApproveGuidancePlan(String officeId) async {
    final r = await _client.rpc('can_approve_guidance_plan', params: {'target_office_id': officeId});
    return r == true;
  }

  /// 一括承認(333)。その年度の承認待ちをまとめて承認し、承認件数を返す。
  Future<int> bulkApproveGuidancePlans(String officeId, int fiscalYear) async {
    final r = await _client.rpc('bulk_approve_guidance_plans',
        params: {'p_office_id': officeId, 'p_fiscal_year': fiscalYear});
    return (r as int?) ?? 0;
  }

  /// 指導計画の未完了タスク(306・主任以上)。未提出=action/承認待ち=info。
  Future<List<Map<String, dynamic>>> fetchGuidancePlanTasks(String officeId) async {
    final rows = await _client.rpc('fetch_guidance_plan_tasks_for_office', params: {'p_office_id': officeId});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  // ===== 給食写真(300) =====
  /// 撮影画像を meal-photos バケットへアップロードし、承認待ちで登録(submit_meal_photo)。
  Future<void> submitMealPhoto(String officeId, DateTime businessDate, Uint8List bytes, {String? caption}) async {
    final d = businessDate.toIso8601String().substring(0, 10);
    final path = '$officeId/$d/${DateTime.now().microsecondsSinceEpoch}.jpg';
    await _client.storage.from('meal-photos').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false),
        );
    await _client.rpc('submit_meal_photo', params: {
      'p_office_id': officeId,
      'p_business_date': d,
      'p_storage_path': path,
      'p_caption': caption,
    });
  }

  /// 職員向け一覧(自施設・指定日・全ステータス)。
  Future<List<Map<String, dynamic>>> fetchMealPhotosForOffice(String officeId, DateTime businessDate) async {
    final rows = await _client.rpc('fetch_meal_photos_for_office',
        params: {'p_office_id': officeId, 'p_business_date': businessDate.toIso8601String().substring(0, 10)});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> approveMealPhoto(String id) async => _client.rpc('approve_meal_photo', params: {'p_id': id});
  Future<void> rejectMealPhoto(String id, String reason) async =>
      _client.rpc('reject_meal_photo', params: {'p_id': id, 'p_reason': reason});
  Future<void> deleteMealPhoto(String id) async => _client.rpc('delete_meal_photo', params: {'p_id': id});

  /// meal-photos の署名URL(表示用・5分)。
  Future<String> mealPhotoSignedUrl(String storagePath) async =>
      _client.storage.from('meal-photos').createSignedUrl(storagePath, 60 * 5);

  // ===== 厨房専用アプリ(304) =====
  /// ログイン中の職員が厨房専用アカウントか。
  Future<bool> isKitchenOnlyEmployee() async {
    final d = await _client.rpc('is_kitchen_only_employee');
    return d == true;
  }

  /// 厨房アカウントが管理する施設(施設割当×給食管理ON)。
  Future<List<Map<String, dynamic>>> fetchMyKitchenOffices() async {
    final rows = await _client.rpc('fetch_my_kitchen_offices');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// その日の残量(グラム)を記録。
  Future<void> setMealLeftover(String officeId, DateTime businessDate, int? grams) async {
    await _client.rpc('set_meal_leftover', params: {
      'p_office_id': officeId,
      'p_business_date': businessDate.toIso8601String().substring(0, 10),
      'p_grams': grams,
    });
  }

  /// 月別集計(施設×暦月・日別×食事区分の園児/職員+残量)。
  Future<List<Map<String, dynamic>>> fetchMealMonthlySummary(String officeId, int year, int month) async {
    final rows = await _client.rpc('fetch_meal_monthly_summary',
        params: {'p_office_id': officeId, 'p_year': year, 'p_month': month});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 食事区分ごとの各施設必要数(指定日・複数施設)。
  Future<List<Map<String, dynamic>>> fetchMealSlotCrossoffice(List<String> officeIds, DateTime businessDate) async {
    final rows = await _client.rpc('fetch_meal_slot_crossoffice',
        params: {'p_office_ids': officeIds, 'p_business_date': businessDate.toIso8601String().substring(0, 10)});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 厨房ビュー用・複数施設の行区分(クラス/給食段階)×食事区分(345)。
  Future<List<Map<String, dynamic>>> fetchMealBoardCrossoffice(List<String> officeIds, DateTime businessDate) async {
    final rows = await _client.rpc('fetch_meal_board_crossoffice',
        params: {'p_office_ids': officeIds, 'p_business_date': businessDate.toIso8601String().substring(0, 10)});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 厨房ビュー用・複数施設のアレルギー対応者リスト(344)。除去食(作る)+弁当持参(作らない)。
  Future<List<Map<String, dynamic>>> fetchMealAllergyCrossoffice(List<String> officeIds, DateTime businessDate) async {
    final rows = await _client.rpc('fetch_meal_allergy_crossoffice',
        params: {'p_office_ids': officeIds, 'p_business_date': businessDate.toIso8601String().substring(0, 10)});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 厨房向け 給食会議の閲覧(305・対象児/除去提供方針/同意状況)。
  Future<List<Map<String, dynamic>>> fetchMealConferencesForKitchen(String officeId) async {
    final rows = await _client.rpc('fetch_meal_conferences_for_kitchen', params: {'p_office_id': officeId});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// AI下書き生成(299/Edge Function generate-guidance-draft)。連絡帳・クラス活動・家庭連絡・前回計画を
  /// 素材に各欄の下書き文を生成して返す。戻り値 {mock:bool, sections:{欄key:文}, source_counts:{...}}。
  /// ANTHROPIC_API_KEY未設定時は mock:true(サンプル下書き)。
  Future<Map<String, dynamic>> generateGuidanceDraft(String planId) async {
    final res = await _client.functions.invoke('generate-guidance-draft', body: {'plan_id': planId});
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw Exception(data['error'].toString());
    }
    return (data as Map).cast<String, dynamic>();
  }

  /// 園で提供しない食材のアレルギー(272・台帳表示のみ・食数非連動)。allergen/severity/note。
  Future<List<Map<String, dynamic>>> fetchChildAllergenAlerts(String childId) async {
    final rows = await _client.rpc('fetch_child_allergen_alerts', params: {'p_child_id': childId});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 非提供食材アレルギーの登録(272・主任以上)。severity: mild/severe/anaphylaxis|null。
  Future<void> setChildAllergenAlert(String childId, String allergen, String? severity, String? note) async {
    await _client.rpc('set_child_allergen_alert', params: {
      'p_child_id': childId,
      'p_allergen': allergen,
      'p_severity': severity,
      'p_note': note,
    });
  }

  /// 非提供食材アレルギーの削除(272・主任以上)。
  Future<void> deleteChildAllergenAlert(String id) async {
    await _client.rpc('delete_child_allergen_alert', params: {'p_id': id});
  }

  /// 給食停止中(弁当持参・アレルギー確認中)の園児一覧(271)。食数ボード/厨房で提供対象外を把握。
  Future<List<Map<String, dynamic>>> fetchMealSuspendedChildren(String officeId) async {
    final rows = await _client.rpc('fetch_meal_suspended_children_for_office', params: {
      'p_office_id': officeId,
    });
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 本日の公開済み献立(267)。厨房ページで当日献立を表示。食種×区分。
  Future<List<Map<String, dynamic>>> fetchPublishedMenuDay(String officeId, DateTime menuDate) async {
    final rows = await _client.rpc('fetch_published_menu_day', params: {
      'p_office_id': officeId,
      'p_menu_date': dateOnly(menuDate),
    });
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 献立の取込一覧(施設×対象月)。月間一覧の版選択に使う(264)。
  Future<List<Map<String, dynamic>>> fetchMenuImports(String officeId, DateTime targetMonth) async {
    final rows = await _client.rpc('fetch_menu_imports', params: {
      'p_office_id': officeId,
      'p_target_month': dateOnly(DateTime(targetMonth.year, targetMonth.month, 1)),
    });
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 取込1件の全日献立(月間一覧の中身・267)。
  Future<List<Map<String, dynamic>>> fetchMenuDaysForImport(String importId) async {
    final rows = await _client.rpc('fetch_menu_days_for_import', params: {'p_import_id': importId});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 食数の手動再算出(職員以上・ON施設)。
  Future<void> computeMealCounts(String officeId, DateTime businessDate) async {
    await _client.rpc('compute_meal_counts', params: {
      'p_office_id': officeId,
      'p_business_date': dateOnly(businessDate),
    });
  }

  /// クラス承認(担任=自クラス/職員行=主任以上)。行を確定。
  Future<void> confirmMealRow(String officeId, DateTime businessDate, String rowKey) async {
    await _client.rpc('confirm_meal_row', params: {
      'p_office_id': officeId,
      'p_business_date': dateOnly(businessDate),
      'p_row_key': rowKey,
    });
  }

  /// その日の給食発注数を一括承認/解除(362・クラスごとの承認は不要)。
  Future<void> confirmMealDay(String officeId, DateTime businessDate) async {
    await _client.rpc('confirm_meal_day', params: {'p_office_id': officeId, 'p_business_date': dateOnly(businessDate)});
  }

  Future<void> unconfirmMealDay(String officeId, DateTime businessDate) async {
    await _client.rpc('unconfirm_meal_day', params: {'p_office_id': officeId, 'p_business_date': dateOnly(businessDate)});
  }

  // ===== 職員給食 自己注文モデル(369-371) =====
  /// その日◯の職員一覧(朝の発注画面)。
  Future<List<Map<String, dynamic>>> fetchStaffMealDayOrderers(String officeId, DateTime date) async {
    final rows = await _client.rpc('fetch_staff_meal_day_orderers', params: {'p_office': officeId, 'p_date': dateOnly(date)});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 職員×日の◯を追加/削除(締切前=日別上書き / 締切後・過去=手動)。
  Future<void> setStaffMealDay(String officeId, DateTime date, String employeeId, bool willEat) async {
    await _client.rpc('set_staff_meal_day',
        params: {'p_office': officeId, 'p_date': dateOnly(date), 'p_employee': employeeId, 'p_will_eat': willEat});
  }

  /// 給食「提供なし」の区分別切替(am_snack/lunch/pm_snack)。
  Future<void> setMealNoService(String officeId, DateTime date, String slot, bool value) async {
    await _client.rpc('set_meal_no_service', params: {'p_office': officeId, 'p_date': dateOnly(date), 'p_slot': slot, 'p_value': value});
  }

  /// 当日の提供なし状態(区分別)。meal_count_days をRLS範囲で直読。
  Future<({bool am, bool lunch, bool pm})> fetchMealNoService(String officeId, DateTime date) async {
    final row = await _client
        .from('meal_count_days')
        .select('no_service_am_snack,no_service_lunch,no_service_pm_snack')
        .eq('office_id', officeId)
        .eq('business_date', dateOnly(date))
        .maybeSingle();
    return (
      am: (row?['no_service_am_snack'] as bool?) ?? false,
      lunch: (row?['no_service_lunch'] as bool?) ?? false,
      pm: (row?['no_service_pm_snack'] as bool?) ?? false,
    );
  }

  /// 施設の職員一覧(発注者に追加する候補)。
  Future<List<Map<String, dynamic>>> fetchOfficeEmployees(String officeId) async {
    final rows = await _client.rpc('fetch_office_employees', params: {'p_office_id': officeId});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 一括承認されていない確定日(承認忘れアラート)。
  Future<List<Map<String, dynamic>>> fetchUnconfirmedFinalizedDays({int days = 7}) async {
    final rows = await _client.rpc('fetch_unconfirmed_finalized_days', params: {'p_days': days});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 期限内変更(当日・昼食10:00/午後14:00/朝9:30)。変更前後を履歴化。
  Future<void> changeMealRow(
    String officeId,
    DateTime businessDate,
    String rowKey,
    String mealSlot,
    String field,
    int newCount,
  ) async {
    await _client.rpc('change_meal_row', params: {
      'p_office_id': officeId,
      'p_business_date': dateOnly(businessDate),
      'p_row_key': rowKey,
      'p_meal_slot': mealSlot,
      'p_field': field,
      'p_new_count': newCount,
    });
  }

  /// 当日の食数変更履歴(厨房の大型アラート・§5.2)。
  Future<List<Map<String, dynamic>>> fetchMealChanges(String officeId, DateTime businessDate) async {
    final rows = await _client.rpc('fetch_meal_changes', params: {
      'p_office_id': officeId,
      'p_business_date': dateOnly(businessDate),
    });
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 厨房の変更確認(未確認の変更を確認済みに・259)。
  Future<void> acknowledgeMealChanges(String officeId, DateTime businessDate) async {
    await _client.rpc('acknowledge_meal_changes', params: {
      'p_office_id': officeId,
      'p_business_date': dateOnly(businessDate),
    });
  }

  /// 当日の共通除去食/弁当持参/給食開始保留の対象児(厨房の誤配膳防止表示用)。
  /// consentStatus(275): 'ok'=保護者同意あり / 'waived'=経過措置 / 'pending'=同意待ち(弁当持参) / null=対象外。
  Future<List<({String childId, String childName, String? className, String? handling, List<String> targets,
      String? consentStatus})>>
      fetchDailyEliminationForOffice(String officeId, DateTime businessDate) async {
    final rows = await _client.rpc('fetch_daily_elimination_for_office', params: {
      'p_office_id': officeId,
      'p_business_date': dateOnly(businessDate),
    }) as List;
    return [
      for (final r in rows)
        (
          childId: (r as Map<String, dynamic>)['child_id'] as String,
          childName: r['child_name'] as String,
          className: r['class_name'] as String?,
          handling: r['handling'] as String?,
          targets: ((r['elimination_targets'] as List?) ?? const []).map((e) => e as String).toList(),
          consentStatus: r['consent_status'] as String?,
        ),
    ];
  }

  /// 表示制御のみに使う(編集・削除ボタンの出し分け)。実際の許可判定は必ずRPC側で行う。
  Future<bool> isChildInternalNotesChief(String officeId) async {
    final result = await _client.rpc(
      'is_child_internal_notes_chief',
      params: {'target_office_id': officeId},
    );
    return result as bool? ?? false;
  }

  /// 絞り込み・並び順はすべてRPC側の責務。フロントで再実装しない。
  Future<List<ChildInternalNote>> fetchChildInternalNotes({
    required String childId,
    List<String>? categories,
    int limit = 20,
    int offset = 0,
  }) async {
    final rows = await _client.rpc('fetch_child_internal_notes', params: {
      'p_child_id': childId,
      'p_categories': categories,
      'p_limit': limit,
      'p_offset': offset,
    });
    return (rows as List)
        .map((row) => ChildInternalNote.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> createChildInternalNote({
    required String childId,
    required DateTime noteDate,
    required String category,
    required String body,
    required bool aiExcluded,
  }) async {
    await _client.rpc('create_child_internal_note', params: {
      'p_child_id': childId,
      'p_note_date': dateOnly(noteDate),
      'p_category': category,
      'p_body': body,
      'p_ai_excluded': aiExcluded,
    });
  }

  Future<void> updateChildInternalNote({
    required String noteId,
    required String body,
    required String category,
    required bool aiExcluded,
    required String noteDate,
  }) async {
    await _client.rpc('update_child_internal_note', params: {
      'p_note_id': noteId,
      'p_body': body,
      'p_category': category,
      'p_ai_excluded': aiExcluded,
      'p_note_date': noteDate,
    });
  }

  Future<void> softDeleteChildInternalNote(String noteId) async {
    await _client.rpc('soft_delete_child_internal_note', params: {'p_note_id': noteId});
  }

  /// 園児台帳の一覧用(217 fetch_children_for_office_master・職員全員可)。
  /// 在籍状況(入園予定/在籍中/退園済み)・ふりがな・クラスを含む全園児。
  Future<List<Map<String, dynamic>>> fetchChildrenForOfficeMaster(String officeId) async {
    final rows = await _client.rpc('fetch_children_for_office_master', params: {'p_office_id': officeId});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 食材チェックの施設フラグ(224)。
  Future<bool> isFoodCheckEnabledForOffice(String officeId) async {
    final result = await _client.rpc('is_food_check_enabled_for_office', params: {'p_office_id': officeId});
    return result == true;
  }

  /// 食材チェック進捗(224)。段階ごとの必須完了数(台帳表示用・全職員閲覧可)。
  Future<List<Map<String, dynamic>>> fetchChildFoodProgress(String childId) async {
    final rows = await _client.rpc('fetch_child_food_progress', params: {'p_child_id': childId});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 給食状態(227/228)。5区分+候補+現在段階(台帳表示用・全職員閲覧可)。
  Future<Map<String, dynamic>?> fetchChildMealStatus(String childId) async {
    final rows = await _client.rpc('fetch_child_meal_status', params: {'p_child_id': childId});
    final list = (rows as List).cast<Map<String, dynamic>>();
    return list.isEmpty ? null : list.first;
  }

  /// クラス在籍履歴(223)。進級・転クラスの履歴表示用(全職員閲覧可)。
  Future<List<Map<String, dynamic>>> fetchChildClassHistory(String childId) async {
    final rows = await _client.rpc('fetch_child_class_history', params: {'p_child_id': childId});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 園児台帳(221)。children正本+世帯住所+承認済み入園フォームのスナップショット。
  /// 施設の全職員が閲覧可(閲覧専用)。
  Future<Map<String, dynamic>?> fetchChildRegister(String childId) async {
    final rows = await _client.rpc('fetch_child_register', params: {'p_child_id': childId});
    final list = (rows as List).cast<Map<String, dynamic>>();
    return list.isEmpty ? null : list.first;
  }

  /// 招待コードは発行時のみ取得できる(サーバーはtoken_hashのみ保持する)。
  Future<({String token, DateTime expiresAt})> createGuardianInvitationByStaff({
    required String childId,
    required String role,
    int ttlHours = 72,
  }) async {
    final rows = await _client.rpc('create_guardian_invitation_by_staff', params: {
      'p_child_id': childId,
      'p_role': role,
      'p_ttl_hours': ttlHours,
    });
    final row = (rows as List).first as Map<String, dynamic>;
    return (token: row['token'] as String, expiresAt: DateTime.parse(row['expires_at'] as String));
  }

  // ------------------------------------------------------------------
  // ヒヤリハット・事故報告(246-250・Phase A)。閲覧=全施設の保育職員。保護者非表示。
  // ------------------------------------------------------------------

  /// 施設で機能が有効か(タイル/入口の出し分け。許可判定は必ずRPC側)。
  Future<bool> isIncidentReportsEnabledForOffice(String officeId) async {
    final result = await _client.rpc('is_incident_reports_enabled_for_office', params: {'p_office_id': officeId});
    return result == true;
  }

  /// 一覧(全施設閲覧)。status/reportType は null で全件。
  Future<List<Map<String, dynamic>>> fetchIncidentReports(
    String officeId, {
    String? status,
    String? reportType,
  }) async {
    final rows = await _client.rpc('fetch_incident_reports', params: {
      'p_office_id': officeId,
      'p_status': status,
      'p_report_type': reportType,
    });
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 詳細(本体+全子コレクションのjsonb)。
  Future<Map<String, dynamic>> fetchIncidentReportDetail(String id) async {
    final result = await _client.rpc('fetch_incident_report_detail', params: {'p_id': id});
    return (result as Map).cast<String, dynamic>();
  }

  /// ルックアップ選択肢(kind=null で全種別・有効のみ)。
  Future<List<Map<String, dynamic>>> fetchIncidentLookupOptions({String? kind}) async {
    final rows = await _client.rpc('fetch_incident_lookup_options', params: {'p_kind': kind});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 下書きの作成/保存(全子コレクション置換)。新規は id=null。返り値=report id。
  Future<String> saveIncidentReport(Map<String, dynamic> payload, {String? id}) async {
    final result = await _client.rpc('save_incident_report', params: {'p_id': id, 'p_payload': payload});
    return result as String;
  }

  Future<void> submitIncidentReport(String id) async {
    await _client.rpc('submit_incident_report', params: {'p_id': id});
  }

  /// 下書き(draft)のヒヤリハット・事故報告を削除(283・作成者本人 or 主任以上)。
  Future<void> deleteIncidentReport(String id) async {
    await _client.rpc('delete_incident_report', params: {'p_id': id});
  }

  Future<void> chiefApproveIncidentReport(String id) async {
    await _client.rpc('chief_approve_incident_report', params: {'p_id': id});
  }

  Future<void> approveIncidentReport(String id) async {
    await _client.rpc('approve_incident_report', params: {'p_id': id});
  }

  Future<void> rejectIncidentReport(String id, String reason) async {
    await _client.rpc('reject_incident_report', params: {'p_id': id, 'p_reason': reason});
  }

  Future<void> cancelIncidentApproval(String id, String reason) async {
    await _client.rpc('cancel_incident_approval', params: {'p_id': id, 'p_reason': reason});
  }

  /// 承認後の追記(経過)。返り値=log id。
  Future<String> addIncidentProgressLog({
    required String reportId,
    required DateTime loggedAt,
    String? staffEmployeeId,
    required String reportKind,
    String? reportText,
  }) async {
    final result = await _client.rpc('add_incident_progress_log', params: {
      'p_report_id': reportId,
      'p_logged_at': loggedAt.toIso8601String(),
      'p_staff_employee_id': staffEmployeeId,
      'p_report_kind': reportKind,
      'p_report_text': reportText,
    });
    return result as String;
  }

  /// クローズ状態+充足判定(詳細のボタン制御用)。
  Future<Map<String, dynamic>?> fetchIncidentClosure(String reportId) async {
    final rows = await _client.rpc('fetch_incident_closure', params: {'p_id': reportId});
    final list = (rows as List).cast<Map<String, dynamic>>();
    return list.isEmpty ? null : list.first;
  }

  Future<void> closeIncidentReport(String reportId, String? note) async {
    await _client.rpc('close_incident_report', params: {'p_id': reportId, 'p_note': note});
  }

  Future<void> reopenIncidentClosure(String reportId, String reason) async {
    await _client.rpc('reopen_incident_closure', params: {'p_id': reportId, 'p_reason': reason});
  }

  /// 未クローズの事故報告書一覧(経過日数順・不足条件付き)。
  Future<List<Map<String, dynamic>>> fetchOpenIncidentReports(String officeId) async {
    final rows = await _client.rpc('fetch_open_incident_reports', params: {'p_office_id': officeId});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 未クローズ件数(バッジ用)。
  Future<int> countOpenIncidentReports(String officeId) async {
    final result = await _client.rpc('count_open_incident_reports', params: {'p_office_id': officeId});
    return (result as num?)?.toInt() ?? 0;
  }

  /// 承認後の追記(保護者連絡)。返り値=contact id。
  Future<String> addIncidentGuardianContact({
    required String reportId,
    required DateTime contactedAt,
    String? staffEmployeeId,
    bool? contactBookWritten,
    required String reactionKind,
    String? reactionText,
  }) async {
    final result = await _client.rpc('add_incident_guardian_contact', params: {
      'p_report_id': reportId,
      'p_contacted_at': contactedAt.toIso8601String(),
      'p_staff_employee_id': staffEmployeeId,
      'p_contact_book_written': contactBookWritten,
      'p_reaction_kind': reactionKind,
      'p_reaction_text': reactionText,
    });
    return result as String;
  }
}
