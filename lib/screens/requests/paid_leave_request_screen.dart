import 'package:flutter/material.dart';

import '../../models/leave_request.dart';
import '../../services/request_service.dart';
import '../../theme/app_theme.dart';

/// 15.1 有給休暇申請。
class PaidLeaveRequestScreen extends StatefulWidget {
  const PaidLeaveRequestScreen({super.key, required this.service});

  final RequestService service;

  @override
  State<PaidLeaveRequestScreen> createState() => _PaidLeaveRequestScreenState();
}

class _PaidLeaveRequestScreenState extends State<PaidLeaveRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hoursController = TextEditingController();

  late Future<LeaveBalance> _balanceFuture;
  DateTime? _targetDate;
  LeaveUsageUnit _usageUnit = LeaveUsageUnit.day;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _balanceFuture = widget.service.fetchMyLeaveBalance();
  }

  @override
  void dispose() {
    _hoursController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? now,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _targetDate = picked);
    }
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    final targetDate = _targetDate;
    if (targetDate == null) {
      setState(() => _errorMessage = '対象日を選択してください');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final hasShift = await widget.service.hasShiftOn(targetDate);
      if (!hasShift) {
        setState(() => _errorMessage = 'シフトが登録されている日のみ申請できます');
        return;
      }

      double? hours;
      if (_usageUnit == LeaveUsageUnit.hour) {
        hours = double.parse(_hoursController.text);
        final hoursPerDay = (await _balanceFuture).hoursPerDay;
        final usedHours = await widget.service.fetchHourlyUsageInLatestGrantPeriod();
        if (usedHours + hours > hoursPerDay * 5) {
          setState(() => _errorMessage = '時間単位年休は年5日相当が上限です');
          return;
        }
      }

      await widget.service.submitPaidLeaveRequest(
        targetDate: targetDate,
        usageUnit: _usageUnit,
        hours: hours,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('有給休暇を申請しました')),
      );
      Navigator.of(context).pop();
    } catch (_) {
      setState(() => _errorMessage = '申請に失敗しました。もう一度お試しください。');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('有給休暇申請')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FutureBuilder<LeaveBalance>(
                future: _balanceFuture,
                builder: (context, snapshot) {
                  final balance = snapshot.data;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          const Icon(Icons.beach_access_rounded, color: AppColors.leafGreen),
                          const SizedBox(width: 12),
                          Text(
                            balance == null ? '残数を確認中…' : '残数 ${balance.display}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
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
              const SizedBox(height: 24),
              const Text('使用単位', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: LeaveUsageUnit.values.map((unit) {
                  final selected = _usageUnit == unit;
                  return ChoiceChip(
                    label: Text(unit.label),
                    selected: selected,
                    selectedColor: AppColors.leafGreen,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) {
                      setState(() => _usageUnit = unit);
                    },
                  );
                }).toList(),
              ),
              if (_usageUnit == LeaveUsageUnit.hour) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _hoursController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '時間数'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '時間数を入力してください';
                    }
                    final parsed = double.tryParse(value);
                    if (parsed == null || parsed <= 0) {
                      return '正しい時間数を入力してください';
                    }
                    return null;
                  },
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
                    : const Text('申請する'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
