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
                            child: ListTile(
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
