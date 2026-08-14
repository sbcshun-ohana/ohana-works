import 'package:flutter/material.dart';

import '../../models/linked_child.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/child_context_app_bar_title.dart';
import '../class_photos/class_photos_screen.dart';
import '../communication_book/communication_book_list_screen.dart';
import '../communication_book/communication_book_notice_list_screen.dart';
import '../family_report/family_daily_report_screen.dart';
import '../infection/handover_card_screen.dart';
import '../infection/return_notice_screen.dart';
import '../parent_request/parent_request_list_screen.dart';
import '../qr/child_qr_screen.dart';

/// 園児ごとの機能ハブ。アイコン付きグリッドで各機能への入口を並べる。
class ChildDetailScreen extends StatefulWidget {
  const ChildDetailScreen({
    super.key,
    required this.guardianService,
    required this.child,
    required this.guardianId,
  });

  final GuardianService guardianService;
  final LinkedChild child;
  final String guardianId;

  @override
  State<ChildDetailScreen> createState() => _ChildDetailScreenState();
}

class _ChildDetailScreenState extends State<ChildDetailScreen> {
  int _unreadCommunicationBookCount = 0;
  int _unreadNoticeCount = 0;
  Set<String> _enabledFeatures = {};
  bool _isLoadingFeatures = true;
  // 感染症の手続き表示(206)。進行中案件があるときだけカードを出す。
  List<({String caseId, String origin, String status, String? diseaseName, String? returnCriteria,
      String requiredDocument, String documentState, String? formTemplatePath})> _infectionCases = const [];

  @override
  void initState() {
    super.initState();
    _loadFeatureFlags();
    _loadUnreadCounts();
    _loadInfectionCases();
  }

  Future<void> _loadInfectionCases() async {
    try {
      final cases = await widget.guardianService.fetchMyChildInfectionCases(widget.child.childId);
      if (mounted) setState(() => _infectionCases = cases);
    } catch (_) {
      // 取得失敗時は非表示(安全側)。
    }
  }

  Future<void> _openFormPdf(String path) async {
    try {
      final url = await widget.guardianService.createDocumentTemplateUrl(path);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('様式のダウンロード', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          content: SelectableText('以下のURLをブラウザで開くとPDFを表示・保存できます(5分間有効)\n\n$url'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる'))],
        ),
      );
    } catch (_) {}
  }

