import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/notice.dart';

/// 8章 職員連絡(お知らせ)機能。閲覧・既読管理・管理者向け未読確認を扱う。
///
/// notice_recipients への読み書きは全てRLS(20260710160006_rls.sql /
/// 20260714000002_notices_recipient_policies.sql)で保護されており、
/// 本サービスはservice roleを使わずクライアントの権限のまま直接テーブル操作する。
class NoticeService {
  NoticeService(this._client);

  final SupabaseClient _client;

  Future<String?> _fetchMyEmployeeId() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _client
        .from('employees')
        .select('id')
        .eq('auth_user_id', userId)
        .maybeSingle();
    return row?['id'] as String?;
  }

  Future<List<Notice>> fetchNotices() async {
    final rows = await _client
        .from('notices')
        .select('*, notice_recipients(read_at, reply_option)')
        .order('created_at', ascending: false);
    return (rows as List)
        .map((row) => Notice.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<Notice?> fetchNotice(String noticeId) async {
    final row = await _client
        .from('notices')
        .select('*, notice_recipients(read_at, reply_option)')
        .eq('id', noticeId)
        .maybeSingle();
    return row != null ? Notice.fromJson(row) : null;
  }

  Future<List<NoticeAttachment>> fetchAttachments(String noticeId) async {
    final rows = await _client
        .from('notice_attachments')
        .select()
        .eq('notice_id', noticeId);
    return (rows as List)
        .map((row) => NoticeAttachment.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<String> createAttachmentSignedUrl(String filePath) async {
    return _client.storage
        .from('notice-attachments')
        .createSignedUrl(filePath, 60 * 5);
  }

  /// 既読を記録する。まだ notice_recipients 行がない場合(会社一斉/園単位/役職別等)は
  /// 開封時に自己申告で作成する。
  Future<void> markAsRead(String noticeId) async {
    final employeeId = await _fetchMyEmployeeId();
    if (employeeId == null) return;
    await _client.from('notice_recipients').upsert(
      {
        'notice_id': noticeId,
        'employee_id': employeeId,
        'read_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'notice_id,employee_id',
    );
  }

  Future<void> submitReply(String noticeId, String replyOption) async {
    final employeeId = await _fetchMyEmployeeId();
    if (employeeId == null) return;
    final now = DateTime.now().toIso8601String();
    await _client.from('notice_recipients').upsert(
      {
        'notice_id': noticeId,
        'employee_id': employeeId,
        'read_at': now,
        'reply_option': replyOption,
        'replied_at': now,
      },
      onConflict: 'notice_id,employee_id',
    );
  }

  /// 管理者モード: 対象者ごとの既読状況を算出する。
  /// 会社一斉/園単位/役職別は対象範囲を職員マスタから算出し、
  /// 個別/勤務交代関連/災害モードは notice_recipients に登録済みの対象者をそのまま使う。
  Future<List<NoticeAudienceEntry>> fetchAudienceStatus(Notice notice) async {
    if (['個別', '勤務交代関連', '災害モード'].contains(notice.category)) {
      final rows = await _client
          .from('notice_recipients')
          .select('read_at, employees(name, offices(name))')
          .eq('notice_id', notice.id);
      return (rows as List).map((row) {
        final map = row as Map<String, dynamic>;
        final employee = map['employees'] as Map<String, dynamic>?;
        final office = employee?['offices'] as Map<String, dynamic>?;
        return NoticeAudienceEntry(
          employeeName: employee?['name'] as String? ?? '(不明な職員)',
          officeName: office?['name'] as String?,
          readAt: map['read_at'] != null
              ? DateTime.parse(map['read_at'] as String)
              : null,
        );
      }).toList()
        ..sort(_unreadFirst);
    }

    var query = _client.from('employees').select('id, name, offices(name)').filter(
          'resignation_date',
          'is',
          null,
        );
    if (notice.category == '園単位' && notice.targetOfficeId != null) {
      query = query.eq('home_office_id', notice.targetOfficeId!);
    } else if (notice.category == '役職別' && notice.targetPositionId != null) {
      query = query.eq('position_id', notice.targetPositionId!);
    }
    final employeeRows = await query;

    final recipientRows = await _client
        .from('notice_recipients')
        .select('employee_id, read_at')
        .eq('notice_id', notice.id);
    final readAtByEmployeeId = <String, String?>{
      for (final row in recipientRows as List)
        (row as Map<String, dynamic>)['employee_id'] as String:
            row['read_at'] as String?,
    };

    return (employeeRows as List).map((row) {
      final map = row as Map<String, dynamic>;
      final office = map['offices'] as Map<String, dynamic>?;
      final readAtRaw = readAtByEmployeeId[map['id'] as String];
      return NoticeAudienceEntry(
        employeeName: map['name'] as String,
        officeName: office?['name'] as String?,
        readAt: readAtRaw != null ? DateTime.parse(readAtRaw) : null,
      );
    }).toList()
      ..sort(_unreadFirst);
  }

  int _unreadFirst(NoticeAudienceEntry a, NoticeAudienceEntry b) {
    if (a.isRead == b.isRead) return 0;
    return a.isRead ? 1 : -1;
  }

  /// 管理者モード(未読者一覧)を表示してよいか(施設管理権限を持つロールか)。
  Future<bool> canViewAudienceStatus() async {
    final employeeId = await _fetchMyEmployeeId();
    if (employeeId == null) return false;
    final rows = await _client
        .from('employee_roles')
        .select('roles(code)')
        .eq('employee_id', employeeId);
    const managerRoleCodes = {
      'director',
      'chief',
      'office_manager',
      'labor_manager',
      'system_admin',
    };
    return (rows as List).any((row) {
      final role = (row as Map<String, dynamic>)['roles'] as Map<String, dynamic>?;
      return managerRoleCodes.contains(role?['code']);
    });
  }
}
