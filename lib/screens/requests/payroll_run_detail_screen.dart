import 'package:flutter/material.dart';

import '../../models/payroll_run.dart';
import '../../services/payroll_service.dart';
import '../../theme/app_theme.dart';

String _formatYen(int amount) => '${amount.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (m) => ',',
    )}円';

/// 16章〜18章 給与計算結果の職員ごとの内訳(給与明細相当)。
class PayrollRunDetailScreen extends StatefulWidget {
  const PayrollRunDetailScreen({super.key, required this.run, required this.service});

  final PayrollRun run;
  final PayrollService service;

  @override
  State<PayrollRunDetailScreen> createState() => _PayrollRunDetailScreenState();
}

class _PayrollRunDetailScreenState extends State<PayrollRunDetailScreen> {
  late Future<List<PayrollDetail>> _detailsFuture;

  @override
  void initState() {
    super.initState();
    _detailsFuture = widget.service.fetchDetails(widget.run.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('給与計算 ${widget.run.targetMonth.year}/${widget.run.targetMonth.month}'),
      ),
      body: FutureBuilder<List<PayrollDetail>>(
        future: _detailsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final details = snapshot.data ?? const [];
          if (details.isEmpty) {
            return const Center(child: Text('この対象月の給与明細はありません'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: details.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final d = details[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              d.employeeName ?? '(不明な職員)',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                          ),
                          Text(
                            _formatYen(d.netPay),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: AppColors.leafGreen,
                            ),
                          ),
                        ],
                      ),
                      if (d.officeName != null) ...[
                        const SizedBox(height: 2),
                        Text(d.officeName!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      ],
                      const Divider(height: 20),
                      Text('支給', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.skyBlue)),
                      _Row('基本給', d.baseSalary),
                      _Row('手当', d.allowanceTotal),
                      if (d.specialDutyAllowance != 0) _Row('特殊業務手当', d.specialDutyAllowance),
                      if (d.earlyShiftAllowance != 0) _Row('早番手当', d.earlyShiftAllowance),
                      _Row('時間外割増', d.overtimePremium),
                      if (d.nightPremium != 0) _Row('深夜割増', d.nightPremium),
                      if (d.holidayPremium != 0) _Row('法定休日割増', d.holidayPremium),
                      _Row('交通費', d.commuteAllowance),
                      _Row('支給合計', d.grossTotal, bold: true),
                      const SizedBox(height: 12),
                      Text('控除', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.punchClockOut)),
                      if (d.absenceDeduction != 0) _Row('欠勤・遅刻早退控除', d.absenceDeduction),
                      _Row('健康保険', d.healthInsurance),
                      if (d.careInsurance != 0) _Row('介護保険', d.careInsurance),
                      _Row('厚生年金', d.pensionInsurance),
                      _Row('雇用保険', d.employmentInsurance),
                      _Row('源泉所得税', d.incomeTax),
                      _Row('住民税', d.residentTax),
                      if (d.burdenFee != 0) _Row('負担金', d.burdenFee),
                      if (d.companyHousingDeduction != 0) _Row('借上宿舎本人負担金', d.companyHousingDeduction),
                      _Row('控除合計', d.deductionsTotal, bold: true),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.amount, {this.bold = false});

  final String label;
  final int amount;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final text = _formatYen(amount);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            text,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: bold ? AppColors.textPrimary : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
