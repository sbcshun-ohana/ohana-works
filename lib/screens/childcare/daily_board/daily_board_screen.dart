import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/childcare.dart';
import '../../../models/guardian_app.dart';
import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ohana_logo_home_button.dart';
import '../children/child_detail_screen.dart';

/// 保護者アプリ・後続保育機能 Phase A: デイリーボード(iPad中心)。
/// 登降園は保護者アプリ・キオスク端末など複数端末から記録されるため、Realtimeで即時反映する。
/// Phase 2 §2.1/§2.2: クラス絞り込み(年齢区分順)と在籍登園状況サマリーを追加。
class DailyBoardScreen extends StatefulWidget {
  const DailyBoardScreen({
    super.key,
    required this.service,
    required this.officeId,
    required this.businessDate,
  });

  final ChildcareService service;
  final String officeId;
  final DateTime businessDate;

  @override
  State<DailyBoardScreen> createState() => _DailyBoardScreenState();
}

class _DailyBoardScreenState extends State<DailyBoardScreen> {
  late Future<List<DailyBoardRow>> _rowsFuture;
  RealtimeChannel? _channel;

  List<ChildcareClass> _classes = const [];
  // null = 全クラス。クラスの並び順は fetch_childcare_classes の返却順(年齢区分順)を正とする。
  String? _selectedClassId;
  DailyBoardSummary? _summary;
  WeatherRecord? _weather;
  bool _weatherLoaded = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadClasses();
    _loadSummary();
    _loadWeather();
    _channel = widget.service.watchDailyChildStatus(widget.officeId, () {
      if (!mounted) return;
      setState(_load);
      _loadSummary();
    });
  }

  @override
  void dispose() {
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    super.dispose();
  }

  void _load() {
    _rowsFuture = widget.service.fetchDailyBoardForOffice(widget.officeId, widget.businessDate);
  }

  Future<void> _loadClasses() async {
    final classes = await widget.service.fetchChildcareClasses(widget.officeId);
    if (mounted) setState(() => _classes = classes);
  }

  Future<void> _loadSummary() async {
    final summary = await widget.service.fetchDailyBoardSummary(
      widget.officeId,
      widget.businessDate,
      classId: _selectedClassId,
    );
    if (mounted) setState(() => _summary = summary);
  }

  Future<void> _loadWeather() async {
    final weather = await widget.service.fetchDailyWeather(widget.officeId, widget.businessDate);
    if (mounted) {
      setState(() {
        _weather = weather;
        _weatherLoaded = true;
      });
    }
  }

  Future<void> _reload() async {
    setState(_load);
    _loadSummary();
    _loadWeather();
    await _rowsFuture;
  }

  Future<void> _recordProxyAttendance(DailyBoardRow row, String eventType) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProxyAttendanceSheet(
        service: widget.service,
        childId: row.childId,
        childName: row.nameLabel,
        eventType: eventType,
        businessDate: widget.businessDate,
      ),
    );
    if (result == true && mounted) {
      setState(_load);
      _loadSummary();
    }
  }

  Future<void> _editWeather() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _WeatherEditSheet(
        service: widget.service,
        officeId: widget.officeId,
        businessDate: widget.businessDate,
        initial: _weather,
      ),
    );
    if (saved == true) _loadWeather();
  }

  void _onClassChanged(String? classId) {
    setState(() => _selectedClassId = classId);
    _loadSummary();
  }

  void _openChildDetail(DailyBoardRow row) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChildDetailScreen(
          service: widget.service,
          childId: row.childId,
          childName: row.nameLabel,
          officeId: widget.officeId,
          businessDate: widget.businessDate,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const OhanaLogoHomeButton(),
        leadingWidth: 180,
        title: const Text('デイリーボード'),
      ),
      body: Column(
        children: [
          _ClassFilterBar(
            classes: _classes,
            selectedClassId: _selectedClassId,
            onChanged: _onClassChanged,
          ),
          _WeatherBar(weather: _weather, loaded: _weatherLoaded, onTap: _editWeather),
          _SummaryBar(summary: _summary),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: FutureBuilder<List<DailyBoardRow>>(
                future: _rowsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final all = snapshot.data ?? const <DailyBoardRow>[];
                  final rows = _selectedClassId == null
                      ? all
                      : all.where((r) => r.classId == _selectedClassId).toList();
                  if (rows.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [SizedBox(height: 120), Center(child: Text('在籍園児がいません'))],
                    );
                  }
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return Card(
                        child: Column(
                          children: [
                            ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              onTap: () => _openChildDetail(row),
                              title: Text(row.nameLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(row.className, style: const TextStyle(color: AppColors.textSecondary)),
                              trailing: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _StatusChip(status: row.status),
                                  if (row.lastEventAt != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        '${row.lastEventAt!.hour.toString().padLeft(2, '0')}:'
                                        '${row.lastEventAt!.minute.toString().padLeft(2, '0')}',
                                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (row.hasPickupChange)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.warmOrange.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.person_pin_circle_rounded, size: 18, color: AppColors.warmOrange),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'お迎え変更あり: ${row.pickupPersonName}'
                                        '${row.pickupTimeFrom != null ? '(${row.pickupTimeFrom}〜${row.pickupTimeTo})' : ''}',
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            _ProxyAttendanceButton(row: row, onTap: _recordProxyAttendance),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 状態に応じた代理登録ボタン(未登園/欠席→登園を登録、登園中→降園を登録、降園済み→なし)。
class _ProxyAttendanceButton extends StatelessWidget {
  const _ProxyAttendanceButton({required this.row, required this.onTap});

  final DailyBoardRow row;
  final Future<void> Function(DailyBoardRow row, String eventType) onTap;

  @override
  Widget build(BuildContext context) {
    final String? eventType;
    final String label;
    switch (row.status) {
      case 'present':
        eventType = 'pick_up';
        label = '降園を登録';
      case 'not_arrived':
      case 'absent':
        eventType = 'drop_off';
        label = '登園を登録';
      default:
        eventType = null;
        label = '';
    }
    if (eventType == null) return const SizedBox.shrink();
    final resolvedEventType = eventType;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => onTap(row, resolvedEventType),
          icon: const Icon(Icons.edit_calendar_rounded, size: 16),
          label: Text(label),
        ),
      ),
    );
  }
}

/// 代理登降園の登録シート。時刻(既定=現在時刻・手入力可)+ 保護者通知トグル(既定ON)。
class _ProxyAttendanceSheet extends StatefulWidget {
  const _ProxyAttendanceSheet({
    required this.service,
    required this.childId,
    required this.childName,
    required this.eventType,
    required this.businessDate,
  });

  final ChildcareService service;
  final String childId;
  final String childName;
  final String eventType; // 'drop_off' | 'pick_up'
  final DateTime businessDate;

  @override
  State<_ProxyAttendanceSheet> createState() => _ProxyAttendanceSheetState();
}

class _ProxyAttendanceSheetState extends State<_ProxyAttendanceSheet> {
  late TimeOfDay _time = TimeOfDay.now();
  bool _notify = true;
  bool _saving = false;

  String get _actionLabel => widget.eventType == 'drop_off' ? '登園' : '降園';

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    // 対象日 + 手入力時刻(JST壁時計)を UTC 実時刻へ変換して渡す(端末TZに依存しない)。
    final occurredAt = DateTime.utc(
      widget.businessDate.year,
      widget.businessDate.month,
      widget.businessDate.day,
      _time.hour,
      _time.minute,
    ).subtract(const Duration(hours: 9));
    try {
      await widget.service.recordStaffManualAttendance(
        childId: widget.childId,
        eventType: widget.eventType,
        occurredAt: occurredAt,
        notifyGuardian: _notify,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('登録に失敗しました(主任以上のみ登録できます)')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hh = _time.hour.toString().padLeft(2, '0');
    final mm = _time.minute.toString().padLeft(2, '0');
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.childName} の$_actionLabelを登録',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('$_actionLabel時刻', style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: _pickTime, child: Text('$hh:$mm')),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('保護者へ通知する'),
            value: _notify,
            onChanged: (v) => setState(() => _notify = v),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '登録中…' : '登録'),
            ),
          ),
        ],
      ),
    );
  }
}

