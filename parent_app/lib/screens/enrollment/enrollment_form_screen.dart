import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/enrollment_form.dart';
import '../../models/linked_child.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/child_context_app_bar_title.dart';
import 'enrollment_form_definition.dart';

/// 入園時基本情報フォーム(M6 Phase 2・草案§8)。
/// 10ステップ・下書き自動保存(ステップ移動時)・進捗表示・途中再開・確認画面・提出。
/// 提出後は読み取り専用。差し戻し時はメッセージを表示して再編集できる。
class EnrollmentFormScreen extends StatefulWidget {
  const EnrollmentFormScreen({super.key, required this.guardianService, required this.child});

  final GuardianService guardianService;
  final LinkedChild child;

  @override
  State<EnrollmentFormScreen> createState() => _EnrollmentFormScreenState();
}

class _EnrollmentFormScreenState extends State<EnrollmentFormScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  EnrollmentFormState? _form;
  Map<String, dynamic> _data = {};
  int _step = 1; // 1〜10
  bool _isSaving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final form = await widget.guardianService.fetchEnrollmentForm(widget.child.childId);
      if (form != null) {
        _form = form;
        _data = _deepCopy(form.formData);
        _step = form.currentStep.clamp(1, enrollmentSteps.length);
      } else {
        // 初回: 園の仮登録値+兄弟の承認済みフォームから初期値を作る(prefill)
        final prefill = await widget.guardianService.fetchEnrollmentPrefill(widget.child.childId);
        _data = {
          'basic': Map<String, dynamic>.from((prefill['basic'] as Map?)?.cast<String, dynamic>() ?? {}),
          'address': Map<String, dynamic>.from((prefill['address'] as Map?)?.cast<String, dynamic>() ?? {}),
          'guardians': List<dynamic>.from((prefill['guardians'] as List?) ?? []),
          'family': List<dynamic>.from((prefill['family'] as List?) ?? []),
          'pickup': {
            'emergency': List<dynamic>.from((prefill['emergency'] as List?) ?? []),
          },
        };
      }
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '読み込みに失敗しました: $e';
        });
      }
    }
  }

  Map<String, dynamic> _deepCopy(Map<String, dynamic> src) =>
      jsonDecode(jsonEncode(src)) as Map<String, dynamic>;

  bool get _isEditable => _form == null || _form!.isEditable;

  // ===== データアクセス =====

  Map<String, dynamic> _section(String key) {
    final s = _data[key];
    if (s is Map<String, dynamic>) return s;
    final m = <String, dynamic>{};
    _data[key] = m;
    return m;
  }

  List<dynamic> _sectionList(String sectionKey, String listKey) {
    if (listKey.isEmpty) {
      final s = _data[sectionKey];
      if (s is List) return s;
      final l = <dynamic>[];
      _data[sectionKey] = l;
      return l;
    }
    final section = _section(sectionKey);
    final s = section[listKey];
    if (s is List) return s;
    final l = <dynamic>[];
    section[listKey] = l;
    return l;
  }

  // ===== 保存・提出 =====

  Future<bool> _saveDraft({int? stepOverride}) async {
    if (!_isEditable) return true;
    setState(() => _isSaving = true);
    try {
      await widget.guardianService
          .saveEnrollmentDraft(widget.child.childId, _data, stepOverride ?? _step);
      _dirty = false;
      return true;
    } on GuardianServiceException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
      return false;
    } catch (e) {
      if (mounted) setState(() => _errorMessage = '保存に失敗しました: $e');
      return false;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _goToStep(int step) async {
    if (_isEditable && _dirty) {
      final ok = await _saveDraft(stepOverride: step);
      if (!ok) return;
    } else if (_isEditable) {
      // 位置だけ保存(再開位置の記録)
      await _saveDraft(stepOverride: step);
    }
    if (mounted) {
      setState(() {
        _step = step;
        _errorMessage = null;
      });
    }
  }

  Future<void> _submit() async {
    final ok = await _saveDraft();
    if (!ok) return;
    setState(() => _isSaving = true);
    try {
      await widget.guardianService.submitEnrollmentForm(widget.child.childId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('提出しました', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          content: const Text('園で内容を確認します。確認が完了すると通知でお知らせします。'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる'))],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on GuardianServiceException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ===== 必須チェック(クライアント側) =====

  /// 未入力の必須項目(該当ステップ番号つき。確認画面からタップでジャンプできるようにする)
  List<({int step, String stepTitle, String label})> _missingRequired() {
    final missing = <({int step, String stepTitle, String label})>[];
    for (var i = 0; i < enrollmentSteps.length; i++) {
      final step = enrollmentSteps[i];
      for (final f in step.fields) {
        if (!f.required) continue;
        final v = _section(step.sectionKey)[f.key];
        if (v == null || (v is String && v.trim().isEmpty)) {
          missing.add((step: i + 1, stepTitle: step.title, label: f.label));
        }
      }
      for (final g in step.listGroups) {
        final list = _sectionList(step.sectionKey, g.listKey);
        if (g.minItems > 0 && list.length < g.minItems) {
          missing.add((step: i + 1, stepTitle: step.title, label: '${g.itemLabel}を${g.minItems}名以上登録してください'));
        }
      }
    }
    return missing;
  }

  double get _highTemp {
    final t = _section('health')['normal_temp'];
    if (t == null) return 0;
    return double.tryParse(t.toString()) ?? 0;
  }

  // ===== 郵便番号検索(zipcloud) =====

  Future<void> _lookupPostal(String sectionKey) async {
    final zip = (_section(sectionKey)['postal_code'] ?? '').toString().replaceAll('-', '').trim();
    if (zip.length != 7) {
      setState(() => _errorMessage = '郵便番号は7桁で入力してください');
      return;
    }
    setState(() => _errorMessage = null);
    final client = HttpClient();
    try {
      final req = await client
          .getUrl(Uri.parse('https://zipcloud.ibsnet.co.jp/api/search?zipcode=$zip'));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final results = json['results'] as List?;
      if (results == null || results.isEmpty) {
        if (mounted) setState(() => _errorMessage = '該当する住所が見つかりませんでした');
        return;
      }
      final r = results.first as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          final section = _section(sectionKey);
          section['prefecture'] = r['address1'];
          section['city'] = r['address2'];
          section['town'] = r['address3'];
          _dirty = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _errorMessage = '住所検索に失敗しました(通信環境をご確認ください)');
    } finally {
      client.close();
    }
  }

  // ===== UI =====

  @override
  Widget build(BuildContext context) {
    final stepDef = enrollmentSteps[_step - 1];
    return PopScope(
      canPop: !(_isEditable && _dirty),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _saveDraft();
        if (!mounted) return;
        Navigator.of(this.context).pop(true);
      },
      child: Scaffold(
        appBar: AppBar(
          title: ChildContextAppBarTitle(
              title: '入園時基本情報', officeName: widget.child.officeName),
          actions: [
            if (_isEditable && !_isLoading)
              TextButton(
                onPressed: _isSaving
                    ? null
                    : () async {
                        final ok = await _saveDraft();
                        if (!ok || !mounted) return;
                        Navigator.of(this.context).pop(true);
                      },
                child: const Text('保存して閉じる'),
              ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _progressHeader(),
                  if (_statusBanner() != null) _statusBanner()!,
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(_errorMessage!,
                          style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
                    ),
                  Expanded(
                    child: stepDef.isConfirmStep ? _confirmStep() : _fieldsStep(stepDef),
                  ),
                  _navBar(),
                ],
              ),
      ),
    );
  }

  Widget _progressHeader() {
    final total = enrollmentSteps.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('全$total段階中 $_step段階目: ${enrollmentSteps[_step - 1].title}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              ),
              if (_form?.lastSavedAt != null)
                Text('自動保存済み', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: _step / total, minHeight: 6),
          ),
        ],
      ),
    );
  }

  Widget? _statusBanner() {
    final form = _form;
    if (form == null) return null;
    if (form.status == 'sent_back') {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.warmOrange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.warmOrange.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('園から差し戻しがあります',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            if (form.latestReviewMessage != null) ...[
              const SizedBox(height: 4),
              Text(form.latestReviewMessage!, style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 4),
            const Text('内容を修正して、最終確認から再提出してください',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      );
    }
    if (form.status == 'submitted') {
      return _infoBanner('提出済みです。園の確認をお待ちください(修正はできません)', AppColors.skyBlue);
    }
    if (form.status == 'approved') {
      return _infoBanner('園に承認されました。ご登録ありがとうございました', AppColors.leafGreen);
    }
    return null;
  }

  Widget _infoBanner(String text, Color color) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }

  Widget _navBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            if (_step > 1)
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSaving ? null : () => _goToStep(_step - 1),
                  child: const Text('前へ'),
                ),
              ),
            if (_step > 1) const SizedBox(width: 12),
            if (_step < enrollmentSteps.length)
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _isSaving ? null : () => _goToStep(_step + 1),
                  child: Text(_isEditable ? '保存して次へ' : '次へ'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ----- 入力ステップ -----

  Widget _fieldsStep(StepDef stepDef) {
    return ListView(
      key: ValueKey('step$_step'),
      padding: const EdgeInsets.all(16),
      children: [
        if (stepDef.note != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(stepDef.note!,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
        for (final f in stepDef.fields) _fieldWidget(stepDef.sectionKey, _section(stepDef.sectionKey), f),
        for (final g in stepDef.listGroups) ..._listGroupWidgets(stepDef.sectionKey, g),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _fieldWidget(String sectionKey, Map<String, dynamic> holder, FieldDef f,
      {String? keyPrefix}) {
    final value = holder[f.key];
    final enabled = _isEditable;
    final fieldKey = ValueKey('${keyPrefix ?? sectionKey}.${f.key}.$_step');
    switch (f.type) {
      case FieldType.toggle:
        return SwitchListTile(
          key: fieldKey,
          contentPadding: EdgeInsets.zero,
          title: Text(f.label, style: const TextStyle(fontSize: 14)),
          value: value == true,
          onChanged: enabled
              ? (v) => setState(() {
                    holder[f.key] = v;
                    _dirty = true;
                  })
              : null,
        );
      case FieldType.select:
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: DropdownButtonFormField<String>(
            key: fieldKey,
            initialValue: (value is String && (f.options?.contains(value) ?? false)) ? value : null,
            decoration: InputDecoration(labelText: f.label + (f.required ? ' *' : '')),
            items: [
              for (final o in f.options ?? const <String>[])
                DropdownMenuItem(value: o, child: Text(o)),
            ],
            onChanged: enabled
                ? (v) {
                    holder[f.key] = v;
                    _dirty = true;
                  }
                : null,
          ),
        );
      case FieldType.date:
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: InkWell(
            key: fieldKey,
            onTap: enabled
                ? () async {
                    final now = DateTime.now();
                    final initial = DateTime.tryParse((value ?? '').toString()) ??
                        DateTime(now.year - 2, now.month, now.day);
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: initial,
                      firstDate: DateTime(now.year - 20),
                      lastDate: DateTime(now.year + 2),
                    );
                    if (picked != null) {
                      setState(() {
                        holder[f.key] =
                            '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                        _dirty = true;
                      });
                    }
                  }
                : null,
            child: InputDecorator(
              decoration: InputDecoration(labelText: f.label + (f.required ? ' *' : '')),
              child: Text((value ?? '').toString().isEmpty ? '選択してください' : value.toString(),
                  style: TextStyle(
                      fontSize: 15,
                      color: (value ?? '').toString().isEmpty
                          ? AppColors.textSecondary
                          : AppColors.textPrimary)),
            ),
          ),
        );
      case FieldType.postal:
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextFormField(
                  key: fieldKey,
                  enabled: enabled,
                  initialValue: (value ?? '').toString(),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: f.label + (f.required ? ' *' : ''), hintText: f.hint),
                  onChanged: (v) {
                    holder[f.key] = v;
                    _dirty = true;
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: enabled ? () => _lookupPostal(sectionKey) : null,
                child: const Text('住所検索'),
              ),
            ],
          ),
        );
      case FieldType.text:
      case FieldType.kana:
      case FieldType.multiline:
      case FieldType.phone:
      case FieldType.email:
      case FieldType.number:
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextFormField(
            key: fieldKey,
            enabled: enabled,
            initialValue: (value ?? '').toString(),
            maxLines: f.type == FieldType.multiline ? 3 : 1,
            keyboardType: switch (f.type) {
              FieldType.phone => TextInputType.phone,
              FieldType.email => TextInputType.emailAddress,
              FieldType.number => const TextInputType.numberWithOptions(decimal: true),
              FieldType.multiline => TextInputType.multiline,
              _ => TextInputType.text,
            },
            decoration:
                InputDecoration(labelText: f.label + (f.required ? ' *' : ''), hintText: f.hint),
            onChanged: (v) {
              holder[f.key] = v;
              _dirty = true;
            },
          ),
        );
    }
  }

  List<Widget> _listGroupWidgets(String sectionKey, ListGroupDef g) {
    final list = _sectionList(sectionKey, g.listKey);
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(g.itemLabel,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      ),
      if (g.note != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child:
              Text(g.note!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ),
      for (var i = 0; i < list.length; i++)
        Container(
          key: ValueKey('$sectionKey.${g.listKey}.$i.${list.length}'),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('${g.itemLabel} ${i + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                  if (_isEditable)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      onPressed: () => setState(() {
                        list.removeAt(i);
                        _dirty = true;
                      }),
                    ),
                ],
              ),
              // cast() は元Mapへのビューを返すため、書き込みはそのまま _data に反映される
              for (final f in g.itemFields)
                _fieldWidget(sectionKey, (list[i] as Map).cast<String, dynamic>(), f,
                    keyPrefix: '$sectionKey.${g.listKey}.$i'),
            ],
          ),
        ),
      if (_isEditable)
        OutlinedButton.icon(
          onPressed: () => setState(() {
            list.add(<String, dynamic>{});
            _dirty = true;
          }),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text('${g.itemLabel}を追加'),
        ),
      const SizedBox(height: 8),
    ];
  }

  // ----- 最終確認ステップ -----

  Widget _confirmStep() {
    final missing = _missingRequired();
    final highTemp = _highTemp >= 37.5;
    final ack = _section('health')['high_temp_acknowledged'] == true;
    final canSubmit = _isEditable && missing.isEmpty && (!highTemp || ack);
    return ListView(
      key: const ValueKey('confirm'),
      padding: const EdgeInsets.all(16),
      children: [
        if (missing.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('未入力の必須項目があります',
                    style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.danger)),
                const Text('項目をタップすると入力画面へ移動します',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                // タップで該当ステップへ直接ジャンプ(前へを連打しなくてよいように)
                for (final m in missing)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _goToStep(m.step),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('${m.stepTitle}: ${m.label}',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.underline)),
                          ),
                          const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.danger),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (highTemp) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warmOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.warmOrange.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '平熱が37.5℃以上で登録されています。医師の診断書がない限り、体温が37.5℃に達した時点でお迎えを要請します。',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('上記を確認しました', style: TextStyle(fontSize: 13)),
                  value: ack,
                  onChanged: _isEditable
                      ? (v) => setState(() {
                            _section('health')['high_temp_acknowledged'] = v == true;
                            _dirty = true;
                          })
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        const Text('入力内容の確認', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 8),
        for (final step in enrollmentSteps.where((s) => !s.isConfirmStep)) _summaryCard(step),
        const SizedBox(height: 16),
        if (_isEditable)
          FilledButton(
            onPressed: canSubmit && !_isSaving ? _submit : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(_form?.status == 'sent_back' ? '修正して再提出する' : '園へ提出する',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
          ),
        if (_isEditable)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('「園へ提出」を押すまでは園に共有されません',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _summaryCard(StepDef step) {
    final rows = <Widget>[];
    for (final f in step.fields) {
      final v = _section(step.sectionKey)[f.key];
      if (v == null || (v is String && v.trim().isEmpty)) continue;
      rows.add(_summaryRow(f.label, v is bool ? (v ? 'はい' : 'いいえ') : v.toString()));
    }
    for (final g in step.listGroups) {
      final list = _sectionList(step.sectionKey, g.listKey);
      for (var i = 0; i < list.length; i++) {
        final item = (list[i] as Map).cast<String, dynamic>();
        final name = (item['name'] ?? '').toString();
        final parts = <String>[];
        for (final f in g.itemFields) {
          if (f.key == 'name') continue;
          final v = item[f.key];
          if (v == null || (v is String && v.trim().isEmpty) || v == false) continue;
          parts.add(v is bool ? f.label : '${f.label}: $v');
        }
        rows.add(_summaryRow('${g.itemLabel}${i + 1}',
            name.isEmpty ? parts.join(' / ') : '$name${parts.isEmpty ? '' : '(${parts.join(' / ')})'}'));
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    // カードタップでも該当ステップへ移動できる(修正したい箇所へ直接戻る導線)
    final stepNumber = enrollmentSteps.indexOf(step) + 1;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _isEditable ? () => _goToStep(stepNumber) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(step.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.skyBlue)),
                ),
                if (_isEditable)
                  const Icon(Icons.edit_rounded, size: 16, color: AppColors.textSecondary),
              ],
            ),
            const SizedBox(height: 6),
            ...rows,
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 130,
              child: Text(label,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
