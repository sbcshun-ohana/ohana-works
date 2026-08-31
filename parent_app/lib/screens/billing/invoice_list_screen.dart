import 'package:flutter/material.dart';

import '../../models/guardian_invoice.dart';
import '../../models/linked_child.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';

/// ご請求(保護者向け・請求Phase8a)。公開済み請求書の一覧と明細を閲覧する。
/// お支払い(オンライン決済)はPhase8bで追加予定(payment_enabledで出し分け)。
class InvoiceListScreen extends StatefulWidget {
  const InvoiceListScreen({super.key, required this.guardianService, required this.child});

  final GuardianService guardianService;
  final LinkedChild child;

  @override
  State<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends State<InvoiceListScreen> {
  bool _loading = true;
  String? _error;
  List<GuardianInvoice> _invoices = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await widget.guardianService.fetchMyInvoices();
      final mine = all.where((i) => i.childId == widget.child.childId).toList();
      if (mounted) {
        setState(() {
          _invoices = mine;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('invoice list fetch error: $e');
      if (mounted) {
        setState(() {
          _error = 'ご請求の取得に失敗しました';
          _loading = false;
        });
      }
    }
  }

  String _yen(int n) => '¥${n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';

  (String, Color) _statusBadge(GuardianInvoice inv) {
    switch (inv.status) {
      case 'paid':
        return ('お支払い済み', AppColors.leafGreen);
      case 'partially_paid':
        return ('一部お支払い済み', AppColors.warmOrange);
      case 'overdue':
        return ('お支払い期限を過ぎています', Colors.redAccent);
      default:
        return ('お支払いのお願い', AppColors.skyBlue);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ご請求(${widget.child.displayName}${widget.child.honorificSuffix ?? 'ちゃん'})')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : _invoices.isEmpty
                  ? const Center(child: Text('公開済みのご請求はありません'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _invoices.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final inv = _invoices[index];
                          final (label, color) = _statusBadge(inv);
                          return Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              title: Text(
                                '${inv.billingMonth.year}年${inv.billingMonth.month}月分',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(label,
                                        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
                                  ),
                                  if (inv.dueDate != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'お支払い期限: ${inv.dueDate!.year}/${inv.dueDate!.month}/${inv.dueDate!.day}',
                                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                                      ),
                                    ),
                                ],
                              ),
                              trailing: Text(_yen(inv.totalAmount),
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              onTap: () => Navigator.of(context).push<void>(
                                MaterialPageRoute(
                                  builder: (_) => InvoiceDetailScreen(
                                    guardianService: widget.guardianService,
                                    invoice: inv,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class InvoiceDetailScreen extends StatefulWidget {
  const InvoiceDetailScreen({super.key, required this.guardianService, required this.invoice});

  final GuardianService guardianService;
  final GuardianInvoice invoice;

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  bool _loading = true;
  String? _error;
  GuardianInvoiceDetail? _detail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.guardianService.fetchMyInvoiceDetail(widget.invoice.invoiceId);
      if (mounted) {
        setState(() {
          _detail = d;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('invoice detail fetch error: $e');
      if (mounted) {
        setState(() {
          _error = '明細の取得に失敗しました';
          _loading = false;
        });
      }
    }
  }

  String _yen(int n) => '¥${n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';

  @override
  Widget build(BuildContext context) {
    final inv = widget.invoice;
    return Scaffold(
      appBar: AppBar(title: Text('${inv.billingMonth.year}年${inv.billingMonth.month}月分のご請求')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('請求番号: ${_detail!.invoiceNo}',
                                style: const TextStyle(fontSize: 12, color: Colors.black54)),
                            const SizedBox(height: 12),
                            for (final item in _detail!.items)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.isAdjustment ? '【請求額調整】${item.description}' : item.description,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: item.isAdjustment ? AppColors.warmOrange : Colors.black87,
                                            ),
                                          ),
                                          if (item.targetPeriod != null)
                                            Text(item.targetPeriod!,
                                                style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                          if (item.unitAmount != null && item.quantity != 1)
                                            Text('${_yen(item.unitAmount!)} × ${item.quantity}',
                                                style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                        ],
                                      ),
                                    ),
                                    Text(_yen(item.amount),
                                        style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('合計', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text(_yen(_detail!.totalAmount),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                              ],
                            ),
                            if (_detail!.dueDate != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'お支払い期限: ${_detail!.dueDate!.year}年${_detail!.dueDate!.month}月${_detail!.dueDate!.day}日',
                                  style: const TextStyle(color: Colors.black54),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // お支払い方法のご案内。オンライン決済(8b)は payment_enabled で切替予定
                    if (!_detail!.paymentEnabled)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'お支払い方法は園からのご案内をご確認ください。\nアプリでのお支払いは準備中です。',
                            style: TextStyle(color: Colors.black54),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
