import 'package:flutter/material.dart';

import '../../../models/guardian_app.dart';
import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';

/// 保護者アプリ・後続保育機能 Phase A: 保護者管理・招待管理(職員側の閲覧・簡易操作)。
class GuardianManagementScreen extends StatefulWidget {
  const GuardianManagementScreen({super.key, required this.service, required this.officeId});

  final ChildcareService service;
  final String officeId;

  @override
  State<GuardianManagementScreen> createState() => _GuardianManagementScreenState();
}

class _GuardianManagementScreenState extends State<GuardianManagementScreen> {
  late Future<List<GuardianRow>> _guardiansFuture;
  late Future<List<GuardianInvitationRow>> _invitationsFuture;
  late Future<List<ChildForInvitation>> _childrenFuture;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _guardiansFuture = widget.service.fetchGuardiansForOffice(widget.officeId);
    _invitationsFuture = widget.service.fetchPendingGuardianInvitations(widget.officeId);
    _childrenFuture = widget.service.fetchChildrenForOffice(widget.officeId);
  }

  Future<void> _reload() async {
    setState(_load);
    await Future.wait([_guardiansFuture, _invitationsFuture]);
  }

  Future<void> _toggleSuspend(GuardianRow guardian) async {
    if (guardian.status == 'active') {
      final reason = await _promptText('停止理由(必須)');
      if (reason == null || reason.trim().isEmpty) return;
      setState(() => _isBusy = true);
      try {
        await widget.service.suspendGuardianAccount(guardian.guardianId, reason.trim());
      } finally {
        if (mounted) setState(() => _isBusy = false);
      }
    } else {
      setState(() => _isBusy = true);
      try {
        await widget.service.reactivateGuardianAccount(guardian.guardianId);
      } finally {
        if (mounted) setState(() => _isBusy = false);
      }
    }
    await _reload();
  }

  Future<String?> _promptText(String title) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true, maxLines: 2),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('決定'),
          ),
        ],
      ),
    );
  }

  Future<void> _showNewInvitationDialog() async {
    final children = await _childrenFuture;
    if (!mounted) return;
    if (children.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('招待可能な園児がいません')));
      return;
    }

    ChildForInvitation selectedChild = children.first;
    String selectedRole = 'primary';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('新規招待'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('園児', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              DropdownButton<ChildForInvitation>(
                isExpanded: true,
                value: selectedChild,
                items: children
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text('${c.nameLabel}${c.className != null ? "(${c.className})" : ""}'),
                        ))
                    .toList(),
                onChanged: (c) {
                  if (c != null) setDialogState(() => selectedChild = c);
                },
              ),
              const SizedBox(height: 12),
              const Text('役割', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              DropdownButton<String>(
                isExpanded: true,
                value: selectedRole,
                items: const [
                  DropdownMenuItem(value: 'primary', child: Text('主たる保護者')),
                  DropdownMenuItem(value: 'additional', child: Text('追加保護者')),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => selectedRole = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('キャンセル')),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('発行')),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isBusy = true);
    try {
      final result = await widget.service.createGuardianInvitationByStaff(
        childId: selectedChild.childId,
        role: selectedRole,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('招待コード'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'この画面でのみ表示されます。保護者へ直接お伝えください(スクリーンショット等での共有は避けてください)。',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              SelectableText(result.token, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              const SizedBox(height: 8),
              Text(
                '有効期限: ${result.expiresAt.year}/${result.expiresAt.month}/${result.expiresAt.day} '
                '${result.expiresAt.hour.toString().padLeft(2, '0')}:${result.expiresAt.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
          actions: [
            ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('閉じる')),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('保護者管理')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isBusy ? null : _showNewInvitationDialog,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('新規招待'),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            const Text('保護者一覧', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            FutureBuilder<List<GuardianRow>>(
              future: _guardiansFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final guardians = snapshot.data ?? const [];
                if (guardians.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('保護者が登録されていません', style: TextStyle(color: AppColors.textSecondary)),
                  );
                }
                return Column(
                  children: guardians
                      .map(
                        (g) => Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              [
                                if (g.phone != null) g.phone!,
                                if (g.linkedChildren != null) '紐づく園児: ${g.linkedChildren}',
                              ].join(' ・ '),
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (g.status == 'active' ? AppColors.leafGreen : AppColors.punchClockOut)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    g.status == 'active' ? '有効' : '停止中',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: g.status == 'active' ? AppColors.leafGreen : AppColors.punchClockOut,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    g.status == 'active' ? Icons.block_rounded : Icons.check_circle_outline_rounded,
                                  ),
                                  onPressed: _isBusy ? null : () => _toggleSuspend(g),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 24),
            const Text('招待履歴', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            FutureBuilder<List<GuardianInvitationRow>>(
              future: _invitationsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final invitations = snapshot.data ?? const [];
                if (invitations.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('招待履歴はありません', style: TextStyle(color: AppColors.textSecondary)),
                  );
                }
                return Column(
                  children: invitations
                      .map(
                        (inv) => Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            title: Text(inv.childDisplayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              '${inv.role == "primary" ? "主たる保護者" : "追加保護者"} ・ '
                              '期限: ${inv.expiresAt.month}/${inv.expiresAt.day}',
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                            trailing: Text(
                              guardianInvitationStatusLabel(inv.status),
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}
