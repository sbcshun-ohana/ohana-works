import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/payroll_run.dart';

/// 16章〜18章 給与計算エンジン。
///
/// 実処理はDB側のRPC run_payroll()(20260714000008)で行い、本サービスは
/// 労務管理者以上のみ実行可能な管理者操作としてラップする。同じRPCは将来
/// Supabase Scheduled Function(pg_cron/Edge Function)から無人実行することも
/// 想定している。17章の給与確定(確定ロック・振込CSV・PDF発行・通知)はスコープ外。
class PayrollService {
  PayrollService(this._client);

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

  /// 給与計算の実行・結果閲覧を行ってよいか(労務管理者以上のみ、5.3/16章準拠)。
  Future<bool> canRunPayroll() async {
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

  Future<String> runPayroll({required DateTime targetMonth}) async {
    final result = await _client.rpc('run_payroll', params: {
      'p_target_month': targetMonth.toIso8601String().substring(0, 10),
    });
    return result as String;
  }

  Future<List<PayrollRun>> fetchRuns() async {
    final rows = await _client
        .from('payroll_runs')
        .select()
        .order('target_month', ascending: false);
    return (rows as List)
        .map((row) => PayrollRun.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<PayrollDetail>> fetchDetails(String payrollRunId) async {
    final rows = await _client
        .from('payroll_details')
        .select('*, employees(name, offices(name))')
        .eq('payroll_run_id', payrollRunId)
        .order('employee_id');
    return (rows as List)
        .map((row) => PayrollDetail.fromJson(row as Map<String, dynamic>))
        .toList();
  }
}
