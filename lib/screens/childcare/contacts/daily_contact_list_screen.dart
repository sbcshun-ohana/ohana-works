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

  @override
  void initState() {
    super.initState();
    _load();
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
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<DailyContact>>(
          future: _contactsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final contacts = snapshot.data ?? const [];
            if (contacts.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [SizedBox(height: 120), Center(child: Text('在籍園児がいません'))],
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
