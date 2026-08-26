import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import 'kitchen_screen.dart';
import 'meal_photo_screen.dart';
import 'meal_monthly_summary_screen.dart';
import 'meal_slot_cross_screen.dart';
import 'meal_kitchen_board_screen.dart';
import 'meal_conference_view_screen.dart';

/// 厨房専用ホーム(304)。厨房アカウント(is_kitchen_only)でログインした時の初期画面。
/// 一般職員の7区分ホームは出さず、給食関連の入口だけを表示する。対象施設=施設割当。
class KitchenHomeScreen extends StatefulWidget {
  const KitchenHomeScreen({super.key, required this.service});
  final ChildcareService service;

  @override
  State<KitchenHomeScreen> createState() => _KitchenHomeScreenState();
}

class _KitchenHomeScreenState extends State<KitchenHomeScreen> {
  List<Map<String, dynamic>> _offices = const [];
  String? _officeId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final offices = await widget.service.fetchMyKitchenOffices();
      if (!mounted) return;
      setState(() {
        _offices = offices;
        _officeId = offices.isNotEmpty ? offices.first['office_id'] as String : null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _officeName =>
      _offices.firstWhere((o) => o['office_id'] == _officeId, orElse: () => const {'office_name': ''})['office_name'] as String? ?? '';

  void _push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: const Text('厨房(給食管理)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'ログアウト',
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _offices.isEmpty
              ? const Center(child: Text('給食管理が有効な担当施設がありません', style: TextStyle(color: AppColors.textSecondary)))
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 施設切替(委託=複数施設)。単一施設のときはラベルのみ。
                      if (_offices.length > 1)
                        Row(
                          children: [
                            const Text('施設: ', style: TextStyle(fontWeight: FontWeight.w700)),
                            DropdownButton<String>(
                              value: _officeId,
                              items: [
                                for (final o in _offices)
                                  DropdownMenuItem(value: o['office_id'] as String, child: Text(o['office_name'] as String)),
                              ],
                              onChanged: (v) => setState(() => _officeId = v),
                            ),
                          ],
                        )
                      else
                        Text('施設: $_officeName', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 16),
                      // 6機能をスクロールなしで1画面に収める(3列×2行・iPad固定)。
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: _tile(Icons.dashboard_rounded, AppColors.warmOrange, '厨房ボード(区分別・全施設)',
                                      () => _push(MealKitchenBoardScreen(service: widget.service, offices: _offices)))),
                                  const SizedBox(width: 16),
                                  Expanded(child: _tile(Icons.restaurant_rounded, AppColors.warmOrange, '食数ボード(厨房)',
                                      () => _push(KitchenScreen(service: widget.service, officeId: _officeId!, businessDate: today)))),
                                  const SizedBox(width: 16),
                                  Expanded(child: _tile(Icons.photo_camera_rounded, AppColors.leafGreen, '給食写真',
                                      () => _push(MealPhotoScreen(service: widget.service, officeId: _officeId!, businessDate: today, isManager: false)))),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: _tile(Icons.calendar_month_rounded, AppColors.skyBlue, '月別集計',
                                      () => _push(MealMonthlySummaryScreen(service: widget.service, offices: _offices, initialOfficeId: _officeId!)))),
                                  const SizedBox(width: 16),
                                  Expanded(child: _tile(Icons.view_list_rounded, AppColors.skyBlue, '食事区分ごと(全施設)',
                                      () => _push(MealSlotCrossScreen(service: widget.service, offices: _offices)))),
                                  const SizedBox(width: 16),
                                  Expanded(child: _tile(Icons.groups_rounded, AppColors.punchClockOut, '給食会議(閲覧)',
                                      () => _push(MealConferenceViewScreen(service: widget.service, officeId: _officeId!, officeName: _officeName)))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _tile(IconData icon, Color color, String label, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 0.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(18)),
              child: Icon(icon, color: color, size: 34),
            ),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}
