import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/childcare.dart';
import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ohana_logo_home_button.dart';

/// §13 承認済み文章のコピー(コドモン運用)。承認済みの連絡帳のみコピー可能。
/// 基本は申請者、不在時は他職員・管理者が対応可能(誰でもコピー操作は行える)。
class ContactCopyScreen extends StatefulWidget {
  const ContactCopyScreen({
    super.key,
    required this.service,
    required this.officeId,
    required this.businessDate,
  });

  final ChildcareService service;
  final String officeId;
  final DateTime businessDate;

  @override
  State<ContactCopyScreen> createState() => _ContactCopyScreenState();
}

class _ContactCopyScreenState extends State<ContactCopyScreen> {
  late Future<List<DailyContact>> _contactsFuture;
  String? _copiedChildId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _contactsFuture = widget.service
        .fetchDailyContactsForOffice(widget.officeId, widget.businessDate)
        .then((rows) => rows.where((r) => r.status == 'approved').toList());
  }

  Future<void> _reload() async {
    setState(_load);
    await _contactsFuture;
  }

  Future<void> _copy(DailyContact contact) async {
    if (contact.contactId == null || contact.currentText == null) return;
    await Clipboard.setData(ClipboardData(text: contact.currentText!));
    await widget.service.markChildDailyContactCopied(contact.contactId!);
    setState(() => _copiedChildId = contact.childId);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const OhanaLogoHomeButton(),
        leadingWidth: 148,
        toolbarHeight: 48,
        title: const Text('承認済み連絡帳のコピー'),
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
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('承認済みの連絡帳はまだありません')),
                ],
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
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${contact.nameLabel}${contact.className != null ? " (${contact.className})" : ""}',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () => _copy(contact),
                              child: Text(_copiedChildId == contact.childId ? 'コピーしました' : 'コピーする'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            contact.currentText ?? '',
                            style: const TextStyle(fontSize: 15, height: 1.5),
                          ),
                        ),
                        if (contact.copiedAt != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '最終コピー: ${contact.copiedAt!.month}/${contact.copiedAt!.day} '
                            '${contact.copiedAt!.hour.toString().padLeft(2, '0')}:'
                            '${contact.copiedAt!.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ],
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
