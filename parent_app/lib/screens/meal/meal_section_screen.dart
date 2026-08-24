import 'package:flutter/material.dart';

import '../../models/linked_child.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';
import 'meal_consent_screen.dart';
import 'allergy_incident_report_screen.dart';
import '../food_check/food_check_screen.dart';

/// 給食セクション(264・保護者)。公開済みの「今月の献立」と「食育レター」を閲覧する。
/// 退避構成: 画像はインライン表示、PDF/Excel はタップで署名URL(5分間有効)を表示。
class MealSectionScreen extends StatefulWidget {
  const MealSectionScreen({super.key, required this.guardianService, required this.child});

  final GuardianService guardianService;
  final LinkedChild child;

  @override
  State<MealSectionScreen> createState() => _MealSectionScreenState();
}

typedef _MenuItem = ({String kind, String sourcePath, String? sourceFilename, String format, String? publishedAt});

class _MealSectionScreenState extends State<MealSectionScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  bool _loading = true;
  String? _error;
  List<_MenuItem> _items = const [];
  final Map<String, String> _signedUrls = {};
  // 構造化献立(267/270): 日→区分→本文+材料。子の食種(年齢代替)で取得。
  List<({DateTime menuDate, String mealSlot, String menuText, String ingredients})> _menuDays = const [];
  // 除去食献立(276・保護者限定): 除去食提供中の児のみ。空なら非表示。
  List<({DateTime menuDate, String mealSlot, String menuText, String ingredients, String? removalKind, String? removalNote})>
      _allergyMenuDays = const [];
  // アレルギー除去食の同意(272/273): 同意待ち件数 / 同意履歴の有無。この区画をこの画面内に統合。
  int _pendingConsents = 0;
  bool _hasConsentHistory = false;
  // 本日の給食写真(300・公開済み): 選択月に依らず「今日」の分を表示。
  List<({String id, String storagePath, String? caption})> _todayPhotos = const [];
  final Map<String, String> _photoUrls = {};
  // 給食入口に統合(俊指示 2026-08-24): 食材チェック(224)・アレルギー発症報告(271)。
  bool _foodCheckEnabled = false;
  bool _mealMgmtEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final foodType = GuardianService.foodTypeForAgeGroup(widget.child.ageGroup);
      final results = await Future.wait([
        widget.guardianService.fetchPublishedMealMenu(widget.child.officeId, _month),
        widget.guardianService.fetchPublishedMenuDays(widget.child.officeId, _month, foodType),
      ]);
      final items = results[0] as List<_MenuItem>;
      final menuDays = results[1] as List<({DateTime menuDate, String mealSlot, String menuText, String ingredients})>;
      // 除去食の同意(件数のみ)+ 除去食献立。失敗しても通常献立表示は続行。
      try {
        final pending = await widget.guardianService.fetchPendingMealConsents(widget.child.childId);
        final history = await widget.guardianService.fetchMealConsentHistory(widget.child.childId);
        final allergyMenu = await widget.guardianService.fetchAllergyMenuDaysForChild(widget.child.childId, _month);
        if (mounted) {
          _pendingConsents = pending.length;
          _hasConsentHistory = history.isNotEmpty;
          _allergyMenuDays = allergyMenu;
        }
      } catch (_) {}
      // 給食入口に統合した機能の表示可否(失敗は非表示=安全側)。
      try {
        _foodCheckEnabled = await widget.guardianService.isFoodCheckEnabled(widget.child.childId);
      } catch (_) {}
      try {
        _mealMgmtEnabled = await widget.guardianService.isMealManagementEnabled(widget.child.officeId);
      } catch (_) {}
      // 本日の給食写真(公開済み)。失敗しても献立表示は続行。
      try {
        final photos = await widget.guardianService.fetchPublishedMealPhotos(widget.child.childId, DateTime.now());
        for (final p in photos) {
          try {
            _photoUrls[p.storagePath] = await widget.guardianService.mealPhotoSignedUrl(p.storagePath);
          } catch (_) {}
        }
        if (mounted) _todayPhotos = photos;
      } catch (_) {}
      // 画像は署名URLを先に取得してインライン表示する。
      for (final it in items.where((e) => e.format == 'image')) {
        try {
          final url = await widget.guardianService.mealMenuSignedUrl(it.sourcePath);
          if (mounted) _signedUrls[it.sourcePath] = url;
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _items = items;
          _menuDays = menuDays;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '取得に失敗しました';
          _loading = false;
        });
      }
    }
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
    _load();
  }

  Future<void> _openFile(_MenuItem it) async {
    try {
      final url = _signedUrls[it.sourcePath] ?? await widget.guardianService.mealMenuSignedUrl(it.sourcePath);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(it.sourceFilename ?? '献立', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          content: SelectableText('以下のURLをブラウザで開くと表示・保存できます(5分間有効)\n\n$url'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる'))],
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final letters = _items.where((e) => e.kind == 'letter').toList();
    return Scaffold(
      appBar: AppBar(title: const Text('給食')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // 月切替
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left_rounded)),
                Text('${_month.year}年${_month.month}月',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                IconButton(onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right_rounded)),
              ],
            ),
            if (_loading) ...[
              const SizedBox(height: 60),
              const Center(child: CircularProgressIndicator()),
            ] else if (_error != null) ...[
              const SizedBox(height: 40),
              Center(child: Text(_error!, style: const TextStyle(color: AppColors.danger))),
            ] else ...[
              // アレルギー発症報告(緊急性があるため最上部に目立たせる)。
              if (_mealMgmtEnabled) ...[
                _entryButton(
                  icon: Icons.report_gmailerrorred_rounded,
                  color: AppColors.danger,
                  label: 'アレルギー発症報告',
                  desc: '給食後の症状を園へ報告します',
                  onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(
                    builder: (_) => AllergyIncidentReportScreen(guardianService: widget.guardianService, child: widget.child),
                  )),
                ),
                const SizedBox(height: 12),
              ],
              if (_foodCheckEnabled) ...[
                _entryButton(
                  icon: Icons.restaurant_rounded,
                  color: AppColors.leafGreen,
                  label: '食材チェック',
                  desc: '家庭で食べた食材の確認・登録',
                  onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(
                    builder: (_) => FoodCheckScreen(guardianService: widget.guardianService, child: widget.child),
                  )),
                ),
                const SizedBox(height: 24),
              ],
              if (_todayPhotos.isNotEmpty) ...[
                _todayPhotoSection(),
                const SizedBox(height: 24),
              ],
              if (_pendingConsents > 0 || _hasConsentHistory) ...[
                _consentEntry(),
                const SizedBox(height: 24),
              ],
              if (_allergyMenuDays.isNotEmpty) ...[
                _allergyMenuSection(),
                const SizedBox(height: 24),
              ],
              _structuredSection(),
              const SizedBox(height: 24),
              // 献立ファイル(元データ・Excel等)は保護者には非表示(俊指示 2026-08-21)。
              _section('食育レター', letters, Icons.menu_book_rounded),
            ],
          ],
        ),
      ),
    );
  }

  // 給食入口に統合した機能への遷移ボタン(食材チェック・アレルギー発症報告)。
  Widget _entryButton({required IconData icon, required Color color, required String label, required String desc, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  Text(desc, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  // 本日の給食(300)。公開済み写真をカードで表示。タップで拡大。
  Widget _todayPhotoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.photo_camera_rounded, color: AppColors.warmOrange, size: 20),
            SizedBox(width: 6),
            Text('本日の給食', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 10),
        for (final p in _todayPhotos) ...[
          if (_photoUrls[p.storagePath] != null)
            GestureDetector(
              onTap: () => _openPhoto(_photoUrls[p.storagePath]!, p.caption),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  _photoUrls[p.storagePath]!,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, e, s) => const SizedBox.shrink(),
                ),
              ),
            ),
          if ((p.caption ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              child: Text(p.caption!, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            )
          else
            const SizedBox(height: 12),
        ],
      ],
    );
  }

  Future<void> _openPhoto(String url, String? caption) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: InteractiveViewer(child: Image.network(url))),
            if ((caption ?? '').isNotEmpty)
              Padding(padding: const EdgeInsets.all(12), child: Text(caption!)),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる')),
          ],
        ),
      ),
    );
  }

  // アレルギー除去食の同意(272/273)。給食セクション内の一区画として表示し、詳細/履歴は専用画面へ。
  Widget _consentEntry() {
    final pending = _pendingConsents > 0;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => MealConsentScreen(guardianService: widget.guardianService, child: widget.child),
          ),
        );
        _load();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: pending ? AppColors.warmOrange.withValues(alpha: 0.1) : AppColors.leafGreen.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: pending ? AppColors.warmOrange.withValues(alpha: 0.5) : AppColors.leafGreen.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(pending ? Icons.fact_check_rounded : Icons.check_circle_rounded,
                color: pending ? AppColors.warmOrange : AppColors.leafGreen),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('アレルギー除去食の同意', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    pending ? '同意のお願いがあります。タップして確認・同意してください。' : '同意の記録を確認できます。',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            if (pending)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.warmOrange, borderRadius: BorderRadius.circular(20)),
                child: Text('$_pendingConsents',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
              ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  static const _slotLabels = {'am_snack': '午前おやつ', 'lunch': '昼食', 'pm_snack': '午後おやつ'};
  static const _slotOrder = {'am_snack': 0, 'lunch': 1, 'pm_snack': 2};

  /// 今月の献立(Ohana Works独自の構造化表示)。日ごとに区分をまとめて表示。
  Widget _structuredSection() {
    // 日付ごとにグルーピング
    final byDate = <DateTime, List<({DateTime menuDate, String mealSlot, String menuText, String ingredients})>>{};
    for (final d in _menuDays.where((e) => e.menuText.trim().isNotEmpty)) {
      (byDate[d.menuDate] ??= []).add(d);
    }
    final dates = byDate.keys.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.restaurant_menu_rounded, size: 18, color: AppColors.leafGreen),
            SizedBox(width: 6),
            Text('今月の献立', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 8),
        if (dates.isEmpty)
          const Text('今月の献立はまだ公開されていません', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))
        else
          for (final date in dates) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.leafGreen.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${date.month}/${date.day}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 4),
                  for (final s in (byDate[date]!..sort((a, b) =>
                      (_slotOrder[a.mealSlot] ?? 9).compareTo(_slotOrder[b.mealSlot] ?? 9))))
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 76,
                            child: Text(_slotLabels[s.mealSlot] ?? s.mealSlot,
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.menuText, style: const TextStyle(fontSize: 13, height: 1.3)),
                                // 材料(昼食)。保護者にも掲載(俊指示2026-08-21)。
                                if (s.ingredients.trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text('材料: ${s.ingredients}',
                                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.3)),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
      ],
    );
  }

  // 除去食献立(276・保護者限定)。除去食提供中の児のみ表示。除去/代替内容を強調。
  Widget _allergyMenuSection() {
    final byDate =
        <DateTime, List<({DateTime menuDate, String mealSlot, String menuText, String ingredients, String? removalKind, String? removalNote})>>{};
    for (final d in _allergyMenuDays.where((e) => e.menuText.trim().isNotEmpty)) {
      (byDate[d.menuDate] ??= []).add(d);
    }
    final dates = byDate.keys.toList()..sort();
    if (dates.isEmpty) return const SizedBox.shrink();
    // 除去の種類(卵/そば等)を集約して見出しに出す。
    final kinds = _allergyMenuDays
        .map((e) => e.removalKind)
        .where((k) => k != null && k.trim().isNotEmpty)
        .map((k) => k!)
        .toSet()
        .join('・');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warmOrange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warmOrange.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.no_meals_rounded, size: 18, color: AppColors.warmOrange),
              const SizedBox(width: 6),
              const Text('お子さまの除去食献立', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              if (kinds.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.warmOrange, borderRadius: BorderRadius.circular(20)),
                  child: Text('$kinds 除去',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          const Text('園でお子さま用に用意する除去・代替の献立です。',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          for (final date in dates) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${date.month}/${date.day}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 4),
                  for (final s in (byDate[date]!..sort((a, b) =>
                      (_slotOrder[a.mealSlot] ?? 9).compareTo(_slotOrder[b.mealSlot] ?? 9))))
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 76,
                            child: Text(_slotLabels[s.mealSlot] ?? s.mealSlot,
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.menuText, style: const TextStyle(fontSize: 13, height: 1.3)),
                                if (s.ingredients.trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text('材料: ${s.ingredients}',
                                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.3)),
                                  ),
                                if (s.removalNote != null && s.removalNote!.trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text('除去・代替: ${s.removalNote}',
                                        style: const TextStyle(
                                            fontSize: 11, color: AppColors.warmOrange, fontWeight: FontWeight.w600, height: 1.3)),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _section(String title, List<_MenuItem> items, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppColors.leafGreen),
            const SizedBox(width: 6),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Text('この月の公開はまだありません', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))
        else
          for (final it in items) ...[
            const SizedBox(height: 8),
            if (it.format == 'image' && _signedUrls[it.sourcePath] != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  _signedUrls[it.sourcePath]!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => _fileButton(it),
                ),
              )
            else
              _fileButton(it),
          ],
      ],
    );
  }

  Widget _fileButton(_MenuItem it) => OutlinedButton.icon(
        onPressed: () => _openFile(it),
        icon: Icon(it.format == 'pdf' ? Icons.picture_as_pdf_rounded : Icons.description_rounded, size: 18),
        label: Text(it.sourceFilename ?? '献立ファイル', overflow: TextOverflow.ellipsis),
      );
}
