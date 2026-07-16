import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/childcare.dart';

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

  Future<bool> hasChildcareAccess() async {
    final offices = await fetchMyChildcareOffices();
    return offices.isNotEmpty;
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
        .select('*, childcare_classes(class_name), employees(name)')
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

  Future<DailyContact> fetchDailyContactDetail(String contactId) async {
    final row = await _client
        .from('child_daily_contacts')
        .select('*, children(display_name, honorific_suffix), employees(name)')
        .eq('id', contactId)
        .single();
    final child = row['children'] as Map<String, dynamic>?;
    final assignee = row['employees'] as Map<String, dynamic>?;
    return DailyContact.fromJson({
      'contact_id': row['id'],
      'child_id': row['child_id'],
      'child_display_name': child?['display_name'] ?? '',
      'child_honorific_suffix': child?['honorific_suffix'],
      'class_name': null,
      'assignee_employee_id': row['assignee_employee_id'],
      'assignee_name': assignee?['name'],
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
    });
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
}
