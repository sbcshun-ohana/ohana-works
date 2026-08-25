import 'package:flutter/material.dart';

import '../models/guardian_qr_resolution.dart';
import '../services/guardian_qr_service.dart';

// 保育園らしい明るく可愛らしい配色(俊指示 2026-08-25)。
const _kSky = Color(0xFF5EC6E8); // やさしい空色(ブランド)
const _kGreen = Color(0xFF74C365); // 新緑
const _kOrange = Color(0xFFF6A623); // 夕焼けオレンジ(降園)
const _kInk = Color(0xFF4A4A4A); // やわらかい文字色
// 明るい背景グラデーション(クリーム→水色)。
const _kBgGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFFFFF6E9), Color(0xFFE1F4FF)],
);
// 園児アバターのパステル色(child_idで安定して割当)。
const _kAvatarColors = <Color>[
  Color(0xFFFFD8A8),
  Color(0xFFBFE3C0),
  Color(0xFFAEDFF7),
  Color(0xFFF7C6D9),
  Color(0xFFD6C8F0),
  Color(0xFFFDE9A8),
];

/// 兄弟一括登降園の確認画面(234・俊確定 2026-08-18)。
/// スキャンで返った候補を表示し、登園/降園する園児を選んで確定する(半自動)。
/// 欠席連絡がある子は既定OFF・注記付きだが選択可能(登園時は当日欠席が自動解除される)。
class FamilyCheckinScreen extends StatefulWidget {
  const FamilyCheckinScreen({
    super.key,
    required this.resolution,
    required this.service,
  });

  final GuardianQrResolution resolution;
  final GuardianQrService service;

  @override
  State<FamilyCheckinScreen> createState() => _FamilyCheckinScreenState();
}

class _FamilyCheckinScreenState extends State<FamilyCheckinScreen> {
  late final Map<String, bool> _selected;
  bool _isSubmitting = false;
  String? _errorMessage;
  List<Map<String, dynamic>>? _results;

  bool get _isArrival => widget.resolution.direction == 'arrival';

  @override
  void initState() {
    super.initState();
    _selected = {
      for (final c in widget.resolution.candidates) c.childId: c.defaultSelected,
    };
  }

  Future<void> _submit() async {
    final action = _isArrival ? 'checkin' : 'checkout';
    final selections = _selected.entries
        .where((e) => e.value)
        .map((e) => {'child_id': e.key, 'action': action})
        .toList();
    if (selections.isEmpty) {
      setState(() => _errorMessage = '登降園するお子様を選んでください');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final results = await widget.service.applyFamilyCheckin(
        sessionId: widget.resolution.sessionId!,
        selections: selections,
      );
      if (mounted) setState(() => _results = results);
    } on GuardianQrException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_results != null) return _buildResult();
    final title = _isArrival ? 'ご登園' : 'ご降園';
    final accent = _isArrival ? _kGreen : _kOrange;
    return _brightScaffold(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 30, offset: const Offset(0, 12)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('🌸 $titleのお子さまをえらんでね',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: _kInk)),
                const SizedBox(height: 8),
                Text(_isArrival ? '一緒に登園するお子さまをタップしてね' : 'お迎えするお子さまをタップしてね',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                const SizedBox(height: 22),
                // 縦一列の羅列ではなく2列のボタン状グリッド(タッチで押しやすく・兄弟を見分けやすい)。
                LayoutBuilder(
                  builder: (context, constraints) {
                    const gap = 16.0;
                    final tileWidth = (constraints.maxWidth - gap) / 2;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: widget.resolution.candidates
                          .map((c) => SizedBox(width: tileWidth, child: _buildCandidateTile(c)))
                          .toList(),
                    );
                  },
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Text(_errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFE86A5E), fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 26),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey.shade600,
                          side: BorderSide(color: Colors.grey.shade300, width: 2),
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        child: const Text('キャンセル', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          elevation: 3,
                        ),
                        child: _isSubmitting
                            ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(_isArrival ? '登園する 🌱' : '降園する 👋', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 明るいグラデーション背景の共通スキャフォールド。
  Widget _brightScaffold({required Widget child}) => Scaffold(
        backgroundColor: const Color(0xFFEAF6FF),
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: _kBgGradient),
          child: SafeArea(child: Center(child: child)),
        ),
      );

  Widget _buildCandidateTile(FamilyCheckinCandidate c) {
    // 選択できないケース(登園フェーズで既に在園中/降園済み、降園フェーズで未登園)は無効化。
    final disabled = _isArrival
        ? (c.todayStatus == 'present' || c.todayStatus == 'picked_up')
        : (c.todayStatus != 'present');
    final selected = !disabled && (_selected[c.childId] ?? false);
    final avatarColor = _kAvatarColors[c.childId.hashCode.abs() % _kAvatarColors.length];
    final firstChar = c.childName.characters.isNotEmpty ? c.childName.characters.first : '?';
    // 2列のボタン状カード。園児ごとにパステルのまるいアバター(頭文字)+選択時はにっこりチェックバッジ。
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: disabled ? null : () => setState(() => _selected[c.childId] = !selected),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
          decoration: BoxDecoration(
            color: disabled ? const Color(0xFFF3F4F6) : (selected ? const Color(0xFFEAF7FF) : Colors.white),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: disabled ? const Color(0xFFE3E6EA) : (selected ? _kSky : const Color(0xFFE7EDF2)),
              width: selected ? 3 : 2,
            ),
            boxShadow: disabled
                ? null
                : [
                    BoxShadow(
                      color: (selected ? _kSky : Colors.black).withValues(alpha: selected ? 0.20 : 0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // まるいアバター(頭文字)+選択時ににっこりチェックバッジ
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: disabled ? Colors.grey.shade300 : avatarColor,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(firstChar,
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: disabled ? Colors.grey.shade600 : const Color(0xFF5B5B5B))),
                  ),
                  if (selected)
                    Positioned(
                      right: -3,
                      bottom: -3,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: _kGreen,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${c.childName}${c.className != null ? '\n(${c.className})' : ''}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                  color: disabled ? Colors.grey : _kInk,
                ),
              ),
              if (c.note != null) ...[
                const SizedBox(height: 6),
                Text(
                  c.note!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: c.isAbsentToday ? Colors.orange.shade800 : Colors.grey.shade600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResult() {
    final done = _results!.where((r) => r['result'] == 'checked_in' || r['result'] == 'checked_out').toList();
    final blocked = _results!.where((r) => r['result'] == 'blocked').toList();
    final ok = blocked.isEmpty;
    return _brightScaffold(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(36),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 30, offset: const Offset(0, 12)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // にっこりチェック(丸背景)
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: (ok ? _kGreen : _kOrange).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(ok ? Icons.check_circle_rounded : Icons.info_rounded, size: 64, color: ok ? _kGreen : _kOrange),
                ),
                const SizedBox(height: 18),
                Text('${done.length}名を${_isArrival ? '登園' : '降園'}しました 🎉',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _kInk)),
                if (blocked.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  for (final b in blocked)
                    Text('受付できなかったお子様: ${b['reason'] ?? ''}',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, color: Colors.orange.shade800, fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 30),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: _kSky,
                    padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 3,
                  ),
                  child: const Text('とじる', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