/// クラス絞り込み(全クラス既定→クラス単位)。並び順は fetch_childcare_classes の返却順に従う。
class _ClassFilterBar extends StatelessWidget {
  const _ClassFilterBar({
    required this.classes,
    required this.selectedClassId,
    required this.onChanged,
  });

  final List<ChildcareClass> classes;
  final String? selectedClassId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          const Icon(Icons.filter_list_rounded, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: selectedClassId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'クラス',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('全クラス')),
                for (final c in classes)
                  DropdownMenuItem<String?>(value: c.classId, child: Text(c.className)),
              ],
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// 天気バー。未入力なら「未入力」を軽く表示(強アラート無し)。タップで編集シートを開く。
class _WeatherBar extends StatelessWidget {
  const _WeatherBar({required this.weather, required this.loaded, required this.onTap});

  final WeatherRecord? weather;
  final bool loaded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final w = weather;
    final label = !loaded
        ? '天気'
        : w == null
            ? '天気: 未入力'
            : '天気: ${w.weather}'
                '${w.temperature != null ? ' / ${w.temperature}℃' : ''}'
                '${w.humidity != null ? ' / ${w.humidity}%' : ''}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.skyBlue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.wb_sunny_rounded, size: 18, color: AppColors.warmOrange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: w == null ? AppColors.textSecondary : AppColors.textPrimary,
                  ),
                ),
              ),
              const Icon(Icons.edit_rounded, size: 16, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// 天気の編集シート。当日は誰でも、過去日/未来日は主任以上(RPC側でガード・失敗時はSnackBar)。
class _WeatherEditSheet extends StatefulWidget {
  const _WeatherEditSheet({
    required this.service,
    required this.officeId,
    required this.businessDate,
    required this.initial,
  });

  final ChildcareService service;
  final String officeId;
  final DateTime businessDate;
  final WeatherRecord? initial;

  @override
  State<_WeatherEditSheet> createState() => _WeatherEditSheetState();
}

class _WeatherEditSheetState extends State<_WeatherEditSheet> {
  late String _weather = widget.initial?.weather ?? weatherOptions.first;
  late final TextEditingController _temp =
      TextEditingController(text: widget.initial?.temperature?.toString() ?? '');
  late final TextEditingController _humidity =
      TextEditingController(text: widget.initial?.humidity?.toString() ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _temp.dispose();
    _humidity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.service.upsertDailyWeather(
        widget.officeId,
        widget.businessDate,
        weather: _weather,
        temperature: _temp.text.trim().isEmpty ? null : double.tryParse(_temp.text.trim()),
        humidity: _humidity.text.trim().isEmpty ? null : double.tryParse(_humidity.text.trim()),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('天気の保存に失敗しました(過去日/未来日の修正は主任以上のみ)')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('天気の記録', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _weather,
            decoration: const InputDecoration(labelText: '天気', border: OutlineInputBorder(), isDense: true),
            items: [for (final o in weatherOptions) DropdownMenuItem(value: o, child: Text(o))],
            onChanged: (v) => setState(() => _weather = v ?? _weather),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _temp,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '気温(℃)', border: OutlineInputBorder(), isDense: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _humidity,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '湿度(%)', border: OutlineInputBorder(), isDense: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中…' : '保存'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 在籍登園状況サマリー(在籍/登園予定/出席/登園中/欠席)。数字はRPC集計を表示するのみ。
class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.summary});

  final DailyBoardSummary? summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final items = <_SummaryItem>[
      _SummaryItem('在籍', s?.enrolled, AppColors.textPrimary),
      _SummaryItem('登園予定', s?.expected, AppColors.skyBlue),
      _SummaryItem('出席', s?.attended, AppColors.leafGreen),
      _SummaryItem('登園中', s?.presentNow, AppColors.leafGreen),
      _SummaryItem('欠席', s?.absent, AppColors.punchClockOut),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    children: [
                      Text(item.label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      const SizedBox(height: 2),
                      Text(
                        item.value?.toString() ?? '—',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: item.color),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryItem {
  const _SummaryItem(this.label, this.value, this.color);
  final String label;
  final int? value;
  final Color color;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (status) {
      case 'present':
        color = AppColors.leafGreen;
      case 'picked_up':
        color = AppColors.textSecondary;
      case 'absent':
        color = AppColors.punchClockOut;
      default:
        color = AppColors.warmOrange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
      child: Text(
        dailyBoardStatusLabel(status),
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}
