import 'package:flutter/material.dart';

import '../../models/linked_child.dart';
import '../../models/supply_order.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';

/// 備品注文(保護者向け・401)。園の備品カタログから注文→園の承認で確定→次回請求に合算。
/// 申請中のみ取消可。却下時は理由が表示される。
class SupplyOrderScreen extends StatefulWidget {
  const SupplyOrderScreen({super.key, required this.guardianService, required this.child});

  final GuardianService guardianService;
  final LinkedChild child;

  @override
  State<SupplyOrderScreen> createState() => _SupplyOrderScreenState();
}

class _SupplyOrderScreenState extends State<SupplyOrderScreen> {
  bool _loading = true;
  String? _error;
  List<SupplyCatalogItem> _catalog = const [];
  List<SupplyOrder> _orders = const [];

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
      final catalog = await widget.guardianService.fetchSupplyCatalog(widget.child.childId);
      final orders = await widget.guardianService.fetchMySupplyOrders(widget.child.childId);
      if (mounted) {
        setState(() {
          _catalog = catalog;
          _orders = orders;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('supply order fetch error: $e');
      if (mounted) {
        setState(() {
          _error = '備品注文の取得に失敗しました';
          _loading = false;
        });
      }
    }
  }

  String _yen(int n) => '¥${n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';

  Future<void> _order(SupplyCatalogItem item) async {
    var quantity = 1;
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(item.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('単価: ${_yen(item.unitAmount)}'),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('数量'),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: quantity > 1 ? () => setDialogState(() => quantity--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$quantity', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    onPressed: quantity < 20 ? () => setDialogState(() => quantity++) : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: '備考(サイズ・色など・任意)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text('合計 ${_yen(item.unitAmount * quantity)}(園の承認後、次回のご請求に合算されます)',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('キャンセル')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('注文する')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.guardianService.createSupplyOrder(
          widget.child.childId, item.feeItemId, quantity,
          noteController.text.trim().isEmpty ? null : noteController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('注文しました(園の承認をお待ちください)')));
      }
      await _load();
    } catch (e) {
      debugPrint('supply order create error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('注文に失敗しました')));
      }
    }
  }

  Future<void> _cancel(SupplyOrder order) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('注文の取消'),
        content: Text('「${order.itemName} × ${order.quantity}」の注文を取り消しますか?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('いいえ')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('取り消す')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.guardianService.cancelSupplyOrder(order.orderId);
      await _load();
    } catch (e) {
      debugPrint('supply order cancel error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('取消に失敗しました')));
      }
    }
  }

  (String, Color) _statusBadge(SupplyOrder o) {
    switch (o.status) {
      case 'approved':
        return ('承認済み(次回請求に合算)', AppColors.leafGreen);
      case 'rejected':
        return ('お受けできませんでした', Colors.redAccent);
      case 'cancelled':
        return ('取消済み', Colors.grey);
      default:
        return ('園の承認待ち', AppColors.warmOrange);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('備品注文(${widget.child.displayName}${widget.child.honorificSuffix ?? 'ちゃん'})')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text('注文できる備品', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (_catalog.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('現在注文できる備品はありません', style: TextStyle(color: Colors.black54)),
                        ),
                      for (final item in _catalog)
                        Card(
                          child: ListTile(
                            title: Text(item.name),
                            subtitle: item.displayNote != null ? Text(item.displayNote!) : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_yen(item.unitAmount),
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: () => _order(item),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  child: const Text('注文'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      const Text('注文履歴', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (_orders.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('注文履歴はありません', style: TextStyle(color: Colors.black54)),
                        ),
                      for (final order in _orders)
                        Card(
                          child: ListTile(
                            title: Text('${order.itemName} × ${order.quantity}'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Builder(builder: (context) {
                                  final (label, color) = _statusBadge(order);
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(label,
                                        style: TextStyle(
                                            fontSize: 12, color: color, fontWeight: FontWeight.w600)),
                                  );
                                }),
                                if (order.rejectedReason != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text('理由: ${order.rejectedReason}',
                                        style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '${order.requestedAt.year}/${order.requestedAt.month}/${order.requestedAt.day}'
                                    '${order.amount != null ? '  ${_yen(order.amount!)}' : ''}',
                                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                                  ),
                                ),
                              ],
                            ),
                            trailing: order.status == 'requested'
                                ? TextButton(
                                    onPressed: () => _cancel(order),
                                    child: const Text('取消', style: TextStyle(color: Colors.redAccent)),
                                  )
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
