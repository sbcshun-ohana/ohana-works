import 'package:flutter/material.dart';

import '../../../models/childcare.dart';
import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ohana_logo_home_button.dart';
import 'child_detail_screen.dart' show showChildWeeklyScheduleSheet;

/// 週次予定(標準保育時間)の園児一覧。ホームの「週次予定」タイルから直接開く専用画面。
/// 従来はデイリーボード→園児詳細→週次アイコンの遠回り導線だったため、
/// 園児をタップするだけで週次保育時間シートを開けるようにする(俊指示の導線改善)。
class WeeklyScheduleListScreen extends StatefulWidget {
  const WeeklyScheduleListScreen({super.key, required this.service, required this.officeId});

  final ChildcareService service;
  final String officeId;

  @override
  State<WeeklyScheduleListScreen> createState() => _WeeklyScheduleListScreenState();
}

class _WeeklyScheduleListScreenState extends State<WeeklyScheduleListScreen> {
  List<ChildcareClass> _classes = const [];
  String? _selectedClassId;
  bool _loading = true;
  List<({String childId, String nameLabel, String className})> _roster = const [];

  @override
  void initState() {
    super.initState();
    _loadClasses();
    _reload();
  }

  Future<void> _loadClasses() async {
    final c = await widget.service.fetchChildcareClasses(widget.officeId);
    if (mounted) setState(() => _classes = c);
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final children = await widget.service.fetchChildrenForOffice(widget.officeId);
      final roster = children
          .map((c) => (childId: c.childId, nameLabel: '${c.displayName}${c.honorificSuffix ?? ''}', className: c.className ?? ''))
          .toList();
      if (mounted) {
        setState(() {
          _roster = roster;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedClassName = _selectedClassId == null
        ? null
        : _classes
            .firstWhere((c) => c.classId == _selectedClassId,
                orElse: () => const ChildcareClass(classId: '', className: '', ageGroup: '', schoolYear: 0))
            .className;
    final rows = selectedClassName == null ? _roster : _roster.where((r) => r.className == selectedClassName).toList();

    return Scaffold(
      appBar: AppBar(
        leading: const OhanaLogoHomeButton(),
        leadingWidth: 148,
        toolbarHeight: 48,
        titleSpacing: 0,
        title: const Text('週次予定(標準保育時間)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _selectedClassId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'クラス', isDense: true, border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('全クラス')),
                      for (final c in _classes) DropdownMenuItem<String?>(value: c.classId, child: Text(c.className)),
                    ],
                    onChanged: (v) => setState(() => _selectedClassId = v),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('園児をタップすると曜日ごとの標準保育時間を設定できます(設定/削除は主任以上)',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                    ? const Center(child: Text('対象の園児がいません'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, i) {
                          final child = rows[i];
                          return Card(
                            margin: EdgeInsets.zero,
                            child: ListTile(
                              dense: true,
                              leading: const Icon(Icons.event_repeat_rounded, color: AppColors.leafGreen),
                              title: Text(child.nameLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(child.className, style: const TextStyle(fontSize: 12)),
                              trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                              onTap: () => showChildWeeklyScheduleSheet(
                                context,
                                service: widget.service,
                                childId: child.childId,
                                childName: child.nameLabel,
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
