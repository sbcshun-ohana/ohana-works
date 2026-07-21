import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/my_data_service.dart';
import '../theme/app_theme.dart';
import 'notices/notice_list_screen.dart';
import 'qr_attendance_screen.dart';
import 'requests/my_attendance_screen.dart';
import 'requests/my_payslip_list_screen.dart';
import 'requests/my_shift_screen.dart';
import 'requests/request_menu_screen.dart';

/// ログイン後に表示する仮のホーム画面。
/// 職員個人のスマートフォン向け(QR勤怠表示・お知らせ・各種申請)。保育業務は会社iPad専用の
/// 別アプリ(--dart-define=APP_MODE=childcare)で扱うため、ここには含めない。
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('ホーム'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'ログアウト',
            onPressed: _signOut,
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: AppColors.warmOrange,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.waving_hand_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'ようこそ！',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    email,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const QrAttendanceScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: const Text('勤怠QRを表示'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const NoticeListScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.notifications_outlined),
                    label: const Text('お知らせ'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const RequestMenuScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.assignment_outlined),
                    label: const Text('各種申請'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MyAttendanceScreen(service: MyDataService(Supabase.instance.client)),
                        ),
                      );
                    },
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: const Text('自分の勤怠'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MyPayslipListScreen(service: MyDataService(Supabase.instance.client)),
                        ),
                      );
                    },
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('給与明細'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MyShiftScreen(service: MyDataService(Supabase.instance.client)),
                        ),
                      );
                    },
                    icon: const Icon(Icons.event_note_outlined),
                    label: const Text('自分のシフト'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
