import 'package:flutter/material.dart';

import '../../../models/childcare.dart';
import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/business_date_action.dart';
import '../../../widgets/ohana_logo_home_button.dart';
import '../children/child_internal_notes_tab.dart';
import 'child_day_health_nap_views.dart';
import 'daily_contact_detail_screen.dart';

/// §10-13 連絡帳一覧(施設内の在籍園児の当日分)。
class DailyContactListScreen extends StatefulWidget {
  const DailyContactListScreen({
    super.key,
    required this.service,
    required this.officeId,
    required this.businessDate,
    required this.isManager,
    this.initialTab,
  });

  final ChildcareService service;
  final String officeId;
  final DateTime businessDate;
  final bool isManager;

  /// 右パネルの初期タブ('internal'=園内記録)。null=連絡帳(既定)。園内記録タブは施設フラグON時のみ。
  final String? initialTab;

  @override
  State<DailyContactListScreen> createState() => _DailyContactListScreenState();
}

class _DailyContactListScreenState extends State<DailyContactListScreen> {
  late DateTime _businessDate = widget.businessDate;
  late Future<List<DailyContact>> _contactsFuture;
  // クラス絞り込み(俊指示 2026-08-13)。null=全クラス。
  List<ChildcareClass> _classes = const [];
  String? _selectedClassId;
  // 分割ビュー(iPad幅)で右パネルに表示中の園児。
  DailyContact? _selectedContact;
  // 園内記録タブ(145)。ON施設のみ右パネルのタブに追加する(俊指示 2026-08-27)。
  bool _internalNotesEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadClasses();
    _loadInternalNotesFlag();
  }

  Future<void> _loadClasses() async {
    final c = await widget.service.fetchChildcareClasses(widget.officeId);
    if (mounted) setState(() => _classes = c);
  }

  Future<void> _loadInternalNotesFlag() async {
    try {
      final enabled = await widget.service.isChildInternalNotesEnabledForOffice(widget.officeId);
      if (mounted) setState(() => _internalNotesEnabled = enabled);
    } catch (_) {
      if (mounted) setState(() => _internalNotesEnabled = false);
    }
  }

  void _load() {
    _contactsFuture = widget.service.fetchDailyContactsForOffice(widget.officeId, _businessDate);
  }

  Future<void> _reload() async {
    setState(_load);
    await _contactsFuture;
  }

  void _onDateChanged(DateTime d) {
    setState(() {
      _businessDate = d;
      _load();
    });
  }

  /// クラス名から年齢('0歳'..'5歳')を引く(連絡帳の午前おやつ/ミルクの出し分け用)。
  String? _ageGroupFor(String? className) {
    if (className == null) return null;
    for (final k in _classes) {
      if (k.className == className) return k.ageGroup;
    }
    return null;
  }

  List<DailyContact> _filter(List<DailyContact> all) {
    final selectedClassName = _selectedClassId == null
        ? null
        : _classes
            .firstWhere((c) => c.classId == _selectedClassId,
                orElse: () => const ChildcareClass(classId: '', className: '', ageGroup: '', schoolYear: 0))
            .className;
    return selectedClassName == null ? all : all.where((c) => c.className == selectedClassName).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const OhanaLogoHomeButton(),
        leadingWidth: 148,
        toolbarHeight: 48,
        title: const Text('連絡帳'),
        actions: [BusinessDateAction(date: _businessDate, onChanged: _onDateChanged)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                SizedBox(
                  width: 200,
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
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<DailyContact>>(
              future: _contactsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final contacts = _filter(snapshot.data ?? const []);
                return LayoutBuilder(
                  builder: (context, constraints) {
                    // iPad幅: 左=園児一覧+右=選択児のタブ(連絡帳/午睡/健康)。狭い画面は一覧→遷移。
                    final split = constraints.maxWidth >= 800;
                    if (!split) {
                      return RefreshIndicator(onRefresh: _reload, child: _contactList(contacts, split: false));
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 340,
                          child: RefreshIndicator(onRefresh: _reload, child: _contactList(contacts, split: true)),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: _detailPanel()),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactList(List<DailyContact> contacts, {required bool split}) {
    if (contacts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [SizedBox(height: 120), Center(child: Text('対象の園児がいません'))],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(split ? 10 : 16),
      itemCount: contacts.length,
      separatorBuilder: (_, _) => SizedBox(height: split ? 6 : 12),
      itemBuilder: (context, index) {
        final contact = contacts[index];
        final selected = split && _selectedContact?.childId == contact.childId;
        return Card(
          margin: EdgeInsets.zero,
          color: selected ? AppColors.leafGreen.withValues(alpha: 0.10) : null,
          child: Opacity(
            opacity: contact.isAbsent ? 0.5 : 1,
            child: ListTile(
              selected: selected,
              contentPadding: EdgeInsets.all(split ? 12 : 16),
              title: Text(
                '${contact.nameLabel}${contact.isAbsent ? "(欠席)" : ""}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${contact.className ?? ""} ・ 担当: ${contact.assigneeName ?? "未割当"}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              trailing: _StatusChip(status: contact.status),
              onTap: () async {
                if (split) {
                  setState(() => _selectedContact = contact);
                } else if (widget.initialTab == 'internal' && _internalNotesEnabled) {
                  // 狭幅(非split)はタブが無いため、園内記録モードでは専用画面へ(俊指示の入口を狭幅でも成立させる)。
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChildInternalNotesScreen(
                        service: widget.service,
                        officeId: widget.officeId,
                        childId: contact.childId,
                        childNameLabel: contact.nameLabel,
                      ),
                    ),
                  );
                  await _reload();
                } else {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DailyContactDetailScreen(
                        service: widget.service,
                        officeId: widget.officeId,
                        childId: contact.childId,
                        childNameLabel: contact.nameLabel,
                        businessDate: _businessDate,
                        isManager: widget.isManager,
                        ageGroup: _ageGroupFor(contact.className),
                      ),
                    ),
                  );
                  await _reload();
                }
              },
            ),
          ),
        );
      },
    );
  }

  Widget _detailPanel() {
    final c = _selectedContact;
    if (c == null) {
      return const Center(
        child: Text('左の一覧から園児を選択してください', style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    // フラグ変化でタブ数が変わるため childKey に含めて再構築する。
    final childKey = ValueKey('${c.childId}_${_businessDate.toIso8601String()}_$_internalNotesEnabled');
    final tabs = <Tab>[
      const Tab(text: '連絡帳'), const Tab(text: '午睡'), const Tab(text: '健康'), const Tab(text: '食事'),
      if (_internalNotesEnabled) const Tab(text: '園内記録'),
    ];
    // ホーム/導線から initialTab='internal' で来たら園内記録タブを初期選択(フラグON時のみ)。
    final initialIndex = (widget.initialTab == 'internal' && _internalNotesEnabled) ? tabs.length - 1 : 0;
    return DefaultTabController(
      key: childKey,
      length: tabs.length,
      initialIndex: initialIndex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text('${c.nameLabel}${c.isAbsent ? "(欠席)" : ""}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ),
          TabBar(tabs: tabs),
          Expanded(
            child: TabBarView(
              children: [
                DailyContactDetailScreen(
                  service: widget.service,
                  officeId: widget.officeId,
                  childId: c.childId,
                  childNameLabel: c.nameLabel,
                  businessDate: _businessDate,
                  isManager: widget.isManager,
                  embedded: true,
                  ageGroup: _ageGroupFor(c.className),
                  // 作成・保存・申請・承認で一覧チップ(未着手/下書き等)を最新化。
                  onChanged: () {
                    if (mounted) setState(_load);
                  },
                ),
                ChildDayNapView(
                  service: widget.service,
                  officeId: widget.officeId,
                  childId: c.childId,
                  businessDate: _businessDate,
                ),
                ChildDayHealthView(
                  service: widget.service,
                  officeId: widget.officeId,
                  childId: c.childId,
                  businessDate: _businessDate,
                  ageGroup: _ageGroupFor(c.className),
                ),
                ChildDayMealView(
                  service: widget.service,
                  officeId: widget.officeId,
                  childId: c.childId,
                  businessDate: _businessDate,
                  ageGroup: _ageGroupFor(c.className),
                ),
                // 園内記録(職員専用・園児別の走り書き履歴)。ON施設のみ。連絡帳のタブに集約(俊指示 2026-08-27)。
                if (_internalNotesEnabled)
                  ChildInternalNotesTab(
                    service: widget.service,
                    childId: c.childId,
                    officeId: widget.officeId,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String? status;

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (status) {
      case 'approved':
        color = AppColors.leafGreen;
      case 'rejected':
        color = AppColors.punchClockOut;
      case 'submitted':
        color = AppColors.skyBlue;
      default:
        color = AppColors.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
      child: Text(
        childcareStatusLabel(status),
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

/// 園内記録の単独画面(園児1名)。連絡帳一覧の狭幅モードと、デイリーボードの
/// 行アクション「園内記録」(俊指示 2026-08-28)から使う共有画面。
class ChildInternalNotesScreen extends StatelessWidget {
  const ChildInternalNotesScreen({
    super.key,
    required this.service,
    required this.officeId,
    required this.childId,
    required this.childNameLabel,
  });

  final ChildcareService service;
  final String officeId;
  final String childId;
  final String childNameLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$childNameLabel の園内記録')),
      body: ChildInternalNotesTab(service: service, childId: childId, officeId: officeId),
    );
  }
}