  Future<void> _openHandoverCard(
      ({String caseId, String origin, String status, String? diseaseName, String? returnCriteria,
        String requiredDocument, String documentState, String? formTemplatePath}) c) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => HandoverCardScreen(
          guardianService: widget.guardianService,
          child: widget.child,
          caseId: c.caseId,
          caseStatus: c.status,
        ),
      ),
    );
    if (changed == true) _loadInfectionCases();
  }

  // 感染症の手続きカード(206・設計書§8: 必要書類と次の手続きを大きく表示)。
  Widget _infectionCaseCard(
      ({String caseId, String origin, String status, String? diseaseName, String? returnCriteria,
        String requiredDocument, String documentState, String? formTemplatePath}) c) {
    final docLabel = c.requiredDocument == 'opinion_letter'
        ? '登園許可書(医師記入)'
        : c.requiredDocument == 'return_form'
            ? '登園届(保護者記入)'
            : null;
    final submitted = c.documentState == 'submitted_electronically' || c.documentState == 'received_on_paper';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.medical_information_rounded, color: AppColors.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    c.status == 'awaiting_medical_result'
                        ? '園から引き継ぎカードが届いています'
                        : '感染症の手続き: ${c.diseaseName ?? '感染症'}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ],
          ),
          if (c.origin == 'handover') ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _openHandoverCard(c),
              icon: const Icon(Icons.badge_rounded, size: 18),
              label: Text(c.status == 'awaiting_medical_result' ? 'カードを見る・受診結果を入力' : 'カードを見る'),
            ),
          ],
          if (c.returnCriteria != null) ...[
            const SizedBox(height: 8),
            Text('登園のめやす: ${c.returnCriteria}', style: const TextStyle(fontSize: 13)),
          ],
          if (docLabel != null) ...[
            const SizedBox(height: 8),
            Text(
              submitted ? '$docLabel: 提出済みです' : '登園には $docLabel の提出が必要です',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: submitted ? AppColors.leafGreen : AppColors.danger),
            ),
          ],
          // 211: 電子登園届(登園届対象・未提出のとき)
          if (c.requiredDocument == 'return_form' && !submitted) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () async {
                final done = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => ReturnNoticeScreen(
                      guardianService: widget.guardianService,
                      child: widget.child,
                      caseId: c.caseId,
                    ),
                  ),
                );
                if (done == true) _loadInfectionCases();
              },
              icon: const Icon(Icons.assignment_turned_in_rounded, size: 18),
              label: const Text('登園届を入力・提出する'),
            ),
          ],
          if (!submitted && c.formTemplatePath != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _openFormPdf(c.formTemplatePath!),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
              label: const Text('様式PDFを表示'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _loadFeatureFlags() async {
    final flags = await widget.guardianService.fetchGuardianFeatureFlags(widget.child.childId);
    if (!mounted) return;
    setState(() {
      _enabledFeatures = flags;
      _isLoadingFeatures = false;
    });
  }

  Future<void> _loadUnreadCounts() async {
    final counts = await widget.guardianService.fetchUnreadCounts(
      childId: widget.child.childId,
      guardianId: widget.guardianId,
    );
    if (!mounted) return;
    setState(() {
      _unreadCommunicationBookCount = counts.communicationBook;
      _unreadNoticeCount = counts.notice;
    });
  }

  Future<void> _openAndRefresh(Widget screen) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _loadUnreadCounts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ChildContextAppBarTitle(title: widget.child.nameLabel, officeName: widget.child.officeName),
      ),
      body: _isLoadingFeatures
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                for (final c in _infectionCases) _infectionCaseCard(c),
                Expanded(child: _buildGrid()),
              ],
            ),
    );
  }

  Widget _buildGrid() {
    final items = <Widget>[
      if (_enabledFeatures.contains('attendance_qr'))
        _GridMenuItem(
          icon: Icons.qr_code_2_rounded,
          color: AppColors.skyBlue,
          label: '登降園QR',
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => ChildQrScreen(guardianService: widget.guardianService, child: widget.child),
            ),
          ),
        ),
      if (_enabledFeatures.contains('guardian_requests'))
        _GridMenuItem(
          icon: Icons.assignment_rounded,
          color: AppColors.skyBlue,
          label: '保護者からの申請・連絡',
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => ParentRequestListScreen(
                guardianService: widget.guardianService,
                child: widget.child,
                guardianId: widget.guardianId,
              ),
            ),
          ),
        ),
      if (_enabledFeatures.contains('family_daily_report'))
        _GridMenuItem(
          icon: Icons.edit_note_rounded,
          color: AppColors.leafGreen,
          label: 'ご家庭からの連絡帳',
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => FamilyDailyReportScreen(guardianService: widget.guardianService, child: widget.child),
            ),
          ),
        ),
      if (_enabledFeatures.contains('communication_book'))
        _GridMenuItem(
          icon: Icons.menu_book_rounded,
          color: AppColors.warmOrange,
          label: '保育園からの連絡帳',
          badgeCount: _unreadCommunicationBookCount,
          onTap: () => _openAndRefresh(
            CommunicationBookListScreen(
              guardianService: widget.guardianService,
              child: widget.child,
              guardianId: widget.guardianId,
            ),
          ),
        ),
      if (_enabledFeatures.contains('guardian_notices'))
        _GridMenuItem(
          icon: Icons.campaign_rounded,
          color: AppColors.warmOrange,
          label: '保育園からのお知らせ',
          badgeCount: _unreadNoticeCount,
          onTap: () => _openAndRefresh(
            CommunicationBookNoticeListScreen(
              guardianService: widget.guardianService,
              child: widget.child,
              guardianId: widget.guardianId,
            ),
          ),
        ),
      if (_enabledFeatures.contains('class_photos'))
        _GridMenuItem(
          icon: Icons.photo_library_rounded,
          color: AppColors.leafGreen,
          label: 'クラス写真',
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => ClassPhotosScreen(guardianService: widget.guardianService, child: widget.child),
            ),
          ),
        ),
    ];

    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '現在ご利用いただける機能はありません。園からのご案内をお待ちください',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return GridView.count(
      padding: const EdgeInsets.all(16),
      crossAxisCount: 3,
      childAspectRatio: 0.85,
      children: items,
    );
  }
}

/// CODMON等の保育園アプリでよく見る、丸背景アイコン+下ラベルのグリッドタイル。
class _GridMenuItem extends StatelessWidget {
  const _GridMenuItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 28),
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(999)),
                      alignment: Alignment.center,
                      child: Text(
                        '$badgeCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
