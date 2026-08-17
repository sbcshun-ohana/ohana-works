import 'package:flutter/material.dart';

import '../../models/linked_child.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/child_context_app_bar_title.dart';

/// 食材チェック(M6 Phase 4・草案§12-14)。
/// 段階タブ(初期/中期/後期/完了期)ごとに必須・目安の食材を表示し、家庭での経験を登録する。
/// 状態は記録から導出(未確認/家庭で確認中/問題なし登録済み/症状あり・園確認待ち/医療確認中)。
/// 症状ありの登録は園の管理職へ通知され、当該食材は完了扱いにならない(給食開始は保留)。
class FoodCheckScreen extends StatefulWidget {
  const FoodCheckScreen({super.key, required this.guardianService, required this.child});

  final GuardianService guardianService;
  final LinkedChild child;

  @override
  State<FoodCheckScreen> createState() => _FoodCheckScreenState();
}

const _stages = ['初期', '中期', '後期', '完了期'];

Color _statusColor(String status) {
  switch (status) {
    case '問題なし登録済み':
      return AppColors.leafGreen;
    case '家庭で確認中':
      return AppColors.skyBlue;
    case '症状あり・園確認待ち':
      return AppColors.danger;
    case '医療確認中':
      return AppColors.warmOrange;
    default:
      return AppColors.textSecondary;
  }
}

class _FoodCheckScreenState extends State<FoodCheckScreen> {
  List<Map<String, dynamic>> _items = const [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.guardianService.fetchFoodChecklist(widget.child.childId);
      if (mounted) {
        setState(() {
          _items = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '読み込みに失敗しました: $e';
        });
      }
    }
  }

  /// 段階の必須進捗(代替グループはいずれか1つでOKとしてグループ単位で集計)
  ({int done, int total}) _requiredProgress(String stage) {
    final required = _items.where((i) => i['stage'] == stage && i['category'] == 'required');
    final groups = <String, bool>{};
    for (final i in required) {
      final key = (i['alt_group'] as String?) ?? (i['food_item_id'] as String);
      final done = i['item_status'] == '問題なし登録済み';
      groups[key] = (groups[key] ?? false) || done;
    }
    return (done: groups.values.where((v) => v).length, total: groups.length);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _stages.length,
      child: Scaffold(
        appBar: AppBar(
          title: ChildContextAppBarTitle(title: '食材チェック', officeName: widget.child.officeName),
          bottom: TabBar(isScrollable: false, tabs: [for (final s in _stages) Tab(text: s)]),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(child: Text(_errorMessage!, style: const TextStyle(color: AppColors.danger)))
                : TabBarView(children: [for (final s in _stages) _stageView(s)]),
      ),
    );
  }

  Widget _stageView(String stage) {
    final stageItems = _items.where((i) => i['stage'] == stage).toList();
    final required = stageItems.where((i) => i['category'] == 'required').toList();
    final reference = stageItems.where((i) => i['category'] == 'reference').toList();
    final progress = _requiredProgress(stage);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('必須確認食材の進捗: ${progress.done} / ${progress.total}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.total == 0 ? 0 : progress.done / progress.total,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 6),
                const Text('ご家庭で複数回試して、問題がないことを確認してから登録してください',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (required.isNotEmpty) ...[
            const Text('必須確認食材',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.danger)),
            const Text('「いずれか1つ」の印がある食材は、同じグループのどれか1つでかまいません',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            for (final i in required) _itemTile(i),
            const SizedBox(height: 12),
          ],
          if (reference.isNotEmpty) ...[
            const Text('目安食材(進め方の参考)',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            for (final i in reference) _itemTile(i),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _itemTile(Map<String, dynamic> item) {
    final status = (item['item_status'] as String?) ?? '未確認';
    final color = _statusColor(status);
    final isSymptom = status == '症状あり・園確認待ち' || status == '医療確認中';
    final altGroup = item['alt_group'] as String?;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        title: Row(
          children: [
            Flexible(child: Text(item['name'] as String, style: const TextStyle(fontSize: 14))),
            if (altGroup != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.skyBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text('いずれか1つ',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.skyBlue)),
              ),
            ],
          ],
        ),
        subtitle: isSymptom
            ? const Text('症状の報告があるため、この食材の給食開始を保留しています',
                style: TextStyle(fontSize: 11, color: AppColors.danger))
            : null,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(status,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ),
        onTap: () => _openRecordSheet(item),
      ),
    );
  }

  Future<void> _openRecordSheet(Map<String, dynamic> item) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RecordSheet(
        guardianService: widget.guardianService,
        childId: widget.child.childId,
        item: item,
      ),
    );
    if (changed == true) _load();
  }
}

