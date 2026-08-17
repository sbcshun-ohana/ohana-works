import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 招待QRの読み取り画面。園で発行された招待QR(中身=招待コード)を読み取り、
/// 読み取れたコード文字列を pop で返す。
class InvitationQrScanScreen extends StatefulWidget {
  const InvitationQrScanScreen({super.key});

  @override
  State<InvitationQrScanScreen> createState() => _InvitationQrScanScreenState();
}

class _InvitationQrScanScreenState extends State<InvitationQrScanScreen> {
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null || value.trim().isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(value.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('招待QRを読み取る')),
      body: Stack(
        children: [
          MobileScanner(onDetect: _onDetect),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '園から渡された招待QRコードを枠内に写してください',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
