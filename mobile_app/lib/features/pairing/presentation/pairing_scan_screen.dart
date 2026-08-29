import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../domain/pairing_models.dart';

/// Scans a pairing QR code and hands the parsed [ParsedPairingLink] back to
/// the caller via [onScanned]. Redemption itself (calling
/// `PairingRepository.redeemInvite`, including the TOFU check) happens
/// outside this widget - it only owns the camera/scan concern.
class PairingScanScreen extends StatefulWidget {
  const PairingScanScreen({super.key, required this.onScanned});

  final void Function(ParsedPairingLink link) onScanned;

  @override
  State<PairingScanScreen> createState() => _PairingScanScreenState();
}

class _PairingScanScreenState extends State<PairingScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final uri = Uri.tryParse(raw);
      if (uri == null) continue;
      final link = PairingInvite.tryParse(uri);
      if (link != null) {
        _handled = true;
        widget.onScanned(link);
        return;
      }
    }
    setState(() => _error = 'QR-Code enthält keinen gültigen PhotoFrame-Einladungslink.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Einladung scannen')),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          if (_error != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 32,
              child: Material(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
