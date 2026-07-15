import 'package:flutter/material.dart';

import '../../services/request_service.dart';
import '../../theme/app_theme.dart';

/// 15.2 欠勤連絡。
class AbsenceRequestScreen extends StatefulWidget {
  const AbsenceRequestScreen({super.key, required this.service});

  final RequestService service;

  @override
  State<AbsenceRequestScreen> createState() => _AbsenceRequestScreenState();
}

class _AbsenceRequestScreenState extends State<AbsenceRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final _detailController = TextEditingController();
  final _officeMessageController = TextEditingController();
  final _substituteDetailController = TextEditingController();

  DateTime? _targetDate;
  bool _hasSubstitute = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _reasonController.dispose();
    _detailController.dispose();
    _officeMessageController.dispose();
    _substituteDetailController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? now,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 60)),
    );
    if (picked != null) {
      setState(() => _targetDate = picked);
    }
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    final targetDate = _targetDate;
    if (targetDate == null) {
      setState(() => _errorMessage = '欠勤日を選択してください');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      await widget.service.submitAbsenceRequest(
        targetDate: targetDate,
        reason: _reasonController.text.trim(),
        detail: _detailController.text.trim().isEmpty ? null : _detailController.text.trim(),
        officeMessage:
            _officeMessageController.text.trim().isEmpty ? null : _officeMessageController.text.trim(),
        hasSubstitute: _hasSubstitute,
        substituteDetail: _hasSubstitute && _substituteDetailController.text.trim().isNotEmpty
            ? _substituteDetailController.text.trim()
            : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('欠勤連絡を送信しました')),
      );
      Navigator.of(context).pop();
    } catch (_) {
      setState(() => _errorMessage = '送信に失敗しました。もう一度お試しください。');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('欠勤連絡')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.warmOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: AppColors.warmOrange),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'やむを得ない事情がある場合にご利用ください。理由・連絡事項は具体的にご記入ください。',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text('欠勤日', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_rounded),
                label: Text(
                  _targetDate == null
                      ? '日付を選択'
                      : '${_targetDate!.year}/${_targetDate!.month}/${_targetDate!.day}',
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _reasonController,
                decoration: const InputDecoration(labelText: '理由'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return '理由を入力してください';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _detailController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '詳細(任意)'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _officeMessageController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '園への連絡事項(任意)'),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('代替対応の有無'),
                value: _hasSubstitute,
                activeThumbColor: AppColors.leafGreen,
                onChanged: (value) => setState(() => _hasSubstitute = value),
              ),
              if (_hasSubstitute) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _substituteDetailController,
                  decoration: const InputDecoration(labelText: '対応者・対応内容'),
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w500),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text('送信する'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
