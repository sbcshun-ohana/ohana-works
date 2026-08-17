import 'package:flutter/material.dart';

import '../../../models/childcare.dart';
import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ohana_logo_home_button.dart';
import 'child_detail_screen.dart';
import 'child_register_tab.dart' show estimateCohortAge, parseClassAge;

/// 園児台帳の一覧入口(ホームタイル用・俊指示 2026-08-17)。
/// 在籍状況を区分してクラス・名前(漢字/ふりがな)で探せる。園児タップで「台帳」タブを直接開く。
/// デイリーボード→園児詳細の既存導線はそのまま(こちらは別の入り口)。
class ChildRegisterListScreen extends StatefulWidget {
  const ChildRegisterListScreen({
    super.key,
    required this.service,
    required this.officeId,
    required this.businessDate,
  });

  final ChildcareService service;
  final String officeId;
  final DateTime businessDate;

  @override
  State<ChildRegisterListScreen> createState() => _ChildRegisterListScreenState();
}

const _preEnrollLabel = '入園前(入園予定)';
const _withdrawnLabel = '卒園・退園済み';
const _noClassLabel = 'クラス未所属(在籍中)';

class _ChildRegisterListScreenState extends State<ChildRegisterListScreen> {
  List<Map<String, dynamic>> _children = const [];
  List<ChildcareClass> _classes = const [];
  bool _isLoading = true;
  String? _errorMessage;
  String _query = '';
  String? _filter; // null=全園児。クラス名 or _preEnrollLabel / _withdrawnLabel / _noClassLabel

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final children = await widget.service.fetchChildrenForOfficeMaster(widget.officeId);
      final classes = await widget.service.fetchChildcareClasses(widget.officeId);
      if (mounted) {
        setState(() {
          _children = children;
          _classes = classes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '園児一覧の読み込みに失敗しました: $e';
        });
      }
    }
  }

  /// 入園前の園児向け: 生年月日から入園予定クラス(年齢区分)を推定して表示ラベルを返す
  String? _plannedClassLabel(Map<String, dynamic> c) {
    final age = estimateCohortAge(c['birth_date'] as String?, c['enrollment_date'] as String?);
    if (age == null) return null;
    final match = _classes.where((cl) => parseClassAge(cl.ageGroup) == age).toList();
    if (match.isNotEmpty) {
      return '入園予定クラス: ${match.first.className}($age歳児)';
    }
    return '入園予定: $age歳児クラス相当';
  }

  /// 在籍状況を明確に区分する(俊指示: 入園前・卒園後がわかるように)
  String _category(Map<String, dynamic> c) {
    final status = (c['enrollment_status'] as String?) ?? '';
    if (status == '入園予定') return _preEnrollLabel;
    if (status == '退園済み' || status == '退園予定') return _withdrawnLabel;
    return (c['class_name'] as String?) ?? _noClassLabel;
  }

  /// 漢字(正式氏名・呼び名)とふりがなのどちらでもヒットさせる
  bool _matchesQuery(Map<String, dynamic> c, String query) {
    final display = (c['display_name'] as String?) ?? '';
    final full = (c['full_name'] as String?) ?? '';
    final kana = (c['name_kana'] as String?) ?? '';
    return display.contains(query) || full.contains(query) || kana.contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim();
    var filtered = q.isEmpty ? _children : _children.where((c) => _matchesQuery(c, q)).toList();
    if (_filter != null) {
      filtered = filtered.where((c) => _category(c) == _filter).toList();
    }

    // 区分別にグループ化。表示順=クラス→クラス未所属→入園前→卒園・退園済み
    final byCategory = <String, List<Map<String, dynamic>>>{};
    for (final c in filtered) {
      byCategory.putIfAbsent(_category(c), () => []).add(c);
    }
    int rank(String cat) {
      if (cat == _preEnrollLabel) return 2;
      if (cat == _withdrawnLabel) return 3;
      if (cat == _noClassLabel) return 1;
      return 0;
    }
    final categories = byCategory.keys.toList()
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.compareTo(b);
      });

    // プルダウンの選択肢(データに存在する区分のみ・順序は表示と同じ)
    final allCategories = _children.map(_category).toSet().toList()
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.compareTo(b);
      });

    return Scaffold(
      appBar: AppBar(
        leading: const OhanaBackHomeLeading(),
        leadingWidth: 200,
        title: const Text('園児台帳'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.search_rounded),
                                hintText: '園児名で検索(漢字・ひらがな)',
                                isDense: true,
                              ),
                              onChanged: (v) => setState(() => _query = v),
                            ),
                          ),
                          const SizedBox(width: 12),
                          DropdownButton<String?>(
                            value: _filter,
                            hint: const Text('全園児'),
                            items: [
                              const DropdownMenuItem<String?>(value: null, child: Text('全園児')),
                              for (final cat in allCategories)
                                DropdownMenuItem<String?>(value: cat, child: Text(cat)),
                            ],
                            onChanged: (v) => setState(() => _filter = v),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            for (final category in categories) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: 8, bottom: 4),
                                child: Text(category,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        color: category == _withdrawnLabel
                                            ? Colors.grey
                                            : category == _preEnrollLabel
                                                ? AppColors.warmOrange
                                                : AppColors.leafGreen)),
                              ),
                              for (final c in byCategory[category]!) _childTile(c, category),
                            ],
                            if (filtered.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text('該当する園児がいません', textAlign: TextAlign.center),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _childTile(Map<String, dynamic> c, String category) {
    final display = (c['display_name'] as String?) ?? '';
    final honorific = (c['honorific_suffix'] as String?) ?? '';
    final kana = (c['name_kana'] as String?) ?? '';
    final isWithdrawn = category == _withdrawnLabel;
    // 入園前の園児は生年月日から入園予定クラスを併記(俊指示 2026-08-17)
    final planned = category == _preEnrollLabel ? _plannedClassLabel(c) : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Icon(Icons.badge_rounded,
            color: isWithdrawn ? Colors.grey : AppColors.leafGreen),
        title: Row(
          children: [
            Text('$display$honorific',
                style: TextStyle(color: isWithdrawn ? Colors.grey : null)),
            if (planned != null) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.warmOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(planned,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.warmOrange)),
              ),
            ],
          ],
        ),
        subtitle: kana.isEmpty ? null : Text(kana, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => ChildDetailScreen(
              service: widget.service,
              childId: c['child_id'] as String,
              childName: '$display$honorific',
              officeId: widget.officeId,
              businessDate: widget.businessDate,
              openRegisterTab: true,
            ),
          ),
        ),
      ),
    );
  }
}
