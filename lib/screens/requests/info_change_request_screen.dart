import 'package:flutter/material.dart';

import '../../models/leave_request.dart';
import '../../services/request_service.dart';
import '../../theme/app_theme.dart';

/// 6.4 登録情報変更申請(住所・電話番号・振込先口座)。承認後に反映される。
class InfoChangeRequestScreen extends StatefulWidget {
  const InfoChangeRequestScreen({super.key, required this.service});

  final RequestService service;

  @override
  State<InfoChangeRequestScreen> createState() => _InfoChangeRequestScreenState();
}

class _InfoChangeRequestScreenState extends State<InfoChangeRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newValueController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _branchNameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _accountHolderController = TextEditingController();

  late Future<({String? address, String? phone})> _currentContactFuture;

  InfoChangeField _field = InfoChangeField.address;
  String _accountType = bankAccountTypes.first;
  DateTime _effectiveDate = DateTime.now();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentContactFuture = widget.service.fetchMyCurrentContact();
  }

  @override
  void dispose() {
    _newValueController.dispose();
    _bankNameController.dispose();
    _branchNameController.dispose();
    _accountNumberController.dispose();
    _accountHolderController.dispose();
    super.dispose();
  }

  Future<void> _pickEffectiveDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveDate,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _effectiveDate = picked);
    }
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      await widget.service.submitInfoChangeRequest(
        effectiveDate: _effectiveDate,
        field: _field,
        newValue: _field == InfoChangeField.bankAccount ? null : _newValueController.text.trim(),
        bankName: _field == InfoChangeField.bankAccount ? _bankNameController.text.trim() : null,
        branchName:
            _field == InfoChangeField.bankAccount ? _branchNameController.text.trim() : null,
        accountType: _field == InfoChangeField.bankAccount ? _accountType : null,
        accountNumber:
            _field == InfoChangeField.bankAccount ? _accountNumberController.text.trim() : null,
        accountHolderNameKana:
            _field == InfoChangeField.bankAccount ? _accountHolderController.text.trim() : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登録情報変更を申請しました')),
      );
      Navigator.of(context).pop();
    } catch (_) {
      setState(() => _errorMessage = '申請に失敗しました。もう一度お試しください。');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildCurrentValueHint() {
    if (_field == InfoChangeField.bankAccount) return const SizedBox.shrink();
    return FutureBuilder<({String? address, String? phone})>(
      future: _currentContactFuture,
      builder: (context, snapshot) {
        final current = _field == InfoChangeField.address
            ? snapshot.data?.address
            : snapshot.data?.phone;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '現在の登録内容: ${current == null || current.isEmpty ? '未登録' : current}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        );
      },
    );
  }

  Widget _buildFieldForm() {
    if (_field == InfoChangeField.bankAccount) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _bankNameController,
            decoration: const InputDecoration(labelText: '銀行名'),
            validator: (v) => (v == null || v.trim().isEmpty) ? '銀行名を入力してください' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _branchNameController,
            decoration: const InputDecoration(labelText: '支店名'),
            validator: (v) => (v == null || v.trim().isEmpty) ? '支店名を入力してください' : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _accountType,
            decoration: const InputDecoration(labelText: '口座種別'),
            items: bankAccountTypes
                .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _accountType = value);
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _accountNumberController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '口座番号'),
            validator: (v) => (v == null || v.trim().isEmpty) ? '口座番号を入力してください' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _accountHolderController,
            decoration: const InputDecoration(labelText: '口座名義(カナ)'),
            validator: (v) => (v == null || v.trim().isEmpty) ? '口座名義を入力してください' : null,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCurrentValueHint(),
        TextFormField(
          controller: _newValueController,
          keyboardType:
              _field == InfoChangeField.phone ? TextInputType.phone : TextInputType.text,
          decoration: InputDecoration(labelText: '新しい${_field.label}'),
          validator: (v) => (v == null || v.trim().isEmpty) ? '入力してください' : null,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登録情報変更申請')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('変更する項目', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: InfoChangeField.values.map((field) {
                  final selected = _field == field;
                  return ChoiceChip(
                    label: Text(field.label),
                    selected: selected,
                    selectedColor: AppColors.skyBlue,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) => setState(() => _field = field),
                  );
                }).toList(),
              ),
              if (_field == InfoChangeField.bankAccount) ...[
                const SizedBox(height: 12),
                const Text(
                  '振込先口座の変更は労務管理者以上の承認が必要です',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
              const SizedBox(height: 24),
              _buildFieldForm(),
              const SizedBox(height: 24),
              const Text('適用日', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pickEffectiveDate,
                icon: const Icon(Icons.calendar_today_rounded),
                label: Text('${_effectiveDate.year}/${_effectiveDate.month}/${_effectiveDate.day}'),
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
                    : const Text('申請する'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
