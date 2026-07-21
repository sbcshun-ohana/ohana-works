import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/my_attendance.dart';
import '../models/my_shift.dart';
import '../models/payslip.dart';

/// Phase1 A: 職員セルフビュー(自分の勤怠・給与明細)。
/// 給与・勤怠の管理者向け操作(AttendanceSummaryService/PayrollService)とは別に、
/// 本人が自分自身のデータのみ参照する用途に限定したサービス。
class MyDataService {
  MyDataService(this._client);

  final SupabaseClient _client;

  /// 自分の勤怠(月間・施設別)。daily_attendances(生データ)から都度組み立てる
  /// fetch_my_attendance RPCを呼ぶため、月次集計(attendance_summaries)が
  /// 未実行の月でも正しく表示される。
  Future<List<MyAttendanceDay>> fetchMyAttendance({
    required DateTime monthStart,
    required DateTime monthEnd,
  }) async {
    final rows = await _client.rpc('fetch_my_attendance', params: {
      'p_month_start': _formatDate(monthStart),
      'p_month_end': _formatDate(monthEnd),
    });
    return (rows as List)
        .map((row) => MyAttendanceDay.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// 自分のシフト(月間・施設別)。shiftsはoffice_idを直接持ち、既存のRLS
  /// (shifts_select_self)で自己参照が許可されているためRPCは不要。
  /// employee_idで明示的に絞り込む(shifts_select_selfは管理施設分も見える設計のため、
  /// 絞り込まないと管理者は部下のシフトまで一緒に取得してしまう)。
  Future<List<MyShift>> fetchMyShifts({
    required DateTime monthStart,
    required DateTime monthEnd,
  }) async {
    final employeeId = await _fetchMyEmployeeId();
    if (employeeId == null) return const [];
    final rows = await _client
        .from('shifts')
        .select('*, offices(name)')
        .eq('employee_id', employeeId)
        .gte('work_date', _formatDate(monthStart))
        .lte('work_date', _formatDate(monthEnd))
        .order('work_date');
    return (rows as List).map((row) => MyShift.fromJson(row as Map<String, dynamic>)).toList();
  }

  Future<String?> _fetchMyEmployeeId() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _client.from('employees').select('id').eq('auth_user_id', userId).maybeSingle();
    return row?['id'] as String?;
  }

  /// 自分の給与明細一覧(直近12ヶ月分)。退職後6ヶ月を過ぎると空になる
  /// (is_within_payslip_access_windowによりRPC側で制御される)。
  Future<List<Payslip>> fetchMyPayslips() async {
    final rows = await _client.rpc('fetch_my_payslips');
    return (rows as List).map((row) => Payslip.fromJson(row as Map<String, dynamic>)).toList();
  }

  /// 給与明細PDFの署名付きURL(5分間有効)。Storage側のRLSでも退職後6ヶ月の
  /// アクセス制限が適用されるため、期限切れ後はここでエラーになる。
  Future<String> createPayslipSignedUrl(String filePath) async {
    return _client.storage.from('payslips').createSignedUrl(filePath, 60 * 5);
  }

  String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
