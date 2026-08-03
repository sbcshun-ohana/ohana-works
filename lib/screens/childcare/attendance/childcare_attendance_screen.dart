import 'package:flutter/material.dart';

import '../../../models/childcare.dart';
import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ohana_logo_home_button.dart';

/// §7 当日の欠席選択。在籍園児一覧から欠席チェックする。
/// 複数端末への即時反映(Realtime)はRLS越しにDB側で配信対象publicationに含まれている。
class ChildcareAttendanceScreen extends StatefulWidget {
  const ChildcareAttendanceScreen({
    super.key,
    required this.service,
    required this.officeId,
    required this.businessDate,
  });

  final ChildcareService service;
  final String officeId;
  final DateTime businessDate;

  @override
  State<ChildcareAttendanceScreen> createState() => _ChildcareAttendanceScreenState();
}

class _ChildcareAttendanceScreenState extends State<ChildcareAttendanceScreen> {
  late Future<List<ChildcareClass>> _classesFuture;
  ChildcareClass? _selectedClass;
  Future<List<ClassChild>>? _childrenFuture;
  final _busyChildIds = <String>{};

  @override
  void initState() {
    super.initState();
    _classesFuture = widget.service.fetchChildcareClasses(widget.officeId);
  }

  void _selectClass(ChildcareClass classItem) {
    setState(() {
      _selectedClass = classItem;
      _childrenFuture = widget.service.fetchClassChildren(classItem.classId, widget.businessDate);
    });
  }

  Future<void> _reload() async {
    if (_selectedClass == null) return;
    setState(() {
      _childrenFuture =
          widget.service.fetchClassChildren(_selectedClass!.classId, widget.businessDate);
    });
    await _childrenFuture;
  }

  Future<void> _toggleAbsence(ClassChild child) async {
    final nextIsAbsent = !child.isAbsent;
    String? reason;
    if (nextIsAbsent) {
      reason = await _promptReason();
      if (reason == null) return; // キャンセル
    }
    setState(() => _busyChildIds.add(child.childId));
    try {
      await widget.service.setChildDailyAttendance(
        childId: child.childId,
        businessDate: widget.businessDate,
        isAbsent: nextIsAbsent,
        absenceReason: reason,
      );
      await _reload();
    } finally {
      if (mounted) setState(() => _busyChildIds.remove(child.childId));
    }
  }

  Future<String?> _promptReason() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('欠席理由(任意)'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('欠席にする'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const OhanaLogoHomeButton(),
        leadingWidth: 180,
        title: const Text('当日の欠席選択'),
      ),
      body: FutureBuilder<List<ChildcareClass>>(
        future: _classesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final classes = snapshot.data ?? const [];
          if (classes.isEmpty) {
            return const Center(child: Text('クラスが登録されていません'));
          }
          _selectedClass ??= classes.first;
          _childrenFuture ??=
              widget.service.fetchClassChildren(_selectedClass!.classId, widget.businessDate);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: DropdownButton<ChildcareClass>(
                  isExpanded: true,
                  value: _selectedClass,
                  items: classes
                      .map((c) => DropdownMenuItem(value: c, child: Text(c.className)))
                      .toList(),
                  onChanged: (c) {
                    if (c != null) _selectClass(c);
                  },
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _reload,
                  child: FutureBuilder<List<ClassChild>>(
                    future: _childrenFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final children = snapshot.data ?? const [];
                      if (children.isEmpty) {
                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 120),
                            Center(child: Text('在籍園児がいません')),
                          ],
                        );
                      }
                      return ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: children.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final child = children[index];
                          final isBusy = _busyChildIds.contains(child.childId);
                          return Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              title: Text(
                                child.nameLabel,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: child.absenceReason != null
                                  ? Text(
                                      '理由: ${child.absenceReason}',
                                      style: const TextStyle(color: AppColors.textSecondary),
                                    )
                                  : null,
                              trailing: isBusy
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2.5),
                                    )
                                  : FilterChip(
                                      label: Text(child.isAbsent ? '欠席' : '出席'),
                                      selected: child.isAbsent,
                                      selectedColor: AppColors.punchClockOut.withValues(alpha: 0.15),
                                      onSelected: (_) => _toggleAbsence(child),
                                    ),
                            ),
                          );
                        },
                      );
                    },
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
