import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/leave_request.dart';

/// 15章/28.4 各種申請(有給休暇/欠勤連絡/遅刻早退/情報変更)。職員側の申請・管理者側の承認を扱う。
///
/// requests関連テーブルへの読み書きは全てRLS
/// (20260710160006_rls.sql / 20260714000004 / 20260714000005)で保護されており、
/// 本サービスはservice roleを使わずクライアントの権限のまま直接テーブル操作する。
class RequestService {
  RequestService(this._client);

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

  Future<double> fetchHoursPerDay() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final row = await _client
        .from('leave_day_hour_settings')
        .select('hours_per_day')
        .lte('effective_start_date', today)
        .order('effective_start_date', ascending: false)
        .limit(1)
        .maybeSingle();
    return (row?['hours_per_day'] as num?)?.toDouble() ?? 8.0;
  }

  /// 15.1 残数は「日+時間」の複合で管理する。
  /// 簡易ルール: 失効(expiry_date超過)した付与の消化状況までは追わず、
  /// 有効な付与の合計から全期間の消化量を差し引く(自動失効エンジンはスコープ外)。
  Future<LeaveBalance> fetchMyLeaveBalance() async {
    final employeeId = await _fetchMyEmployeeId();
    final hoursPerDay = await fetchHoursPerDay();
    if (employeeId == null) {
      return LeaveBalance(remainingDays: 0, remainingHours: 0, hoursPerDay: hoursPerDay);
    }

    final today = DateTime.now().toIso8601String().substring(0, 10);
    final grantRows = await _client
        .from('leave_grants')
        .select('granted_days')
        .eq('employee_id', employeeId)
        .gte('expiry_date', today);
    final totalGrantedDays = (grantRows as List).fold<double>(
      0,
      (sum, row) => sum + ((row as Map<String, dynamic>)['granted_days'] as num).toDouble(),
    );

    final usageRows = await _client
        .from('leave_usages')
        .select('days_used, hours_used')
        .eq('employee_id', employeeId);
    var usedHours = 0.0;
    for (final row in usageRows as List) {
      final map = row as Map<String, dynamic>;
      usedHours += ((map['days_used'] as num).toDouble()) * hoursPerDay;
      usedHours += (map['hours_used'] as num).toDouble();
    }

    final remainingTotalHours =
        (totalGrantedDays * hoursPerDay - usedHours).clamp(0, double.infinity);
    final remainingDays = (remainingTotalHours / hoursPerDay).floor();
    final remainingHours = remainingTotalHours - remainingDays * hoursPerDay;

    return LeaveBalance(
      remainingDays: remainingDays,
      remainingHours: remainingHours,
      hoursPerDay: hoursPerDay,
    );
  }

  /// 15.1 申請はシフトが入っている日に対して行う。
  Future<bool> hasShiftOn(DateTime date) async {
    final employeeId = await _fetchMyEmployeeId();
    if (employeeId == null) return false;
    final dateStr = date.toIso8601String().substring(0, 10);
    final row = await _client
        .from('shifts')
        .select('id')
        .eq('employee_id', employeeId)
        .eq('work_date', dateStr)
        .maybeSingle();
    return row != null;
  }

  /// 15.1 時間単位年休の上限(年5日相当)チェック用に、直近の付与期間内における
  /// 時間単位消化の合計時間を取得する。
  Future<double> fetchHourlyUsageInLatestGrantPeriod() async {
    final employeeId = await _fetchMyEmployeeId();
    if (employeeId == null) return 0;

    final latestGrant = await _client
        .from('leave_grants')
        .select('grant_date, expiry_date')
        .eq('employee_id', employeeId)
        .order('grant_date', ascending: false)
        .limit(1)
        .maybeSingle();
    if (latestGrant == null) return 0;

    final usageRows = await _client
        .from('leave_usages')
        .select('hours_used, target_date')
        .eq('employee_id', employeeId)
        .eq('usage_unit', 'hour')
        .gte('target_date', latestGrant['grant_date'] as String)
        .lte('target_date', latestGrant['expiry_date'] as String);
    return (usageRows as List).fold<double>(
      0,
      (sum, row) => sum + ((row as Map<String, dynamic>)['hours_used'] as num).toDouble(),
    );
  }

  Future<void> submitPaidLeaveRequest({
    required DateTime targetDate,
    required LeaveUsageUnit usageUnit,
    double? hours,
  }) async {
    final employeeId = await _fetchMyEmployeeId();
    if (employeeId == null) return;

    final details = <String, dynamic>{'usage_unit': usageUnit.code};
    if (usageUnit == LeaveUsageUnit.hour) {
      details['hours'] = hours;
    }

    await _client.from('requests').insert({
      'employee_id': employeeId,
      'request_type': 'paid_leave',
      'target_date': targetDate.toIso8601String().substring(0, 10),
      'details': details,
    });
  }

  /// 6.4 情報変更申請フォームで「現在の登録内容」を表示するための現在値取得。
  Future<({String? address, String? phone})> fetchMyCurrentContact() async {
    final employeeId = await _fetchMyEmployeeId();
    if (employeeId == null) return (address: null, phone: null);
    final row = await _client
        .from('employees')
        .select('address, phone')
        .eq('id', employeeId)
        .maybeSingle();
    return (address: row?['address'] as String?, phone: row?['phone'] as String?);
  }

  /// 15.2 欠勤連絡。「安易に休める印象にならないフォーム」とするため
  /// 理由・連絡事項の入力を必須とする(画面側でバリデーション)。
  Future<void> submitAbsenceRequest({
    required DateTime targetDate,
    required String reason,
    String? detail,
    String? officeMessage,
    required bool hasSubstitute,
    String? substituteDetail,
  }) async {
    final employeeId = await _fetchMyEmployeeId();
    if (employeeId == null) return;

    await _client.from('requests').insert({
      'employee_id': employeeId,
      'request_type': 'absence',
      'target_date': targetDate.toIso8601String().substring(0, 10),
      'details': {
        'reason': reason,
        'detail': detail,
        'office_message': officeMessage,
        'has_substitute': hasSubstitute,
        'substitute_detail': substituteDetail,
      },
    });
  }

  /// 15.3 遅刻・早退。事前申請・事後報告のいずれも対象日と現在日の比較から自動判定する。
  Future<void> submitTardinessRequest({
    required DateTime targetDate,
    required TardinessSubType subType,
    required String time,
    required String reason,
  }) async {
    final employeeId = await _fetchMyEmployeeId();
    if (employeeId == null) return;

    final today = DateTime.now();
    final isAdvance = !targetDate.isBefore(DateTime(today.year, today.month, today.day));

    await _client.from('requests').insert({
      'employee_id': employeeId,
      'request_type': 'tardiness_early_leave',
      'target_date': targetDate.toIso8601String().substring(0, 10),
      'details': {
        'sub_type': subType.code,
        'time': time,
        'reason': reason,
        'timing': isAdvance ? 'advance' : 'after_the_fact',
      },
    });
  }

  /// 6.4 情報変更申請(住所・電話番号・振込先口座)。
  Future<void> submitInfoChangeRequest({
    required DateTime effectiveDate,
    required InfoChangeField field,
    String? newValue,
    String? bankName,
    String? branchName,
    String? accountType,
    String? accountNumber,
    String? accountHolderNameKana,
  }) async {
    final employeeId = await _fetchMyEmployeeId();
    if (employeeId == null) return;

    final details = <String, dynamic>{'change_field': field.code};
    if (field == InfoChangeField.bankAccount) {
      details.addAll({
        'bank_name': bankName,
        'branch_name': branchName,
        'account_type': accountType,
        'account_number': accountNumber,
        'account_holder_name_kana': accountHolderNameKana,
      });
    } else {
      details['new_value'] = newValue;
    }

    await _client.from('requests').insert({
      'employee_id': employeeId,
      'request_type': 'info_change',
      'target_date': effectiveDate.toIso8601String().substring(0, 10),
      'details': details,
    });
  }

  Future<List<AppRequest>> fetchMyRequests() async {
    final employeeId = await _fetchMyEmployeeId();
    if (employeeId == null) return const [];
    final rows = await _client
        .from('requests')
        .select()
        .eq('employee_id', employeeId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((row) => AppRequest.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// 管理者モード(承認待ち申請)を表示・操作してよいか(施設管理範囲を持つロールか)。
  Future<bool> canApproveRequests() async {
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

  Future<List<AppRequest>> fetchPendingRequests() async {
    final rows = await _client
        .from('requests')
        .select('*, employees(name, offices(name))')
        .eq('status', 'pending')
        .order('created_at', ascending: true);
    return (rows as List)
        .map((row) => AppRequest.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> approvePaidLeaveRequest(String requestId, {String? decisionReason}) async {
    await _client.rpc('approve_paid_leave_request', params: {
      'p_request_id': requestId,
      'p_decision_reason': decisionReason,
    });
  }

  Future<void> approveInfoChangeRequest(String requestId, {String? decisionReason}) async {
    await _client.rpc('approve_info_change_request', params: {
      'p_request_id': requestId,
      'p_decision_reason': decisionReason,
    });
  }

  /// 欠勤連絡・遅刻早退など、承認時に副作用テーブルへの書き込みが不要な申請のステータス更新。
  Future<void> approveSimpleRequest(String requestId, {String? decisionReason}) async {
    final employeeId = await _fetchMyEmployeeId();
    await _client.from('requests').update({
      'status': 'approved',
      'approver_id': employeeId,
      'approved_at': DateTime.now().toIso8601String(),
      'decision_reason': decisionReason,
    }).eq('id', requestId);
  }

  Future<void> rejectRequest(String requestId, {String? decisionReason}) async {
    final employeeId = await _fetchMyEmployeeId();
    await _client.from('requests').update({
      'status': 'rejected',
      'approver_id': employeeId,
      'approved_at': DateTime.now().toIso8601String(),
      'decision_reason': decisionReason,
    }).eq('id', requestId);
  }
}
