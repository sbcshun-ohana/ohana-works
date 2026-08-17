import 'package:flutter/material.dart';

import '../../../models/guardian_app.dart';
import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ohana_logo_home_button.dart';
import 'child_detail_screen.dart';

/// 園児台帳の一覧入口(ホームタイル用・俊指示 2026-08-17)。
/// クラス別の在園児一覧から園児をタップすると、園児詳細の「台帳」タブを直接開く。
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

class _ChildRegisterListScreenState extends State<ChildRegisterListScreen> {
  List<ChildForInvitation> _children = const [];
  bool _isLoading = true;
  String? _errorMessage;
  String _query = '';
  String? _classFilter; // null=全クラス

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final children = await widget.service.fetchChildrenForOffice(widget.officeId);
      if (mounted) {
        setState(() {
          _children = children;
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

  @override
  Widget build(BuildContext context) {
    // クラス+名前で絞り込み(俊指示 2026-08-17)
    final allClassNames = _children.map((c) => c.className ?? 'クラス未所属').toSet().toList()..sort();
    var filtered = _query.trim().isEmpty
        ? _children
        : _children.where((c) => c.displayName.contains(_query.trim())).toList();
    if (_classFilter != null) {
      filtered = filtered.where((c) => (c.className ?? 'クラス未所属') == _classFilter).toList();
    }

    // クラス別にグループ化(クラス未所属は末尾)
    final byClass = <String, List<ChildForInvitation>>{};
    for (final c in filtered) {
      byClass.putIfAbsent(c.className ?? 'クラス未所属', () => []).add(c);
    }
    final classNames = byClass.keys.toList()
      ..sort((a, b) {
        if (a == 'クラス未所属') return 1;
        if (b == 'クラス未所属') return -1;
        return a.compareTo(b);
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
                                hintText: '園児名で検索',
                                isDense: true,
                              ),
                              onChanged: (v) => setState(() => _query = v),
                            ),
                          ),
                          const SizedBox(width: 12),
                          DropdownButton<String?>(
                            value: _classFilter,
                            hint: const Text('全クラス'),
                            items: [
                              const DropdownMenuItem<String?>(value: null, child: Text('全クラス')),
                              for (final name in allClassNames)
                                DropdownMenuItem<String?>(value: name, child: Text(name)),
                            ],
                            onChanged: (v) => setState(() => _classFilter = v),
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
                            for (final className in classNames) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: 8, bottom: 4),
                                child: Text(className,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        color: AppColors.leafGreen)),
                              ),
                              for (final c in byClass[className]!)
                                Card(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  child: ListTile(
                                    leading: const Icon(Icons.badge_rounded, color: AppColors.leafGreen),
                                    title: Text('${c.displayName}${c.honorificSuffix ?? ''}'),
                                    trailing: const Icon(Icons.chevron_right_rounded),
                                    onTap: () => Navigator.of(context).push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => ChildDetailScreen(
                                          service: widget.service,
                                          childId: c.childId,
                                          childName: '${c.displayName}${c.honorificSuffix ?? ''}',
                                          officeId: widget.officeId,
                                          businessDate: widget.businessDate,
                                          openRegisterTab: true,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
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
}
