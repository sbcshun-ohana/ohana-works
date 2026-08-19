import 'package:flutter/material.dart';

import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ohana_logo_home_button.dart';
import 'incident_common.dart';
import 'incident_detail_screen.dart';
import 'incident_form_screen.dart';

/// ヒヤリハット・事故報告の一覧(全施設閲覧・作成導線)。
class IncidentListScreen extends StatefulWidget {
  const IncidentListScreen({
    super.key,
    required this.service,
    required this.officeId,
    required this.isManager,
  });

  final ChildcareService service;
  final String officeId;
  final bool isManager;

  @override
  State<IncidentListScreen> createState() => _IncidentListScreenState();
}

class _IncidentListScreenState extends State<IncidentListScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];
  String? _statusFilter;
  String? _typeFilter;

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
      final rows = await widget.service.fetchIncidentReports(
        widget.officeId,
        status: _statusFilter,
        reportType: _typeFilter,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '一覧の取得に失敗しました';
          _loading = false;
        });
      }
    }
  }

  Future<void> _openNew() async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => IncidentFormScreen(service: widget.service, officeId: widget.officeId),
    ));
    if (changed == true) _load();
  }

  Future<void> _openDetail(String id) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => IncidentDetailScreen(
        service: widget.service,
        officeId: widget.officeId,
        reportId: id,
        isManager: widget.isManager,
      ),
    ));
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const OhanaBackHomeLeading(),
        leadingWidth: 200,
        title: const Text('ヒヤリハット・事故報告'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNew,
        icon: const Icon(Icons.add),
        label: const Text('新規作成'),
      ),
      body: Column(
        children: [
          _filters(),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                    : _rows.isEmpty
                        ? const Center(child: Text('報告書はありません', style: TextStyle(color: AppColors.textSecondary)))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: _rows.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 8),
                              itemBuilder: (_, i) => _row(_rows[i]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: _typeFilter,
              isDense: true,
              decoration: const InputDecoration(labelText: '種別', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: null, child: Text('すべて')),
                for (final e in IncidentLabels.reportTypesShort.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) {
                setState(() => _typeFilter = v);
                _load();
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: _statusFilter,
              isDense: true,
              decoration: const InputDecoration(labelText: '状態', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: null, child: Text('すべて')),
                for (final e in IncidentLabels.statuses.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) {
                setState(() => _statusFilter = v);
                _load();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> r) {
    final occurredOn = r['occurred_on'] as String?;
    final occurredAt = r['occurred_at'] as String?;
    final children = (r['child_names'] as String?) ?? '';
    final place = (r['place_label'] as String?) ?? '';
    final closure = r['closure_status'] as String?;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => _openDetail(r['id'] as String),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IncidentTypeBadge(reportType: r['report_type'] as String?, short: true),
                  const SizedBox(width: 8),
                  IncidentStatusBadge(status: r['status'] as String?),
                  const Spacer(),
                  if (closure == 'open')
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Text('未クローズ',
                          style: TextStyle(color: AppColors.punchClockOut, fontWeight: FontWeight.w700, fontSize: 11)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${_fmtDate(occurredOn)}${occurredAt != null ? ' ${_fmtTime(occurredAt)}' : ''}'
                '${place.isNotEmpty ? '  /  $place' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (children.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('園児: $children', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
              const SizedBox(height: 2),
              Text('記入: ${(r['created_by_name'] as String?) ?? '-'}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.year}/${d.month}/${d.day}';
  }

  String _fmtTime(String? t) {
    if (t == null) return '';
    // 'HH:MM:SS' → 'HH:MM'
    final parts = t.split(':');
    return parts.length >= 2 ? '${parts[0]}:${parts[1]}' : t;
  }
}
