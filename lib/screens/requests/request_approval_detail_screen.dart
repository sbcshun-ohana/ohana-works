import 'package:flutter/material.dart';

import '../../models/leave_request.dart';
import '../../services/request_service.dart';
import '../../theme/app_theme.dart';

/// 15.4/28.4 管理者モード: 申請の承認/却下。
class RequestApprovalDetailScreen extends StatefulWidget {
  const RequestApprovalDetailScreen({
    super.key,
    required this.request,
    required this.service,
  });

  final AppRequest request;
  final RequestService service;

  @override
  State<RequestApprovalDetailScreen> createState() => _RequestApprovalDetailScreenState();
}

class _RequestApprovalDetailScreenState extends State<RequestApprovalDetailScreen> {
  final _reasonController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  /// 申請種別ごとの内容サマリー(ラベル→値のペア)。
  List<MapEntry<String, String>> get _detailEntries {
    final details = widget.request.details;
    switch (widget.request.requestType) {
      case 'paid_leave':
        final unit = details['usage_unit'] as String?;
        if (unit == null) return const [];
        final label = LeaveUsageUnit.fromCode(unit).label;
        final summary = unit == 'hour' ? '$label(${details['hours']}時間)' : label;
        return [MapEntry('内容', summary)];
      case 'absence':
        return [
          MapEntry('理由', (details['reason'] as String?) ?? ''),
          if ((details['detail'] as String?)?.isNotEmpty ?? false)
            MapEntry('詳細', details['detail'] as String),
          if ((details['office_message'] as String?)?.isNotEmpty ?? false)
            MapEntry('園への連絡事項', details['office_message'] as String),
          MapEntry(
            '代替対応',
            (details['has_substitute'] as bool? ?? false)
                ? 'あり${(details['substitute_detail'] as String?) != null ? '(${details['substitute_detail']})' : ''}'
                : 'なし',
          ),
        ];
      case 'tardiness_early_leave':
        final subType = details['sub_type'] as String?;
        return [
          if (subType != null) MapEntry('種別', TardinessSubType.fromCode(subType).label),
          MapEntry('時刻', (details['time'] as String?) ?? ''),
          MapEntry('区分', details['timing'] == 'advance' ? '事前申請' : '事後報告'),
          MapEntry('理由', (details['reason'] as String?) ?? ''),
        ];
      case 'info_change':
        final field = details['change_field'] as String?;
        if (field == 'bank_account') {
          return [
            const MapEntry('変更項目', '振込先口座'),
            MapEntry('銀行名', (details['bank_name'] as String?) ?? ''),
            MapEntry('支店名', (details['branch_name'] as String?) ?? ''),
            MapEntry('口座種別', (details['account_type'] as String?) ?? ''),
            MapEntry('口座番号', (details['account_number'] as String?) ?? ''),
            MapEntry('口座名義', (details['account_holder_name_kana'] as String?) ?? ''),
          ];
        }
        if (field != null) {
          return [
            MapEntry('変更項目', InfoChangeField.fromCode(field).label),
            MapEntry('新しい値', (details['new_value'] as String?) ?? ''),
          ];
        }
        return const [];
      default:
        return const [];
    }
  }

  Future<void> _decide({required bool approve}) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final reason = _reasonController.text.trim().isEmpty ? null : _reasonController.text.trim();
      if (approve) {
        switch (widget.request.requestType) {
          case 'paid_leave':
            await widget.service.approvePaidLeaveRequest(widget.request.id, decisionReason: reason);
          case 'info_change':
            await widget.service.approveInfoChangeRequest(widget.request.id, decisionReason: reason);
          default:
            await widget.service.approveSimpleRequest(widget.request.id, decisionReason: reason);
        }
      } else {
        await widget.service.rejectRequest(widget.request.id, decisionReason: reason);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(approve ? '承認しました' : '却下しました')),
      );
      Navigator.of(context).pop();
    } catch (_) {
      setState(() => _errorMessage = '処理に失敗しました。もう一度お試しください。');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    return Scaffold(
      appBar: AppBar(title: const Text('申請詳細')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              request.employeeName ?? '(不明な職員)',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            if (request.officeName != null) ...[
              const SizedBox(height: 4),
              Text(request.officeName!, style: const TextStyle(color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 16),
            _DetailRow(label: '種別', value: requestTypeLabel(request.requestType)),
            _DetailRow(
              label: '対象日',
              value: '${request.targetDate.year}/${request.targetDate.month}/${request.targetDate.day}',
            ),
            for (final entry in _detailEntries) _DetailRow(label: entry.key, value: entry.value),
            const SizedBox(height: 24),
            const Text('却下理由・コメント(任意)', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: _reasonController,
              maxLines: 3,
              decoration: const InputDecoration(hintText: '却下する場合は理由を入力してください'),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w500),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting ? null : () => _decide(approve: false),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.punchClockOut),
                    child: const Text('却下'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : () => _decide(approve: true),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.leafGreen),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Text('承認'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
