import 'package:flutter/material.dart';

import '../../models/parent_request.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';

/// 保護者申請の詳細。園とのやりとり(parent_request_messages)も表示・送信できる。
class ParentRequestDetailScreen extends StatefulWidget {
  const ParentRequestDetailScreen({
    super.key,
    required this.guardianService,
    required this.request,
    required this.guardianId,
  });

  final GuardianService guardianService;
  final ParentRequest request;
  final String guardianId;

  @override
  State<ParentRequestDetailScreen> createState() => _ParentRequestDetailScreenState();
}

class _ParentRequestDetailScreenState extends State<ParentRequestDetailScreen> {
  late Future<List<ParentRequestMessage>> _messagesFuture;
  final _messageController = TextEditingController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _messagesFuture = widget.guardianService.fetchParentRequestMessages(widget.request.id);
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    setState(() => _isSending = true);
    await widget.guardianService.sendParentRequestMessage(
      requestId: widget.request.id,
      guardianId: widget.guardianId,
      message: text,
    );
    _messageController.clear();
    if (!mounted) return;
    setState(() {
      _load();
      _isSending = false;
    });
  }

  String _formatDateTime(DateTime d) =>
      '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    return Scaffold(
      appBar: AppBar(title: Text(parentRequestTypeLabels[request.requestType] ?? request.requestType)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '対象日: ${request.targetDate.year}/${request.targetDate.month}/${request.targetDate.day}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        Text(
                          parentRequestStatusLabel(request.status),
                          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.skyBlue),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...request.details.entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('${e.key}: ${e.value}'),
                      ),
                    ),
                    if (request.decisionReason?.isNotEmpty ?? false) ...[
                      const Divider(height: 24),
                      const Text('園からのコメント', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Text(request.decisionReason!),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<ParentRequestMessage>>(
              future: _messagesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data ?? const [];
                if (messages.isEmpty) {
                  return const Center(
                    child: Text('やりとりはまだありません', style: TextStyle(color: AppColors.textSecondary)),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return Align(
                      alignment: message.isFromGuardian ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        constraints: const BoxConstraints(maxWidth: 280),
                        decoration: BoxDecoration(
                          color: message.isFromGuardian
                              ? AppColors.skyBlue.withValues(alpha: 0.15)
                              : AppColors.background,
                          border: message.isFromGuardian ? null : Border.all(color: AppColors.textSecondary.withValues(alpha: 0.2)),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(message.message),
                            const SizedBox(height: 4),
                            Text(
                              _formatDateTime(message.createdAt),
                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(hintText: '園にメッセージを送る'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _isSending ? null : _sendMessage,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
