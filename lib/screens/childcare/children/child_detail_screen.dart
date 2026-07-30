import 'package:flutter/material.dart';

import '../../../models/guardian_app.dart';
import '../../../services/childcare_service.dart';
import 'child_internal_notes_tab.dart';
import '../family_daily_report_summary_view.dart';

/// 園児詳細画面。「家庭連絡帳」タブは常時表示、「園内記録」タブは
/// 機能フラグ child_internal_notes_enabled がONの施設のみ表示する。
class ChildDetailScreen extends StatefulWidget {
  const ChildDetailScreen({
    super.key,
    required this.service,
    required this.childId,
    required this.childName,
    required this.officeId,
    required this.businessDate,
  });

  final ChildcareService service;
  final String childId;
  final String childName;
  final String officeId;
  final DateTime businessDate;

  @override
  State<ChildDetailScreen> createState() => _ChildDetailScreenState();
}

class _ChildDetailScreenState extends State<ChildDetailScreen> {
  late Future<bool> _internalNotesEnabledFuture;

  @override
  void initState() {
    super.initState();
    _internalNotesEnabledFuture =
        widget.service.isChildInternalNotesEnabledForOffice(widget.officeId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _internalNotesEnabledFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.childName)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final internalNotesEnabled = snapshot.data ?? false;
        final tabs = <Tab>[
          const Tab(text: '家庭連絡帳'),
          if (internalNotesEnabled) const Tab(text: '園内記録'),
        ];
        return DefaultTabController(
          length: tabs.length,
          child: Scaffold(
            appBar: AppBar(
              title: Text(widget.childName),
              bottom: tabs.length > 1 ? TabBar(tabs: tabs) : null,
            ),
            body: TabBarView(
              children: [
                _FamilyDailyReportTab(
                  service: widget.service,
                  childId: widget.childId,
                  businessDate: widget.businessDate,
                ),
                if (internalNotesEnabled)
                  ChildInternalNotesTab(
                    service: widget.service,
                    childId: widget.childId,
                    officeId: widget.officeId,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FamilyDailyReportTab extends StatefulWidget {
  const _FamilyDailyReportTab({
    required this.service,
    required this.childId,
    required this.businessDate,
  });

  final ChildcareService service;
  final String childId;
  final DateTime businessDate;

  @override
  State<_FamilyDailyReportTab> createState() => _FamilyDailyReportTabState();
}

class _FamilyDailyReportTabState extends State<_FamilyDailyReportTab> {
  late Future<FamilyDailyReportSummary?> _reportFuture;

  @override
  void initState() {
    super.initState();
    _reportFuture =
        widget.service.fetchFamilyDailyReportForStaff(widget.childId, widget.businessDate);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FamilyDailyReportSummary?>(
      future: _reportFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: FamilyDailyReportSummaryView(report: snapshot.data),
        );
      },
    );
  }
}
