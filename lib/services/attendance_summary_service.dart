import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/attendance_summary.dart';

/// 11章/12章 月次勤怠集計エンジン。
///
/// 実処理はDB側のRPC run_attendance_summary()(20260714000007)で行い、
/// 本サービスは労務管理者以上のみ実行可能な管理者操作としてラップする。
/// 同じRPCは将来Supabase Scheduled Function(pg_cron/Edge Function)から
/// service_role経由で無人実行することも想定している。
class AttendanceSummaryService {
  AttendanceSummaryService(this._client);

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

  /// 月次勤怠集計の実行・実行結果閲覧を行ってよいか(労務管理者以上のみ)。
  Future<bool> canRunSummary() async {
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

  Future<String> runSummary({required DateTime targetMonth}) async {
    final result = await _client.rpc('run_attendance_summary', params: {
      'p_target_month': targetMonth.toIso8601String().substring(0, 10),
    });
    return result as String;
  }

  Future<List<AttendanceSummaryRun>> fetchRuns() async {
    final rows = await _client
        .from('attendance_summary_runs')
        .select('*, employees(name)')
        .order('created_at', ascending: false);
    return (rows as List)
        .map((row) => AttendanceSummaryRun.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<AttendanceSummary>> fetchSummariesForMonth(DateTime targetMonth) async {
    final monthStr = DateTime(targetMonth.year, targetMonth.month, 1)
        .toIso8601String()
        .substring(0, 10);
    final rows = await _client
        .from('attendance_summaries')
        .select('*, employees(name, offices(name))')
        .eq('target_month', monthStr)
        .order('employee_id');
    return (rows as List)
        .map((row) => AttendanceSummary.fromJson(row as Map<String, dynamic>))
        .toList();
  }
}
