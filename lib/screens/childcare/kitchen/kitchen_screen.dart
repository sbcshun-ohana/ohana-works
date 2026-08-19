import 'package:flutter/material.dart';

import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/business_date_action.dart';
import '../../../widgets/ohana_logo_home_button.dart';

/// 厨房ページ(M6 Phase 7・本案§4.4)。給食情報のみを表示し、他の保育業務情報へは遷移しない。
/// 当日の区分別食数(給食提供数=通常食+共通除去食)・職員食数・共通除去食/弁当持参の対象児を表示。
class KitchenScreen extends StatefulWidget {
  const KitchenScreen({
    super.key,
    required this.service,
    required this.officeId,
    required this.businessDate,
  });

  final ChildcareService service;
  final String officeId;
  final DateTime businessDate;

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  late DateTime _date = widget.businessDate;
  bool _loading = true;
  String? _error;
  ({int normal, int elimination, int bento, int hold, int pre, int provided, int staff})? _count;
  List<({String childId, String childName, String? className, String? handling, List<String> targets})> _special =
      const [];

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
      final count = await widget.service.fetchMealCountForOffice(widget.officeId, _date);
      final special = await widget.service.fetchDailyEliminationForOffice(widget.officeId, _date);
      if (!mounted) return;
      setState(() {
        _count = count;
        _special = special;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '食数情報の取得に失敗しました';
          _loading = false;
        });
      }
    }
  }

  void _onDateChanged(DateTime d) {
    setState(() => _date = d);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const OhanaBackHomeLeading(),
        leadingWidth: 200,
        title: const Text('厨房(食数)'),
        actions: [BusinessDateAction(date: _date, onChanged: _onDateChanged)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    final c = _count!;
    final elimination = _special.where((s) => s.handling == 'elimination').toList();
    final bento = _special.where((s) => s.handling == 'bento').toList();
    final hold = _special.where((s) => s.handling == 'hold').toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 給食提供数(大きく) + 職員食数
        Row(
          children: [
            Expanded(child: _bigCount('給食提供数', c.provided, AppColors.leafGreen, sub: '通常${c.normal}・除去${c.elimination}')),
            const SizedBox(width: 12),
            Expanded(child: _bigCount('職員食数', c.staff, AppColors.skyBlue)),
          ],
        ),
        const SizedBox(height: 12),
        // 区分別の内訳
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _miniCount('通常食', c.normal),
            _miniCount('共通除去食', c.elimination),
            _miniCount('弁当持参', c.bento),
            _miniCount('給食開始保留', c.hold),
            _miniCount('給食提供前', c.pre),
          ],
        ),
        const SizedBox(height: 20),

        // 共通除去食の対象児(誤配膳防止・除去アレルゲンを大きく)
        _sectionTitle('共通除去食の対象児', AppColors.warmOrange, elimination.length),
        if (elimination.isEmpty)
          _emptyLine('対象児はいません')
        else
          ...elimination.map((s) => Card(
                color: AppColors.warmOrange.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${s.childName}${s.className != null ? '  (${s.className})' : ''}',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            const SizedBox(height: 4),
                            const Text('除去', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          for (final t in s.targets)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.punchClockOut,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(t,
                                  style: const TextStyle(
                                      color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              )),
        const SizedBox(height: 16),

        // 弁当持参
        _sectionTitle('弁当持参', AppColors.textSecondary, bento.length),
        if (bento.isEmpty)
          _emptyLine('対象児はいません')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in bento)
                Chip(label: Text('${s.childName}${s.className != null ? '(${s.className})' : ''}')),
            ],
          ),
        const SizedBox(height: 16),

        // 給食開始保留
        _sectionTitle('給食開始保留', AppColors.punchClockOut, hold.length),
        if (hold.isEmpty)
          _emptyLine('対象児はいません')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in hold)
                Chip(label: Text('${s.childName}${s.className != null ? '(${s.className})' : ''}')),
            ],
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _bigCount(String label, int n, Color color, {String? sub}) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          child: Column(
            children: [
              Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              Text('$n', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: color)),
              if (sub != null) ...[
                const SizedBox(height: 2),
                Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ],
          ),
        ),
      );

  Widget _miniCount(String label, int n) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(width: 10),
            Text('$n名', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  Widget _sectionTitle(String title, Color color, int count) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color)),
            const SizedBox(width: 8),
            Text('$count名', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      );

  Widget _emptyLine(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      );
}
