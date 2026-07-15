/// 16章〜18章 給与計算。payroll_runs/payroll_details(20260714000008)に対応。
class PayrollRun {
  const PayrollRun({
    required this.id,
    required this.targetMonth,
    required this.status,
    required this.createdAt,
  });

  factory PayrollRun.fromJson(Map<String, dynamic> json) {
    return PayrollRun(
      id: json['id'] as String,
      targetMonth: DateTime.parse(json['target_month'] as String),
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final DateTime targetMonth;
  final String status;
  final DateTime createdAt;

  String get statusLabel {
    switch (status) {
      case 'draft':
        return '未確定';
      case 'confirmed':
        return '確定済み';
      case 'transferred':
        return '振込済み';
      default:
        return status;
    }
  }
}

/// 職員1名分の給与明細内訳。
class PayrollDetail {
  const PayrollDetail({
    required this.id,
    required this.employeeId,
    required this.earnings,
    required this.deductions,
    required this.netPay,
    this.employeeName,
    this.officeName,
  });

  factory PayrollDetail.fromJson(Map<String, dynamic> json) {
    final employee = json['employees'] as Map<String, dynamic>?;
    final office = employee?['offices'] as Map<String, dynamic>?;
    return PayrollDetail(
      id: json['id'] as String,
      employeeId: json['employee_id'] as String,
      earnings: (json['earnings'] as Map).cast<String, dynamic>(),
      deductions: (json['deductions'] as Map).cast<String, dynamic>(),
      netPay: json['net_pay'] as int,
      employeeName: employee?['name'] as String?,
      officeName: office?['name'] as String?,
    );
  }

  final String id;
  final String employeeId;
  final Map<String, dynamic> earnings;
  final Map<String, dynamic> deductions;
  final int netPay;
  final String? employeeName;
  final String? officeName;

  int _int(Map<String, dynamic> map, String key) => (map[key] as num?)?.toInt() ?? 0;

  int get baseSalary => _int(earnings, 'base_salary');
  int get allowanceTotal => _int(earnings, 'allowance_total');
  int get specialDutyAllowance => _int(earnings, 'special_duty_allowance');
  int get earlyShiftAllowance => _int(earnings, 'early_shift_allowance');
  int get overtimePremium => _int(earnings, 'overtime_premium');
  int get nightPremium => _int(earnings, 'night_premium');
  int get holidayPremium => _int(earnings, 'holiday_premium');
  int get commuteAllowance => _int(earnings, 'commute_allowance');
  int get grossTotal => _int(earnings, 'gross_total');

  int get absenceDeduction => _int(deductions, 'absence_deduction');
  int get healthInsurance => _int(deductions, 'health_insurance');
  int get careInsurance => _int(deductions, 'care_insurance');
  int get pensionInsurance => _int(deductions, 'pension_insurance');
  int get employmentInsurance => _int(deductions, 'employment_insurance');
  int get incomeTax => _int(deductions, 'income_tax');
  int get residentTax => _int(deductions, 'resident_tax');
  int get burdenFee => _int(deductions, 'burden_fee');
  int get companyHousingDeduction => _int(deductions, 'company_housing_deduction');
  int get deductionsTotal => _int(deductions, 'deductions_total');
}
