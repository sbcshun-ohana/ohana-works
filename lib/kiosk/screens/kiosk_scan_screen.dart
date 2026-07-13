import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../models/paired_device.dart';
import '../services/kiosk_punch_service.dart';
import 'proxy_punch_screen.dart';
import 'punch_confirm_screen.dart';

/// 10章: QR読取(アイドル画面)。
/// その日の最初の読取=出勤 等の自動判定は resolve-qr-punch(サーバー側)が行う。
class KioskScanScreen extends StatefulWidget {
  const KioskScanScreen({super.key, required this.device});

  final PairedDevice device;

  @override
  State<KioskScanScreen> createState() => _KioskScanScreenState();
}

class _KioskScanScreenState extends State<KioskScanScreen> {
  final _controller = MobileScannerController();
  final _punchService = KioskPunchService(Supabase.instance.client);

  bool _isProcessing = false;
  String? _statusMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final token = capture.barcodes.firstOrNull?.rawValue;
    if (token == null || token.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = null;
    });
    await _controller.stop();

    try {
      final resolution = await _punchService.resolveQrPunch(
        token: token,
        deviceId: widget.device.deviceId,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PunchConfirmScreen(
            resolution: resolution,
            device: widget.device,
            punchService: _punchService,
          ),
        ),
      );
    } on KioskPunchException catch (e) {
      setState(() => _statusMessage = e.message);
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
        await _controller.start();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          _buildOverlay(context),
          if (_isProcessing)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          Positioned(
            right: 24,
            bottom: 24,
            child: FloatingActionButton.extended(
              backgroundColor: AppColors.warmOrange,
              icon: const Icon(Icons.badge_outlined),
              label: const Text('代理打刻'),
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => ProxyPunchScreen(
                      device: widget.device,
                      punchService: _punchService,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 32),
        child: Column(
          children: [
            const Text(
              'QRコードをかざしてください',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (widget.device.officeName != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  widget.device.officeName!,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
            if (_statusMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.punchError,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _statusMessage!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
