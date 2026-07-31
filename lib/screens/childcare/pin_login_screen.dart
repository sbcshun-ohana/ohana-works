import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/role_display.dart';
import '../../kiosk/models/paired_device.dart';
import '../../services/pin_auth_service.dart';
import '../../theme/app_theme.dart';

/// 要件3: 登録端末の職員ピッカー+PIN簡易ログイン画面。
/// 氏名タップ → 6桁PIN → pin-login(サーバ検証)→ verifyOTP でセッション確立。
/// 「メール+パスワードでログイン」への切替導線も置く。
class PinLoginScreen extends StatefulWidget {
  const PinLoginScreen({
    super.key,
    required this.device,
    required this.onUsePassword,
  });

  final PairedDevice device;
  final VoidCallback onUsePassword;

  @override
  State<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends State<PinLoginScreen> {
  final _service = PinAuthService(Supabase.instance.client);
  late Future<List<PinPickerStaff>> _pickerFuture;
  PinPickerStaff? _selected;
  String _pin = '';
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pickerFuture = _service.fetchPicker(widget.device.deviceId);
  }

  void _select(PinPickerStaff staff) {
    setState(() {
      _selected = staff;
      _pin = '';
      _error = null;
    });
  }

  void _backToPicker() {
    setState(() {
      _selected = null;
      _pin = '';
      _error = null;
    });
  }

  Future<void> _onDigit(String d) async {
    if (_submitting || _pin.length >= 6) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length == 6) await _submit();
  }

  void _onDelete() {
    if (_submitting || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    final staff = _selected;
    if (staff == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _service.loginWithPin(
        deviceId: widget.device.deviceId,
        employeeId: staff.employeeId,
        pin: _pin,
      );
      // 成功時は auth 状態変化で上位が保育業務メニューへ遷移する。
    } on PinAuthException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _pin = '';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'ログインに失敗しました。もう一度お試しください。';
          _pin = '';
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.device.officeName ?? "保育業務"} — ログイン'),
        actions: [
          TextButton(
            onPressed: widget.onUsePassword,
            child: const Text('メール+パスワード', style: TextStyle(color: AppColors.skyBlue)),
          ),
        ],
      ),
      body: _selected == null ? _buildPicker() : _buildPinPad(),
    );
  }

  Widget _buildPicker() {
    return FutureBuilder<List<PinPickerStaff>>(
      future: _pickerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('職員一覧を取得できませんでした。\nメール+パスワードでログインしてください。',
                  textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
            ),
          );
        }
        final staff = snapshot.data ?? const [];
        if (staff.isEmpty) {
          return const Center(child: Text('この端末の施設に職員が登録されていません'));
        }
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('自分の名前をタップしてください', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220, childAspectRatio: 2.4, crossAxisSpacing: 12, mainAxisSpacing: 12),
                itemCount: staff.length,
                itemBuilder: (context, i) {
                  final s = staff[i];
                  return Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _select(s),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text(roleDisplayName(s.roleCode),
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            if (!s.hasPin)
                              const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Text('PIN未設定',
                                    style: TextStyle(fontSize: 11, color: AppColors.warmOrange)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPinPad() {
    final staff = _selected!;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _submitting ? null : _backToPicker,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('職員選択に戻る'),
              ),
            ),
            Text(staff.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            Text(staff.hasPin ? '6桁のPINを入力' : 'PIN未設定です。メール+パスワードでログイン後に設定してください',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (i) {
                final filled = i < _pin.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 16, height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? AppColors.skyBlue : Colors.transparent,
                    border: Border.all(color: AppColors.skyBlue, width: 2),
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            SizedBox(height: 24, child: _submitting
                ? const CircularProgressIndicator(strokeWidth: 2)
                : Text(_error ?? '', style: const TextStyle(color: AppColors.punchClockOut, fontSize: 13))),
            const SizedBox(height: 8),
            _buildKeypad(),
          ],
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    Widget key(String label, {VoidCallback? onTap, IconData? icon}) => Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: 72, height: 64,
            child: OutlinedButton(
              onPressed: onTap,
              child: icon != null ? Icon(icon) : Text(label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            ),
          ),
        );
    return Column(
      children: [
        for (final row in [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']])
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (final d in row) key(d, onTap: () => _onDigit(d))]),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(width: 88),
          key('0', onTap: () => _onDigit('0')),
          key('', icon: Icons.backspace_outlined, onTap: _onDelete),
        ]),
      ],
    );
  }
}
