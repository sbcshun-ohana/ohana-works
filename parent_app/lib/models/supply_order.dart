/// 備品注文(401)。カタログ=料金マスターのsupply品目(単価登録済みのみ)。
class SupplyCatalogItem {
  const SupplyCatalogItem({
    required this.feeItemId,
    required this.name,
    required this.unitAmount,
    this.displayNote,
  });

  final String feeItemId;
  final String name;
  final int unitAmount;
  final String? displayNote;

  factory SupplyCatalogItem.fromMap(Map<String, dynamic> m) => SupplyCatalogItem(
        feeItemId: m['fee_item_id'] as String,
        name: m['name'] as String? ?? '',
        unitAmount: (m['unit_amount'] as num?)?.toInt() ?? 0,
        displayNote: m['display_note'] as String?,
      );
}

class SupplyOrder {
  const SupplyOrder({
    required this.orderId,
    required this.itemName,
    required this.quantity,
    required this.status,
    this.unitAmount,
    this.amount,
    this.note,
    this.rejectedReason,
    required this.requestedAt,
  });

  final String orderId;
  final String itemName;
  final int quantity;
  final String status; // requested/approved/rejected/cancelled
  final int? unitAmount;
  final int? amount;
  final String? note;
  final String? rejectedReason;
  final DateTime requestedAt;

  factory SupplyOrder.fromMap(Map<String, dynamic> m) => SupplyOrder(
        orderId: m['order_id'] as String,
        itemName: m['item_name'] as String? ?? '',
        quantity: (m['quantity'] as num?)?.toInt() ?? 1,
        status: m['status'] as String? ?? '',
        unitAmount: (m['unit_amount'] as num?)?.toInt(),
        amount: (m['amount'] as num?)?.toInt(),
        note: m['note'] as String?,
        rejectedReason: m['rejected_reason'] as String?,
        requestedAt: DateTime.parse(m['requested_at'] as String).toLocal(),
      );
}
