import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/guardian_profile.dart';
import '../../models/linked_child.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';
import '../announcements/broadcast_notice_list_screen.dart';
import '../invitation/invitation_entry_screen.dart';
import 'child_detail_screen.dart';

/// 保護者アプリのホーム。紐づく園児一覧と、各園児のQR表示への導線。
/// 家庭連絡帳・保護者申請・クラス写真等はPhase Aの後続画面として追加していく。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.guardianService, required this.profile});

  final GuardianService guardianService;
  final GuardianProfile profile;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<LinkedChild>> _childrenFuture;
  List<LinkedChild> _children = const [];
  // お知らせ(一斉配信)は機能フラグ parent_broadcast_notices が有効な園児がいる時のみ表示。
  // フラグ未定義/OFF なら false=非表示(安全側)。
  bool _broadcastEnabled = false;
  int _broadcastUnread = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final future = widget.guardianService.fetchLinkedChildren(guardianId: widget.profile.id);
    _childrenFuture = future;
    future.then((children) async {
      final enabled = await widget.guardianService.isBroadcastNoticesEnabled(children);
      final unread = enabled ? await widget.guardianService.fetchBroadcastUnreadCount(widget.profile.id) : 0;
      if (!mounted) return;
      setState(() {
        _children = children;
        _broadcastEnabled = enabled;
        _broadcastUnread = unread;
      });
    });
  }

  void _reload() {
    setState(_load);
  }

  Future<void> _openBroadcastNotices() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BroadcastNoticeListScreen(
          guardianService: widget.guardianService,
          guardianId: widget.profile.id,
          children: _children,
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  Future<void> _addAnotherChild() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => InvitationEntryScreen(
          guardianService: widget.guardianService,
          onAccepted: () {
            Navigator.of(context).pop();
            _reload();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('こんにちは、${widget.profile.name}さん'),
        actions: [
          IconButton(icon: const Icon(Icons.logout_rounded), tooltip: 'ログアウト', onPressed: _signOut),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addAnotherChild,
        icon: const Icon(Icons.add_rounded),
        label: const Text('招待コードを追加'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<LinkedChild>>(
          future: _childrenFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final children = snapshot.data ?? const [];
            if (children.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: const [
                  SizedBox(height: 80),
                  Icon(Icons.child_care_rounded, size: 64, color: AppColors.textSecondary),
                  SizedBox(height: 16),
                  Text(
                    'まだ園児が紐づいていません。右下から招待コードを入力してください',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              );
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                if (_broadcastEnabled)
                  _BroadcastNoticeCard(unreadCount: _broadcastUnread, onTap: _openBroadcastNotices),
                ...children.map((child) => _ChildCard(
                      child: child,
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => ChildDetailScreen(
                            guardianService: widget.guardianService,
                            child: child,
                            guardianId: widget.profile.id,
                          ),
                        ),
                      ),
                    )),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 園児を選ばずトップから入る「お知らせ(一斉配信)」への導線。園児横断・未読バッジ付き。
class _BroadcastNoticeCard extends StatelessWidget {
  const _BroadcastNoticeCard({required this.unreadCount, required this.onTap});

  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.warmOrange.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.campaign_rounded, color: AppColors.warmOrange),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'お知らせ',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ),
              if (unreadCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.warmOrange,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$unreadCount',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  const _ChildCard({required this.child, required this.onTap});

  final LinkedChild child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: AppColors.skyBlue.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: const Icon(Icons.child_care_rounded, color: AppColors.skyBlue),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      child.nameLabel,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    if (child.officeName != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          child.officeName!,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (child.className != null) child.className!,
                        childStatusLabel(child.todayStatus),
                      ].join(' ・ '),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
