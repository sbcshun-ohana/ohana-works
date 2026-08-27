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

  // ===== 給食の注文(自己注文モデル・365-371) =====
  /// 曜日テンプレ(毎週の既定。月=0..日=6)。設定済みの曜日のみ返る。
  Future<List<Map<String, dynamic>>> fetchStaffMealWeeklyTemplate() async {
    final rows = await _client.rpc('fetch_staff_meal_weekly_template');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 曜日テンプレを設定(食べる/食べない)。weekday: 0=月..6=日。
  Future<void> setStaffMealWeeklyTemplate(int weekday, bool willEat) async {
    await _client.rpc('set_staff_meal_weekly_template', params: {'p_weekday': weekday, 'p_will_eat': willEat});
  }

  /// 月カレンダー(各日の実効◯×・締切・施設休)。business_date/will_eat/office_id/locked/blocked_reason。
  Future<List<Map<String, dynamic>>> fetchStaffMealMonth(int year, int month) async {
    final rows = await _client.rpc('fetch_staff_meal_month', params: {'p_year': year, 'p_month': month});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 日別の注文上書き(食べる/食べない)。当日は8:55締め。
  Future<void> setStaffMealEntry(DateTime date, bool willEat) async {
    await _client.rpc('set_staff_meal_entry', params: {'p_date': _formatDate(date), 'p_will_eat': willEat});
  }

  /// 当日分の日別上書きを取り消して曜日テンプレに戻す。
  Future<void> clearStaffMealEntry(DateTime date) async {
    await _client.rpc('clear_staff_meal_entry', params: {'p_date': _formatDate(date)});
  }

  /// 自己発注画面用: 自分の所属施設の公開済み献立(当日/翌日の昼食メニュー等)。
  Future<List<Map<String, dynamic>>> fetchMyOfficeMenuDay(DateTime date) async {
    final rows = await _client.rpc('fetch_my_office_menu_day', params: {'p_date': _formatDate(date)});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 賃金明細添付用: 当月の食事日一覧(日付・種別・単価)。
  Future<List<Map<String, dynamic>>> fetchMyMealDays(DateTime month) async {
    final rows = await _client.rpc('fetch_my_meal_days',
        params: {'p_month': _formatDate(DateTime(month.year, month.month, 1))});
    return (rows as List).cast<Map<String, dynamic>>();
  }
}
