import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/services/registration_service.dart';
import '../../../core/app_colors.dart';

/// Full-screen camera screen for the student to take a selfie during check-in.
/// Opened automatically when the organizer clicks "Confirm" on the scan screen.
class SelfieScreen extends StatefulWidget {
  final String registrationId;

  const SelfieScreen({required this.registrationId, super.key});

  @override
  State<SelfieScreen> createState() => _SelfieScreenState();
}

class _SelfieScreenState extends State<SelfieScreen> {
  CameraController? _controller;
  bool        _cameraReady   = false;
  bool        _uploading     = false;
  XFile?      _captured;
  Uint8List?  _capturedBytes;
  String?     _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final status = await Permission.camera.request();
      if (status.isPermanentlyDenied) {
        setState(() => _error =
            'Camera access is permanently denied. '
            'Please enable it in your device Settings.');
        return;
      }
      if (status.isDenied) {
        setState(() => _error = 'Camera permission is required to take a selfie.');
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera found on this device.');
        return;
      }
      // Prefer front camera for a selfie; fall back to the first available.
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _controller = CameraController(cam, ResolutionPreset.medium);
      await _controller!.initialize();
      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _snap() async {
    if (_controller == null || !_cameraReady) return;
    try {
      final file  = await _controller!.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted) setState(() { _captured = file; _capturedBytes = bytes; });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not capture photo: $e')),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (_captured == null || _capturedBytes == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = _capturedBytes!;
      await RegistrationService.uploadSelfie(
        registrationId: widget.registrationId,
        imageBytes: bytes,
      );
      if (mounted) {
        HapticFeedback.heavyImpact();
        // Capture the messenger before pop() detaches this widget's context.
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop(true);
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Selfie submitted! The organizer will check you in shortly.',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'Take a Selfie',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _uploading ? null : () => Navigator.of(context).pop(false),
        ),
      ),
      body: Column(
        children: [
          // Instruction banner
          Container(
            width: double.infinity,
            color: kGold,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            child: const Text(
              'Your organizer needs a selfie to verify your attendance at this event.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),

          // Camera / preview area
          Expanded(child: _buildViewfinder()),

          // Controls
          Container(
            color: Colors.black,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
            child: _captured == null ? _buildSnapButton() : _buildActions(),
          ),
        ],
      ),
    );
  }

  Widget _buildViewfinder() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontFamily: 'Poppins'),
          ),
        ),
      );
    }
    if (_captured != null) {
      return _capturedBytes != null
          ? Image.memory(_capturedBytes!, fit: BoxFit.contain)
          : const Center(child: CircularProgressIndicator(color: kGold));
    }
    if (!_cameraReady || _controller == null) {
      return const Center(child: CircularProgressIndicator(color: kGold));
    }
    return CameraPreview(_controller!);
  }

  Widget _buildSnapButton() {
    return Center(
      child: GestureDetector(
        onTap: _snap,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: Container(
            margin: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _uploading
                ? null
                : () => setState(() { _captured = null; _capturedBytes = null; }),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white70),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Retake',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _uploading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: kGold,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _uploading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Text(
                    'Submit',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
