import 'package:flutter/material.dart';

import '../../../models/childcare.dart';
import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';

const _pageSize = 20;
const _twentyFourHours = Duration(hours: 24);

/// 園内記録タブ(Ohana Kids・iPad)。
/// 上部: 新規入力(モーダル遷移なし・1画面完結)。下部: 新しい順の一覧(ページング)。
/// 絞り込み・権限判定はRPC側の責務。ここでの編集・削除ボタンの表示制御は
/// 見た目の出し分けのみで、実際の許可判定は常にRPC側(24時間ルール等)で行われる。
class ChildInternalNotesTab extends StatefulWidget {
  const ChildInternalNotesTab({
    super.key,
    required this.service,
    required this.childId,
    required this.officeId,
  });

  final ChildcareService service;
  final String childId;
  final String officeId;

  @override
  State<ChildInternalNotesTab> createState() => _ChildInternalNotesTabState();
}

class _ChildInternalNotesTabState extends State<ChildInternalNotesTab> {
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _listError;
  final List<ChildInternalNote> _notes = [];

  String? _myEmployeeId;
  bool _isChief = false;
  Map<String, String> _staffNames = {};

  DateTime _newDate = DateTime.now();
  String _newCategory = kChildInternalNoteCategories.first;
  final _newBodyController = TextEditingController();
  bool _newAiExcluded = false;
  bool _isSaving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _newBodyController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() => _isLoadingInitial = true);
    try {
      final results = await Future.wait([
        widget.service.fetchMyEmployeeId(),
        widget.service.isChildInternalNotesChief(widget.officeId),
        widget.service.fetchChildcareOfficeStaff(widget.officeId),
      ]);
      _myEmployeeId = results[0] as String?;
      _isChief = results[1] as bool;
      _staffNames = {
        for (final staff in results[2] as List<ChildcareStaffMember>) staff.employeeId: staff.name,
      };
      await _loadFirstPage();
    } finally {
      if (mounted) setState(() => _isLoadingInitial = false);
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() => _listError = null);
    try {
      final page = await widget.service.fetchChildInternalNotes(
        childId: widget.childId,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _notes
          ..clear()
          ..addAll(page);
        _hasMore = page.length == _pageSize;
      });
    } catch (_) {
      if (mounted) setState(() => _listError = '記録の取得に失敗しました。もう一度お試しください。');
    }
  }

  Future<void> _loadMore() async {
    setState(() => _isLoadingMore = true);
    try {
      final page = await widget.service.fetchChildInternalNotes(
        childId: widget.childId,
        limit: _pageSize,
        offset: _notes.length,
      );
      if (!mounted) return;
      setState(() {
        _notes.addAll(page);
        _hasMore = page.length == _pageSize;
      });
    } catch (_) {
      if (mounted) setState(() => _listError = '記録の取得に失敗しました。もう一度お試しください。');
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _pickNewDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _newDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _newDate = picked);
  }

  Future<void> _save() async {
    final body = _newBodyController.text.trim();
    if (body.isEmpty) {
      setState(() => _saveError = '本文を入力してください');
      return;
    }
    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    try {
      await widget.service.createChildInternalNote(
        childId: widget.childId,
        noteDate: _newDate,
        category: _newCategory,
        body: body,
        aiExcluded: _newAiExcluded,
      );
      _newBodyController.clear();
      setState(() {
        _newDate = DateTime.now();
        _newAiExcluded = false;
      });
      await _loadFirstPage();
    } catch (_) {
      setState(() => _saveError = '保存に失敗しました。もう一度お試しください。');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  bool _canEdit(ChildInternalNote note) {
    if (_isChief) return true;
    if (_myEmployeeId == null || note.authorEmployeeId != _myEmployeeId) return false;
    return DateTime.now().difference(note.createdAt) < _twentyFourHours;
  }

  Future<void> _openEditDialog(ChildInternalNote note) async {
    var date = note.noteDate;
    var category = note.category;
    var aiExcluded = note.aiExcluded;
    final bodyController = TextEditingController(text: note.body);
    String? dialogError;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('園内記録を編集'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('対象日', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.tryParse(date) ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (picked != null) {
                      setDialogState(() => date = ChildcareService.dateOnly(picked));
                    }
                  },
                  icon: const Icon(Icons.calendar_today_rounded, size: 16),
                  label: Text(date),
                ),
                const SizedBox(height: 12),
                const Text('区分', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                DropdownButton<String>(
                  isExpanded: true,
                  value: category,
                  items: kChildInternalNoteCategories
                      .map(
                        (c) => DropdownMenuItem(value: c, child: Text(childInternalNoteCategoryLabel(c))),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => category = v);
                  },
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: aiExcluded,
                  title: const Text('AI参照から除外', style: TextStyle(fontSize: 13)),
                  onChanged: (v) => setDialogState(() => aiExcluded = v ?? false),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: bodyController,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: '本文'),
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 8),
                  Text(dialogError!, style: const TextStyle(color: AppColors.punchClockOut, fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('キャンセル')),
            ElevatedButton(
              onPressed: () async {
                if (bodyController.text.trim().isEmpty) {
                  setDialogState(() => dialogError = '本文を入力してください');
                  return;
                }
                try {
                  await widget.service.updateChildInternalNote(
                    noteId: note.id,
                    body: bodyController.text.trim(),
                    category: category,
                    aiExcluded: aiExcluded,
                    noteDate: date,
                  );
                  if (context.mounted) Navigator.of(context).pop(true);
                } catch (_) {
                  setDialogState(() => dialogError = '更新に失敗しました。もう一度お試しください。');
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) await _loadFirstPage();
  }

  Future<void> _confirmDelete(ChildInternalNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('この記録を削除します'),
        content: const Text('削除した記録は一覧から表示されなくなります。よろしいですか?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('キャンセル')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.punchClockOut),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.service.softDeleteChildInternalNote(note.id);
      await _loadFirstPage();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('削除に失敗しました。もう一度お試しください。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingInitial) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.warmOrange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.warmOrange),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'この記録は保護者には表示されません',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
        _NewNoteForm(
          date: _newDate,
          category: _newCategory,
          bodyController: _newBodyController,
          aiExcluded: _newAiExcluded,
          isSaving: _isSaving,
          errorMessage: _saveError,
          onPickDate: _pickNewDate,
          onCategoryChanged: (v) => setState(() => _newCategory = v),
          onAiExcludedChanged: (v) => setState(() => _newAiExcluded = v),
          onSave: _save,
        ),
        const SizedBox(height: 24),
        if (_listError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_listError!, style: const TextStyle(color: AppColors.punchClockOut)),
          ),
        if (_notes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('記録がありません', style: TextStyle(color: AppColors.textSecondary))),
          )
        else
          ..._notes.map(
            (note) => _NoteCard(
              note: note,
              authorName: _staffNames[note.authorEmployeeId] ?? '(不明)',
              canEdit: _canEdit(note),
              onEdit: () => _openEditDialog(note),
              onDelete: () => _confirmDelete(note),
            ),
          ),
        if (_hasMore) ...[
          const SizedBox(height: 8),
          Center(
            child: OutlinedButton(
              onPressed: _isLoadingMore ? null : _loadMore,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: _isLoadingMore
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('もっと見る'),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _NewNoteForm extends StatelessWidget {
  const _NewNoteForm({
    required this.date,
    required this.category,
    required this.bodyController,
    required this.aiExcluded,
    required this.isSaving,
    required this.errorMessage,
    required this.onPickDate,
    required this.onCategoryChanged,
    required this.onAiExcludedChanged,
    required this.onSave,
  });

  final DateTime date;
  final String category;
  final TextEditingController bodyController;
  final bool aiExcluded;
  final bool isSaving;
  final String? errorMessage;
  final VoidCallback onPickDate;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<bool> onAiExcludedChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('新規入力', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: onPickDate,
                  icon: const Icon(Icons.calendar_today_rounded, size: 18),
                  label: Text('${date.year}/${date.month}/${date.day}'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    items: kChildInternalNoteCategories
                        .map(
                          (c) => DropdownMenuItem(value: c, child: Text(childInternalNoteCategoryLabel(c))),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) onCategoryChanged(v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: aiExcluded,
              title: const Text('AI参照から除外', style: TextStyle(fontSize: 14)),
              onChanged: (v) => onAiExcludedChanged(v ?? false),
            ),
            TextField(
              controller: bodyController,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: '本文を入力',
                border: OutlineInputBorder(),
              ),
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(errorMessage!, style: const TextStyle(color: AppColors.punchClockOut, fontSize: 13)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isSaving ? null : onSave,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('保存する', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.authorName,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
  });

  final ChildInternalNote note;
  final String authorName;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.skyBlue.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    childInternalNoteCategoryLabel(note.category),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.skyBlue),
                  ),
                ),
                const SizedBox(width: 8),
                Text(note.noteDate, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '記載者: $authorName',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (note.aiExcluded)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.smart_toy_outlined, size: 16, color: AppColors.textSecondary),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(note.body, style: const TextStyle(fontSize: 14, height: 1.4)),
            if (canEdit) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: '編集',
                    iconSize: 22,
                  ),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.punchClockOut),
                    tooltip: '削除',
                    iconSize: 22,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
