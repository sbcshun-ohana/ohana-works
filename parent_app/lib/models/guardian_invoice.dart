/// 保護者向け請求書(請求Phase8a・397)。公開済み(issued以降)のみサーバーから返る。
class GuardianInvoice {
  const GuardianInvoice({
    required this.invoiceId,
    required this.invoiceNo,
    required this.childId,
    required this.childName,
    required this.billingMonth,
    required this.status,
    required this.totalAmount,
    required this.paidAmount,
    this.dueDate,
  });

  final String invoiceId;
  final String invoiceNo;
  final String childId;
  final String childName;
  final DateTime billingMonth;
  final String status;
  final int totalAmount;
  final int paidAmount;
  final DateTime? dueDate;

  factory GuardianInvoice.fromMap(Map<String, dynamic> m) => GuardianInvoice(
        invoiceId: m['invoice_id'] as String,
        invoiceNo: m['invoice_no'] as String,
        childId: m['child_id'] as String,
        childName: m['child_name'] as String? ?? '',
        billingMonth: DateTime.parse(m['billing_month'] as String),
        status: m['status'] as String? ?? '',
        totalAmount: (m['total_amount'] as num?)?.toInt() ?? 0,
        paidAmount: (m['paid_amount'] as num?)?.toInt() ?? 0,
        dueDate: m['due_date'] != null ? DateTime.parse(m['due_date'] as String) : null,
      );
}

class GuardianInvoiceItem {
  const GuardianInvoiceItem({
    required this.description,
    this.targetPeriod,
    required this.quantity,
    this.unitAmount,
    required this.amount,
    required this.isAdjustment,
  });

  final String description;
  final String? targetPeriod;
  final num quantity;
  final int? unitAmount;
  final int amount;
  final bool isAdjustment;

  factory GuardianInvoiceItem.fromMap(Map<String, dynamic> m) => GuardianInvoiceItem(
        description: m['description'] as String? ?? '',
        targetPeriod: m['target_period'] as String?,
        quantity: (m['quantity'] as num?) ?? 1,
        unitAmount: (m['unit_amount'] as num?)?.toInt(),
        amount: (m['amount'] as num?)?.toInt() ?? 0,
        isAdjustment: m['is_adjustment'] == true,
      );
}

class GuardianInvoiceDetail {
  const GuardianInvoiceDetail({
    required this.invoiceNo,
    required this.childName,
    required this.billingMonth,
    required this.status,
    required this.totalAmount,
    required this.paidAmount,
    this.dueDate,
    required this.paymentEnabled,
    required this.items,
  });

  final String invoiceNo;
  final String childName;
  final DateTime billingMonth;
  final String status;
  final int totalAmount;
  final int paidAmount;
  final DateTime? dueDate;
  final bool paymentEnabled; // 8b(Stripe)で支払いボタンの出し分けに使う
  final List<GuardianInvoiceItem> items;

  factory GuardianInvoiceDetail.fromMap(Map<String, dynamic> m) {
    final inv = (m['invoice'] as Map).cast<String, dynamic>();
    return GuardianInvoiceDetail(
      invoiceNo: inv['invoice_no'] as String? ?? '',
      childName: inv['child_name'] as String? ?? '',
      billingMonth: DateTime.parse(inv['billing_month'] as String),
      status: inv['status'] as String? ?? '',
      totalAmount: (inv['total_amount'] as num?)?.toInt() ?? 0,
      paidAmount: (inv['paid_amount'] as num?)?.toInt() ?? 0,
      dueDate: inv['due_date'] != null ? DateTime.parse(inv['due_date'] as String) : null,
      paymentEnabled: m['payment_enabled'] == true,
      items: ((m['items'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(GuardianInvoiceItem.fromMap)
          .toList(),
    );
  }
}
