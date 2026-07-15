import 'package:flutter/material.dart';

import '../../models/leave_request.dart';
import '../../services/request_service.dart';
import '../../theme/app_theme.dart';

/// 15.3 遅刻・早退申請(事前申請・事後報告の両方に対応)。
class TardinessRequestScreen extends StatefulWidget {
  const TardinessRequestScreen({super.key, required this.service});

  final RequestService service;

  @override
  State<TardinessRequestScreen> createState() => _TardinessRequestScreenState();
}

class _TardinessRequestScreenState extends State<TardinessRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();

  DateTime? _targetDate;
  TimeOfDay? _time;
  TardinessSubType _subType = TardinessSubType.tardiness;
  bool _isSubmitting = false;
  String? _errorMessage;

  bool get _isAdvance {
    final targetDate = _targetDate;
    if (targetDate == null) return true;
    final now = DateTime.now();
    return !targetDate.isBefore(DateTime(now.year, now.month, now.day));
  }

  @override
  void dispose() {
    _reasonController.dispose();
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

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _time = picked);
    }
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    final targetDate = _targetDate;
    final time = _time;
    if (targetDate == null) {
      setState(() => _errorMessage = '対象日を選択してください');
      return;
    }
    if (time == null) {
      setState(() => _errorMessage = '時刻を選択してください');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final timeStr =
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      await widget.service.submitTardinessRequest(
        targetDate: targetDate,
        subType: _subType,
        time: timeStr,
        reason: _reasonController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_subType.label}を${_isAdvance ? '申請' : '報告'}しました')),
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
      appBar: AppBar(title: const Text('遅刻・早退申請')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('種別', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                children: TardinessSubType.values.map((type) {
                  final selected = _subType == type;
                  return ChoiceChip(
                    label: Text(type.label),
                    selected: selected,
                    selectedColor: AppColors.skyBlue,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) => setState(() => _subType = type),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              const Text('対象日', style: TextStyle(fontWeight: FontWeight.w700)),
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
              if (_targetDate != null) ...[
                const SizedBox(height: 8),
                Text(
                  _isAdvance ? '事前申請として登録されます' : '事後報告として登録されます',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
              const SizedBox(height: 24),
              const Text('時刻', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.access_time_rounded),
                label: Text(_time == null ? '時刻を選択' : _time!.format(context)),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _reasonController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '理由'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return '理由を入力してください';
                  return null;
                },
              ),
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
