import 'package:flutter/material.dart';

import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';

/// 厨房向け 給食会議の閲覧(305)。調理に必要な「対象児・除去/代替の提供方針・開催日・同意状況」を読み取り専用で表示。
class MealConferenceViewScreen extends StatefulWidget {
  const MealConferenceViewScreen({super.key, required this.service, required this.officeId, required this.officeName});
  final ChildcareService service;
  final String officeId;
  final String officeName;

  @override
  State<MealConferenceViewScreen> createState() => _MealConferenceViewScreenState();
}

class _MealConferenceViewScreenState extends State<MealConferenceViewScreen> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await widget.service.fetchMealConferencesForKitchen(widget.officeId);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('給食会議  ${widget.officeName}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Center(child: Text('給食会議の記録はありません', style: TextStyle(color: AppColors.textSecondary)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _rows.length,
                    separatorBuilder: (_, i) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _card(_rows[i]),
                  ),
                ),
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final consented = r['consent_at'] != null;
    final status = r['status'] as String? ?? '';
    final statusLabel = consented ? '同意済み' : (status == 'held' ? '同意待ち' : status);
    final statusColor = consented ? AppColors.leafGreen : AppColors.warmOrange;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(r['child_name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
                  child: Text(statusLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: statusColor)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (r['held_on'] != null) Text('開催日: ${r['held_on']}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            if ((r['nutritionist_name'] as String?)?.isNotEmpty ?? false)
              Text('栄養士: ${r['nutritionist_name']}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            const Text('除去・代替の提供方針', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            Text((r['elimination_plan'] as String?)?.isNotEmpty == true ? r['elimination_plan'] as String : '—',
                style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
