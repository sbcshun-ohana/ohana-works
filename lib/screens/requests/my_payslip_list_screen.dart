import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/payslip.dart';
import '../../services/my_data_service.dart';
import '../../theme/app_theme.dart';

/// Phase1 A-5: 自分の給与明細一覧(直近12ヶ月)。fetch_my_payslips RPCは
/// is_within_payslip_access_window()により退職後6ヶ月で自動的に空になる。
class MyPayslipListScreen extends StatefulWidget {
  const MyPayslipListScreen({super.key, required this.service});

  final MyDataService service;

  @override
  State<MyPayslipListScreen> createState() => _MyPayslipListScreenState();
}

class _MyPayslipListScreenState extends State<MyPayslipListScreen> {
  late Future<List<Payslip>> _payslipsFuture;
  String? _openingId;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _payslipsFuture = widget.service.fetchMyPayslips();
  }

  Future<void> _open(Payslip payslip) async {
    setState(() {
      _openingId = payslip.id;
      _errorMessage = null;
    });
    try {
      final url = await widget.service.createPayslipSignedUrl(payslip.filePath);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) setState(() => _errorMessage = '明細を開けませんでした。もう一度お試しください');
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('給与明細')),
      body: FutureBuilder<List<Payslip>>(
        future: _payslipsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final payslips = snapshot.data ?? const [];
          return Column(
            children: [
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_errorMessage!, style: const TextStyle(color: AppColors.punchError)),
                ),
              Expanded(
                child: payslips.isEmpty
                    ? const Center(
                        child: Text('給与明細はまだありません', style: TextStyle(color: AppColors.textSecondary)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: payslips.length,
                        itemBuilder: (context, index) {
                          final payslip = payslips[index];
                          final isOpening = _openingId == payslip.id;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.description_outlined, color: AppColors.skyBlue),
                                  title: Text('${payslip.targetMonth.year}年${payslip.targetMonth.month}月分'),
                                  subtitle: Text(
                                    '発行日: ${payslip.generatedAt.year}/${payslip.generatedAt.month}/${payslip.generatedAt.day}',
                                  ),
                                  trailing: isOpening
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                                  onTap: isOpening ? null : () => _open(payslip),
                                ),
                                _MealDaysExpansion(service: widget.service, month: payslip.targetMonth),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 賃金明細に添付する「その月の食事日一覧」(給食管理 Phase3・336)。展開時に読み込む。
class _MealDaysExpansion extends StatefulWidget {
  const _MealDaysExpansion({required this.service, required this.month});

  final MyDataService service;
  final DateTime month;

  @override
  State<_MealDaysExpansion> createState() => _MealDaysExpansionState();
}

class _MealDaysExpansionState extends State<_MealDaysExpansion> {
  List<Map<String, dynamic>>? _days;
  bool _loading = false;

  static const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

  Future<void> _load() async {
    if (_days != null || _loading) return;
    setState(() => _loading = true);
    try {
      final rows = await widget.service.fetchMyMealDays(widget.month);
      if (mounted) setState(() { _days = rows; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _days = const []; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      title: const Text('この月の食事日一覧', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      onExpansionChanged: (open) { if (open) _load(); },
      children: [
        if (_loading)
          const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())
        else if (_days == null || _days!.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(alignment: Alignment.centerLeft, child: Text('食事の記録はありません', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
          )
        else ...[
          ..._days!.map((d) {
            final date = DateTime.parse(d['business_date'] as String);
            final wd = _weekdays[date.weekday - 1];
            final price = (d['unit_price'] as num?)?.toInt() ?? 0;
            final auto = (d['source'] as String?) == 'auto';
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: Row(
                children: [
                  Expanded(child: Text('${date.month}/${date.day}($wd)  ${auto ? '自動' : '発注'}', style: const TextStyle(fontSize: 13))),
                  Text('$price円', style: const TextStyle(fontSize: 13)),
                ],
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(child: Text('合計 ${_days!.length}食', style: const TextStyle(fontWeight: FontWeight.w700))),
                Text('${_days!.fold<int>(0, (s, d) => s + ((d['unit_price'] as num?)?.toInt() ?? 0))}円 控除',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
