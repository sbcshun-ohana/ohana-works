/// 自分の給与明細(fetch_my_payslips RPCの結果)。PDF実体はSupabase Storageの
/// payslipsバケットに `{employee_id}/{payroll_run_id}.pdf` の形式で保存されている。
class Payslip {
  const Payslip({
    required this.id,
    required this.payrollRunId,
    required this.targetMonth,
    required this.filePath,
    required this.generatedAt,
    this.viewedAt,
  });

  factory Payslip.fromJson(Map<String, dynamic> json) => Payslip(
        id: json['id'] as String,
        payrollRunId: json['payroll_run_id'] as String,
        targetMonth: DateTime.parse(json['target_month'] as String),
        filePath: json['file_path'] as String,
        generatedAt: DateTime.parse(json['generated_at'] as String),
        viewedAt: json['viewed_at'] == null ? null : DateTime.parse(json['viewed_at'] as String),
      );

  final String id;
  final String payrollRunId;
  final DateTime targetMonth;
  final String filePath;
  final DateTime generatedAt;
  final DateTime? viewedAt;
}
