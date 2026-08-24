import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';

/// 給食写真(300・§8)。厨房iPadで撮影→承認待ち→管理者以上が承認で保護者「給食」に公開。
/// 施設×日付の「本日の給食」。撮影・送信・自分の未公開分の削除は職員、承認/差し戻しは管理者以上。
class MealPhotoScreen extends StatefulWidget {
  const MealPhotoScreen({
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
  State<MealPhotoScreen> createState() => _MealPhotoScreenState();
}

class _MealPhotoScreenState extends State<MealPhotoScreen> {
  List<Map<String, dynamic>> _photos = const [];
  final Map<String, String> _urls = {}; // storage_path -> signed url
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await widget.service.fetchMealPhotosForOffice(widget.officeId, widget.businessDate);
      for (final p in rows) {
        final path = p['storage_path'] as String;
        if (!_urls.containsKey(path)) {
          try {
            _urls[path] = await widget.service.mealPhotoSignedUrl(path);
          } catch (_) {}
        }
      }
      if (!mounted) return;
      setState(() {
        _photos = rows;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _capture() async {
    try {
      final picker = ImagePicker();
      final shot = await picker.pickImage(source: ImageSource.camera, maxWidth: 2000, imageQuality: 85);
      if (shot == null) return;
      final bytes = await shot.readAsBytes();
      if (!mounted) return;
      final caption = await _previewAndCaption(bytes);
      // bytes は Uint8List(XFile.readAsBytes)
      if (caption == null) return; // 撮り直し/キャンセル
      setState(() => _busy = true);
      await widget.service.submitMealPhoto(widget.officeId, widget.businessDate, bytes, caption: caption.isEmpty ? null : caption);
      if (mounted) _snack('送信しました(承認待ち)');
      await _load();
    } catch (e) {
      _snack('送信できません: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// プレビュー→キャプション入力。戻り値=キャプション(空可)、nullなら撮り直し/キャンセル。
  Future<String?> _previewAndCaption(Uint8List bytes) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('この写真を送信しますか?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  labelText: '一言メモ(任意・例: 今日の昼食)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLength: 60,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('撮り直し')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('送信')),
        ],
      ),
    );
  }

  Future<void> _run(Future<void> Function() fn, String ok) async {
    setState(() => _busy = true);
    try {
      await fn();
      if (mounted) _snack(ok);
      await _load();
    } catch (e) {
      _snack('操作できません: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.businessDate;
    return Scaffold(
      appBar: AppBar(title: Text('給食写真  ${d.month}/${d.day}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _capture,
        icon: const Icon(Icons.photo_camera_rounded),
        label: const Text('撮影して送信'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _photos.isEmpty
              ? const Center(child: Text('本日の給食写真はまだありません。右下から撮影してください。', style: TextStyle(color: AppColors.textSecondary)))
              : GridView.count(
                  padding: const EdgeInsets.all(16),
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                  children: _photos.map(_photoCard).toList(),
                ),
    );
  }

  Widget _photoCard(Map<String, dynamic> p) {
    final status = p['status'] as String? ?? 'pending';
    final url = _urls[p['storage_path']];
    final (badgeColor, badgeText) = switch (status) {
      'published' => (AppColors.leafGreen, '公開中'),
      'rejected' => (AppColors.punchClockOut, '差し戻し'),
      _ => (AppColors.warmOrange, '承認待ち'),
    };
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE3E0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (url != null)
                  Image.network(url, fit: BoxFit.cover, errorBuilder: (_, e, s) => const ColoredBox(color: Color(0xFFEEEEEE)))
                else
                  const ColoredBox(color: Color(0xFFEEEEEE), child: Center(child: Icon(Icons.image, color: Colors.grey))),
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(8)),
                    child: Text(badgeText, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((p['caption'] as String?)?.isNotEmpty ?? false)
                  Text(p['caption'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                if (status == 'rejected' && ((p['rejected_reason'] as String?)?.isNotEmpty ?? false))
                  Text('理由: ${p['rejected_reason']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.punchClockOut)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (widget.isManager && status != 'published')
                      _miniBtn('承認', AppColors.leafGreen, () => _run(() => widget.service.approveMealPhoto(p['id'] as String), '公開しました')),
                    if (widget.isManager && status == 'pending')
                      _miniBtn('却下', AppColors.warmOrange, () => _reject(p['id'] as String)),
                    const Spacer(),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.textSecondary),
                      onPressed: _busy ? null : () => _confirmDelete(p['id'] as String),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniBtn(String label, Color color, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          onTap: _busy ? null : onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
            child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ),
        ),
      );

  Future<void> _reject(String id) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('差し戻し理由(必須)'),
        content: TextField(controller: ctrl, autofocus: true, maxLines: 2),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('差し戻す')),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    _run(() => widget.service.rejectMealPhoto(id, reason), '差し戻しました');
  }

  Future<void> _confirmDelete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('この写真を削除しますか?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('削除')),
        ],
      ),
    );
    if (ok == true) _run(() => widget.service.deleteMealPhoto(id), '削除しました');
  }
}
