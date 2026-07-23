import 'package:flutter/material.dart';

import '../../models/communication_book_entry.dart';
import '../../models/linked_child.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/child_context_app_bar_title.dart';
import 'communication_book_detail_screen.dart';

/// 承認済みの園連絡帳一覧(新しい日付順)。
class CommunicationBookListScreen extends StatefulWidget {
  const CommunicationBookListScreen({
    super.key,
    required this.guardianService,
    required this.child,
    required this.guardianId,
  });

  final GuardianService guardianService;
  final LinkedChild child;
  final String guardianId;

  @override
  State<CommunicationBookListScreen> createState() => _CommunicationBookListScreenState();
}

class _CommunicationBookListScreenState extends State<CommunicationBookListScreen> {
  late Future<List<CommunicationBookEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = widget.guardianService.fetchCommunicationBookHistory(widget.child.childId);
  }

  String _formatDate(DateTime d) => '${d.year}/${d.month}/${d.day}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ChildContextAppBarTitle(
          title: '${widget.child.nameLabel}の保育園からの連絡帳',
          officeName: widget.child.officeName,
        ),
      ),
      body: FutureBuilder<List<CommunicationBookEntry>>(
        future: _entriesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data ?? const [];
          if (entries.isEmpty) {
            return const Center(
              child: Text('公開された連絡帳はまだありません', style: TextStyle(color: AppColors.textSecondary)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.menu_book_rounded, color: AppColors.warmOrange),
                  title: Text(_formatDate(entry.businessDate)),
                  subtitle: Text(
                    (entry.currentText?.isNotEmpty ?? false) ? entry.currentText! : '(本文なし)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => CommunicationBookDetailScreen(
                        guardianService: widget.guardianService,
                        entryId: entry.id,
                        guardianId: widget.guardianId,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
