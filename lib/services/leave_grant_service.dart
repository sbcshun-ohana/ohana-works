import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/leave_grant_run.dart';

/// 15.1 有給自動付与エンジン(労基法39条準拠: 8割出勤要件・比例付与)。
///
/// 実処理はDB側のRPC run_paid_leave_auto_grant()(20260714000006)で行い、
/// 本サービスは労務管理者以上のみ実行可能な管理者操作としてラップする。
/// 同じRPCは将来Supabase Scheduled Function(pg_cron/Edge Function)から
/// service_role経由で無人実行することも想定している。
class LeaveGrantService {
  LeaveGrantService(this._client);

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

  /// 有給自動付与の実行・実行結果閲覧を行ってよいか(労務管理者以上のみ、5.3準拠)。
  Future<bool> canRunAutoGrant() async {
    final employeeId = await _fetchMyEmployeeId();
    if (employeeId == null) return false;
    final rows = await _client
        .from('employee_roles')
        .select('roles(code)')
        .eq('employee_id', employeeId);
    const laborManagerRoleCodes = {'labor_manager', 'system_admin'};
    return (rows as List).any((row) {
      final role = (row as Map<String, dynamic>)['roles'] as Map<String, dynamic>?;
      return laborManagerRoleCodes.contains(role?['code']);
    });
  }

  Future<String> runAutoGrant({DateTime? targetDate}) async {
    final date = targetDate ?? DateTime.now();
    final result = await _client.rpc('run_paid_leave_auto_grant', params: {
      'p_target_date': date.toIso8601String().substring(0, 10),
    });
    return result as String;
  }

  Future<List<LeaveGrantRun>> fetchRuns() async {
    final rows = await _client
        .from('leave_grant_runs')
        .select('*, employees(name)')
        .order('created_at', ascending: false);
    return (rows as List)
        .map((row) => LeaveGrantRun.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<LeaveGrantRunResult>> fetchRunResults(String runId) async {
    final rows = await _client
        .from('leave_grant_run_results')
        .select('*, employees(name)')
        .eq('leave_grant_run_id', runId)
        .order('employee_id');
    return (rows as List)
        .map((row) => LeaveGrantRunResult.fromJson(row as Map<String, dynamic>))
        .toList();
  }
}
