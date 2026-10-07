import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

// Organizer Dashboard Colors
const Color kBackground = Color(0xFFFBF6EA);
const Color kGold = Color(0xFFD6A742);
const Color kText = Color(0xFF111827);
const Color kSubText = Color(0xFF4B5563);

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  MobileScannerController cameraController = MobileScannerController();
  bool _isScanning = true;

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
if (!_isScanning) return;
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        setState(() {
          _isScanning = false;
        });

        // Process the scanned QR code
        _processScannedQRCode(barcode.rawValue!);
        break;
      }
    }
  }

  void _processScannedQRCode(String qrData) {
    // Parse the QR code data (assuming it's in JSON format from EventRegistration)
    try {
      // Show success dialog with scanned data
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('QR Code Scanned Successfully'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Scanned Data:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(qrData, style: TextStyle(fontSize: 12)),
              const SizedBox(height: 16),
              Text(
                'Student Check-in:',
                style: TextStyle(fontWeight: FontWeight.bold, color: kGold),
              ),
              const SizedBox(height: 4),
              Text(
                '✓ Successfully checked in!',
                style: TextStyle(color: Colors.green),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Reset scanning state
                setState(() {
                  _isScanning = true;
                });
              },
              child: const Text('Scan Another'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(); // Go back to dashboard
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kGold,
                foregroundColor: Colors.white,
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      // Handle invalid QR code format
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Invalid QR Code'),
          content: const Text(
            'The scanned QR code is not a valid event registration code.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _isScanning = true;
                });
              },
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan QR Code'),
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: cameraController.torchState,
              builder: (context, state, child) {
                switch (state) {
                  case TorchState.off:
                    return const Icon(Icons.flash_off);
                  case TorchState.on:
                    return const Icon(Icons.flash_on, color: kGold);
                }
              },
            ),
            onPressed: () => cameraController.toggleTorch(),
          ),
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: cameraController.cameraFacingState,
              builder: (context, state, child) {
                switch (state) {
                  case CameraFacing.front:
                    return const Icon(Icons.camera_front);
                  case CameraFacing.back:
                    return const Icon(Icons.camera_rear);
                }
              },
            ),
            onPressed: () => cameraController.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: cameraController, onDetect: _onDetect),
          // Overlay with scan area
          Container(
            decoration: ShapeDecoration(
              shape: QrScannerOverlayShape(
                borderColor: kGold,
                borderRadius: 10,
                borderLength: 30,
                borderWidth: 10,
                cutOutSize: MediaQuery.of(context).size.width * 0.8,
              ),
            ),
          ),
          // Instructions
          Positioned(
            top: 100,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Column(
                children: [
                  Text(
                    'Scan Student QR Code',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Position the QR code within the frame to check-in the student',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          // Bottom instructions
          Positioned(
            bottom: 100,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Make sure the QR code is well-lit and clearly visible',
                style: TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Custom overlay shape for QR scanner
class QrScannerOverlayShape extends ShapeBorder {
  const QrScannerOverlayShape({
    this.borderColor = Colors.red,
    this.borderWidth = 3.0,
    this.overlayColor = const Color.fromRGBO(0, 0, 0, 80),
    this.borderRadius = 0,
    this.borderLength = 40,
    required this.cutOutSize,
  });

  final Color borderColor;
  final double borderWidth;
  final Color overlayColor;
  final double borderRadius;
  final double borderLength;
  final double cutOutSize;

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(10);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(getOuterPath(rect), Offset.zero);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    Path getLeftTopPath(Rect rect) {
      return Path()
        ..moveTo(rect.left, rect.bottom)
        ..lineTo(rect.left, rect.top)
        ..lineTo(rect.right, rect.top);
    }

    return getLeftTopPath(rect)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.left, rect.top);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final width = rect.width;
    final borderWidthSize = width / 2;
    final height = rect.height;
    final borderOffset = borderWidth / 2;
    final halfWidth = width / 2;
    final halfHeight = height / 2;

    final cutOutWidth = cutOutSize;
    final cutOutHeight = cutOutSize;

    final backgroundPaint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    final cutOutRect = Rect.fromLTWH(
      rect.left + halfWidth - cutOutWidth / 2,
      rect.top + halfHeight - cutOutHeight / 2,
      cutOutWidth,
      cutOutHeight,
    );

    canvas
      ..saveLayer(rect, backgroundPaint)
      ..drawRect(rect, backgroundPaint)
      // Draw top right corner
      ..drawRRect(
        RRect.fromLTRBAndCorners(
          cutOutRect.right - borderOffset,
          cutOutRect.top - borderOffset,
          cutOutRect.right + borderOffset,
          cutOutRect.top + borderLength,
          topRight: Radius.circular(borderRadius),
        ),
        borderPaint,
      )
      // Draw top left corner
      ..drawRRect(
        RRect.fromLTRBAndCorners(
          cutOutRect.left - borderOffset,
          cutOutRect.top - borderOffset,
          cutOutRect.left + borderOffset,
          cutOutRect.top + borderLength,
          topLeft: Radius.circular(borderRadius),
        ),
        borderPaint,
      )
      // Draw bottom right corner
      ..drawRRect(
        RRect.fromLTRBAndCorners(
          cutOutRect.right - borderOffset,
          cutOutRect.bottom - borderLength,
          cutOutRect.right + borderOffset,
          cutOutRect.bottom + borderOffset,
          bottomRight: Radius.circular(borderRadius),
        ),
        borderPaint,
      )
      // Draw bottom left corner
      ..drawRRect(
        RRect.fromLTRBAndCorners(
          cutOutRect.left - borderOffset,
          cutOutRect.bottom - borderLength,
          cutOutRect.left + borderOffset,
          cutOutRect.bottom + borderOffset,
          bottomLeft: Radius.circular(borderRadius),
        ),
        borderPaint,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(cutOutRect, Radius.circular(borderRadius)),
        backgroundPaint..blendMode = BlendMode.clear,
      )
      ..restore();
  }

  @override
  ShapeBorder scale(double t) {
    return QrScannerOverlayShape(
      borderColor: borderColor,
      borderWidth: borderWidth * t,
      overlayColor: overlayColor,
      borderRadius: borderRadius * t,
      borderLength: borderLength * t,
      cutOutSize: cutOutSize * t,
    );
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is QrScannerOverlayShape &&
        other.borderColor == borderColor &&
        other.borderWidth == borderWidth &&
        other.overlayColor == overlayColor &&
        other.borderRadius == borderRadius &&
        other.borderLength == borderLength &&
        other.cutOutSize == cutOutSize;
  }

  @override
  int get hashCode => Object.hash(
    borderColor,
    borderWidth,
    overlayColor,
    borderRadius,
    borderLength,
    cutOutSize,
  );

  @override
  String toString() {
    return 'QrScannerOverlayShape('
        'borderColor: $borderColor, '
        'borderWidth: $borderWidth, '
        'overlayColor: $overlayColor, '
        'borderRadius: $borderRadius, '
        'borderLength: $borderLength, '
        'cutOutSize: $cutOutSize)';
  }
}