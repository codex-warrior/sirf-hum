import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sirf_hum/design_system/design_system.dart';
import 'package:sirf_hum/features/verification/application/verification_controller.dart';

/// [QrCodeScanner] over `mobile_scanner` (D-130). Opens the back camera on
/// a pushed page, reads QR codes only, on the device (the frames never
/// leave the phone), and returns the first code's text. Imported only by
/// this file; wired in `main.dart` on Android, never on web.
class CameraQrCodeScanner implements QrCodeScanner {
  const CameraQrCodeScanner();

  @override
  Future<String?> scan(BuildContext context) => Navigator.of(
    context,
  ).push<String>(MaterialPageRoute(builder: (_) => const _ScanPage()));
}

class _ScanPage extends StatefulWidget {
  const _ScanPage();

  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  var _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final text = b.rawValue;
      if (text != null) {
        _done = true;
        Navigator.of(context).pop(text);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan their code')),
    body: Column(
      children: [
        Expanded(
          child: MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => const Padding(
              padding: EdgeInsets.all(Spacing.xl),
              child: ErrorState(
                title: "The camera isn't available",
                message:
                    'Allow Sirf Hum to use the camera, or compare the numbers '
                    'instead.',
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(Spacing.lg),
          child: Notice(
            icon: Icons.qr_code_scanner,
            message: 'Point the camera at the code on their phone.',
          ),
        ),
      ],
    ),
  );
}
