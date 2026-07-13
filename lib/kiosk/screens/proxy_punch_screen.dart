import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../models/paired_device.dart';
import '../punch_type_display.dart';
import '../services/kiosk_punch_service.dart';
import 'punch_success_screen.dart';

const _punchTypes = ['clock_in', 'break_start', 'break_end', 'clock_out'];

/// 9.3章: 管理者コード(職員ごとの個別PIN)入力による代理打刻。
/// 管理者コード保持者の立会いを前提とする。
class ProxyPunchScreen extends StatefulWidget {
  const ProxyPunchScreen({
    super.key,
    required this.device,
    required this.punchService,
  });

  final PairedDevice device;
  final KioskPunchService punchService;

  @override
  State<ProxyPunchScreen> createState() => _ProxyPunchScreenState();
}

class _ProxyPunchScreenState extends State<ProxyPunchScreen> {
  final _employeeNumberController = TextEditingController();
  final _pinController = TextEditingController();
  String _selectedPunchType = _punchTypes.first;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _employeeNumberController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final employeeNumber = _employeeNumberController.text.trim();
    final pin = _pinController.text.trim();
    if (employeeNumber.isEmpty || pin.isEmpty) {
      setState(() => _errorMessage = '職員番号と管理者コードを入力してください');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final result = await widget.punchService.proxyPunch(
        employeeNumber: employeeNumber,
        adminPin: pin,
        punchType: _selectedPunchType,
        deviceId: widget.device.deviceId,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(builder: (_) => PunchSuccessScreen(result: result)),
      );
    } on KioskPunchException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('代理打刻')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '管理者コード保持者の立会いのもとで実施してください',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _employeeNumberController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: '対象職員の職員番号',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _pinController,
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: '管理者コード(PIN)',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '打刻種別',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: _punchTypes.map((type) {
                            final display = PunchTypeDisplay.of(type);
                            final selected = _selectedPunchType == type;
                            return ChoiceChip(
                              label: Text(display.label),
                              selected: selected,
                              selectedColor: display.color,
                              labelStyle: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                              onSelected: (_) {
                                setState(() => _selectedPunchType = type);
                              },
                            );
                          }).toList(),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ],
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _isSubmitting ? null : _submit,
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('代理打刻を記録する'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
