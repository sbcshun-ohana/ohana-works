import 'package:flutter/material.dart';

import '../../../models/childcare.dart';
import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/business_date_action.dart';
import '../../../widgets/ohana_logo_home_button.dart';
import 'daily_contact_detail_screen.dart';

/// §10-13 連絡帳一覧(施設内の在籍園児の当日分)。
class DailyContactListScreen extends StatefulWidget {
  const DailyContactListScreen({
    super.key,
    required this.service,
    required this.officeId,
    required this.businessDate,
    required this.isManager,
  });

  final ChildcareService service;
  final String officeId;
  final DateTime businessDate;
  final bool isManager;

  @override
  State<DailyContactListScreen> createState() => _DailyContactListScreenState();
}

class _DailyContactListScreenState extends State<DailyContactListScreen> {
  late DateTime _businessDate = widget.businessDate;
  late Future<List<DailyContact>> _contactsFuture;
  // クラス絞り込み(俊指示 2026-08-13)。null=全クラス。
  List<ChildcareClass> _classes = const [];
  String? _selectedClassId;

  @override
  void initState() {
    super.initState();
    _load();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    final c = await widget.service.fetchChildcareClasses(widget.officeId);
    if (mounted) setState(() => _classes = c);
  }

  void _load() {
    _contactsFuture = widget.service.fetchDailyContactsForOffice(widget.officeId, _businessDate);
  }

  Future<void> _reload() async {
    setState(_load);
    await _contactsFuture;
  }

  void _onDateChanged(DateTime d) {
    setState(() {
      _businessDate = d;
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const OhanaLogoHomeButton(),
        leadingWidth: 148,
        toolbarHeight: 48,
        title: const Text('連絡帳'),
        actions: [BusinessDateAction(date: _businessDate, onChanged: _onDateChanged)],
      ),
      body: Column(
        children: [
          // クラス絞り込み(表示のみのフィルタ。データ取得は施設単位のまま)。
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _selectedClassId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'クラス', isDense: true, border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('全クラス')),
                      for (final c in _classes) DropdownMenuItem<String?>(value: c.classId, child: Text(c.className)),
                    ],
                    onChanged: (v) => setState(() => _selectedClassId = v),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: FutureBuilder<List<DailyContact>>(
                future: _contactsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final all = snapshot.data ?? const [];
                  // クラス名一致で絞り込み(DailyContact は classId を持たないため className で対応)。
                  final selectedClassName = _selectedClassId == null
                      ? null
                      : _classes
                          .firstWhere((c) => c.classId == _selectedClassId,
                              orElse: () => const ChildcareClass(classId: '', className: '', ageGroup: '', schoolYear: 0))
                          .className;
                  final contacts =
                      selectedClassName == null ? all : all.where((c) => c.className == selectedClassName).toList();
                  if (contacts.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [SizedBox(height: 120), Center(child: Text('対象の園児がいません'))],
                    );
                  }
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: contacts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final contact = contacts[index];
                return Card(
                  child: Opacity(
                    opacity: contact.isAbsent ? 0.5 : 1,
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      title: Text(
                        '${contact.nameLabel}${contact.isAbsent ? "(欠席)" : ""}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${contact.className ?? ""} ・ 担当: ${contact.assigneeName ?? "未割当"}',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      trailing: _StatusChip(status: contact.status),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => DailyContactDetailScreen(
                              service: widget.service,
                              officeId: widget.officeId,
                              childId: contact.childId,
                              childNameLabel: contact.nameLabel,
                              businessDate: _businessDate,
                              isManager: widget.isManager,
                            ),
                          ),
                        );
                        await _reload();
                      },
                    ),
                  ),
                );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String? status;

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (status) {
      case 'approved':
        color = AppColors.leafGreen;
      case 'rejected':
        color = AppColors.punchClockOut;
      case 'submitted':
        color = AppColors.skyBlue;
      default:
        color = AppColors.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
      child: Text(
        childcareStatusLabel(status),
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}
