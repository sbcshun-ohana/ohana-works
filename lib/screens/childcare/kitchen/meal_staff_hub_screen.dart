import 'package:flutter/material.dart';

import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import 'meal_board_screen.dart';
import 'meal_menu_view_screen.dart';

/// 給食管理ハブ(一般職員/担任用)。食数ボード(自クラス承認・変更)と献立(閲覧)への入口。
/// 給食写真・給食会議・月次・全施設横断は厨房/adminのみ(俊指示 2026-08-26)。
class MealStaffHubScreen extends StatelessWidget {
  const MealStaffHubScreen({
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

  void _push(BuildContext context, Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('給食管理')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.5,
          children: [
            _tile(context, Icons.restaurant_rounded, AppColors.warmOrange, '給食発注数',
                () => _push(context, MealBoardScreen(service: service, officeId: officeId, businessDate: businessDate, isManager: isManager))),
            _tile(context, Icons.menu_book_rounded, AppColors.leafGreen, '献立(今日・月間)',
                () => _push(context, MealMenuViewScreen(service: service, officeId: officeId, businessDate: businessDate))),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, IconData icon, Color color, String label, VoidCallback onTap) {
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
