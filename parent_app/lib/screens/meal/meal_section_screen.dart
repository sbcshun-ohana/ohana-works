import 'package:flutter/material.dart';

import '../../models/linked_child.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';

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
    final menus = _items.where((e) => e.kind == 'menu').toList();
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
              _structuredSection(),
              const SizedBox(height: 24),
              _section('献立ファイル(元データ)', menus, Icons.description_rounded),
              const SizedBox(height: 24),
              _section('食育レター', letters, Icons.menu_book_rounded),
            ],
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
