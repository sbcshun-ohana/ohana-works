import 'package:flutter/material.dart';

import '../../models/childcare.dart';
import '../../services/childcare_service.dart';
import '../../theme/app_theme.dart';
import 'attendance/childcare_attendance_screen.dart';
import 'class_activities/class_activity_list_screen.dart';
import 'contacts/contact_copy_screen.dart';
import 'contacts/daily_contact_list_screen.dart';

/// 保育業務メニュー。施設・対象日を選び、各画面へ遷移する。
/// 機能フラグが有効な施設が1つも無い場合はhome_screen側で本画面自体への導線を出さない。
class ChildcareMenuScreen extends StatefulWidget {
  const ChildcareMenuScreen({super.key, required this.service});

  final ChildcareService service;

  @override
  State<ChildcareMenuScreen> createState() => _ChildcareMenuScreenState();
}

class _ChildcareMenuScreenState extends State<ChildcareMenuScreen> {
  late Future<List<ChildcareOffice>> _officesFuture;
  ChildcareOffice? _selectedOffice;
  DateTime _businessDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _officesFuture = widget.service.fetchMyChildcareOffices();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _businessDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) setState(() => _businessDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('保育業務')),
      body: FutureBuilder<List<ChildcareOffice>>(
        future: _officesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final offices = snapshot.data ?? const [];
          if (offices.isEmpty) {
            return const Center(child: Text('保育業務機能が有効な施設がありません'));
          }
          _selectedOffice ??= offices.first;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('施設', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      DropdownButton<ChildcareOffice>(
                        isExpanded: true,
                        value: _selectedOffice,
                        items: offices
                            .map(
                              (office) => DropdownMenuItem(
                                value: office,
                                child: Text(office.officeName),
                              ),
                            )
                            .toList(),
                        onChanged: (office) => setState(() => _selectedOffice = office),
                      ),
                      const SizedBox(height: 16),
                      const Text('対象日', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_today_rounded),
                        label: Text(
                          '${_businessDate.year}/${_businessDate.month}/${_businessDate.day}',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _ChildcareMenuCard(
                icon: Icons.event_busy_rounded,
                color: AppColors.warmOrange,
                title: '当日の欠席選択',
                subtitle: '在籍園児から欠席をチェックします',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChildcareAttendanceScreen(
                      service: widget.service,
                      officeId: _selectedOffice!.officeId,
                      businessDate: _businessDate,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _ChildcareMenuCard(
                icon: Icons.groups_rounded,
                color: AppColors.leafGreen,
                title: 'クラス活動 入力・申請・承認',
                subtitle: '今日の活動を入力し、申請・承認します',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ClassActivityListScreen(
                      service: widget.service,
                      officeId: _selectedOffice!.officeId,
                      businessDate: _businessDate,
                      isManager: _selectedOffice!.isManager,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _ChildcareMenuCard(
                icon: Icons.chat_bubble_outline_rounded,
                color: AppColors.skyBlue,
                title: '連絡帳 入力・AI生成・承認',
                subtitle: '園児ごとの連絡帳を作成し、申請・承認します',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DailyContactListScreen(
                      service: widget.service,
                      officeId: _selectedOffice!.officeId,
                      businessDate: _businessDate,
                      isManager: _selectedOffice!.isManager,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _ChildcareMenuCard(
                icon: Icons.copy_all_rounded,
                color: AppColors.skyBlue,
                title: '承認済み連絡帳のコピー',
                subtitle: 'コピー先(コドモン等)へ貼り付けます',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ContactCopyScreen(
                      service: widget.service,
                      officeId: _selectedOffice!.officeId,
                      businessDate: _businessDate,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ChildcareMenuCard extends StatelessWidget {
  const _ChildcareMenuCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
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
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
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