/// 食材経験の登録シート(§14.1)。
class _RecordSheet extends StatefulWidget {
  const _RecordSheet({required this.guardianService, required this.childId, required this.item});

  final GuardianService guardianService;
  final String childId;
  final Map<String, dynamic> item;

  @override
  State<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<_RecordSheet> {
  DateTime _intakeDate = DateTime.now();
  bool _multipleConfirmed = false;
  String _result = 'ok';
  final _symptomsController = TextEditingController();
  final _onsetController = TextEditingController();
  final _amountController = TextEditingController();
  final _medicalController = TextEditingController();
  final _noteController = TextEditingController();
  bool _isBusy = false;
  String? _errorMessage;

  @override
  void dispose() {
    _symptomsController.dispose();
    _onsetController.dispose();
    _amountController.dispose();
    _medicalController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_result == 'symptom' && _symptomsController.text.trim().isEmpty) {
      setState(() => _errorMessage = '症状の内容を入力してください');
      return;
    }
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      await widget.guardianService.recordFoodIntake(
        childId: widget.childId,
        foodItemId: widget.item['food_item_id'] as String,
        intakeDate: _intakeDate,
        multipleConfirmed: _multipleConfirmed,
        result: _result,
        symptoms: _result == 'symptom' ? _symptomsController.text.trim() : null,
        onsetNote: _onsetController.text.trim().isEmpty ? null : _onsetController.text.trim(),
        amountNote: _amountController.text.trim().isEmpty ? null : _amountController.text.trim(),
        medicalStatus: _medicalController.text.trim().isEmpty ? null : _medicalController.text.trim(),
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      );
      if (!mounted) return;
      if (_result == 'symptom') {
        // §14.4: 園への連絡・医療機関への相談・診断書の案内
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('園へ報告しました',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            content: const Text(
                '症状の内容は園に共有されました。心配な症状がある場合は医療機関にご相談ください。'
                'アレルギーの診断を受けた場合は、診断書のご提出をお願いすることがあります。'
                'この食材の給食提供は開始を保留します。'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる'))],
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on GuardianServiceException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${widget.item['name']} の記録',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _intakeDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _intakeDate = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: '摂取日'),
                  child: Text(
                      '${_intakeDate.year}-${_intakeDate.month.toString().padLeft(2, '0')}-${_intakeDate.day.toString().padLeft(2, '0')}'),
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'ok', label: Text('問題なし')),
                  ButtonSegment(value: 'symptom', label: Text('症状あり')),
                ],
                selected: {_result},
                onSelectionChanged: (v) => setState(() => _result = v.first),
              ),
              if (_result == 'ok')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('家庭で複数回確認済み', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('オンにするとこの1回の登録で完了になります',
                      style: TextStyle(fontSize: 11)),
                  value: _multipleConfirmed,
                  onChanged: (v) => setState(() => _multipleConfirmed = v),
                ),
              if (_result == 'symptom') ...[
                TextField(
                  controller: _symptomsController,
                  decoration: const InputDecoration(labelText: '症状の内容 *', hintText: '例: 口周りに発疹'),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _onsetController,
                  decoration: const InputDecoration(labelText: '発症時刻', hintText: '例: 食後30分'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _amountController,
                  decoration: const InputDecoration(labelText: '摂取量の目安', hintText: '例: ひと口'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _medicalController,
                  decoration: const InputDecoration(labelText: '受診状況', hintText: '例: 未受診・受診予定'),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: '備考(任意)'),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(_errorMessage!, style: const TextStyle(color: AppColors.danger)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _isBusy ? null : _submit,
                child: Text(_isBusy ? '登録中…' : '登録する'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
