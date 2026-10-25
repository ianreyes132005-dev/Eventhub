import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/registration_service.dart';
import '../../../core/app_colors.dart';
import '../../../core/friendly_error.dart';
import '../../../shared/widgets/error_alert.dart';
import '../../../shared/widgets/web/swal.dart';

/// Why the camera screen closes on its own: the organizer's photo request
/// ended while it was open. Null while the request still stands
/// (photo_required).
String? selfieRequestEndedMessage(String? status,
    {String? rejectionReason, bool removed = false}) {
  if (removed) return 'The organizer removed your registration for this event.';
  switch (status) {
    case 'photo_required':
      return null;
    case 'rejected':
      final reason = rejectionReason?.trim() ?? '';
      return reason.isEmpty
          ? 'The organizer declined your registration, so no photo is needed.'
          : 'The organizer declined your registration, so no photo is needed.\n\nReason: $reason';
    case 'checked_in':
      return 'You’re already checked in — no photo is needed.';
    case 'photo_submitted':
      return 'Your check-in photo was already sent.';
    default:
      return 'The organizer withdrew the photo request. They’ll ask again if they need one.';
  }
}

/// Full-screen camera screen for the student to take a selfie during check-in.
/// Opened once the student allows the organizer's photo request
/// (askCheckInPhotoConsent), or from "Take selfie" / "Upload Attendance Photo".
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

  // Watches the request: if the organizer declines, checks the student in
  // or deletes the registration while the camera is open, say so and close
  // instead of letting Submit fail.
  RealtimeChannel? _channel;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _watchRequest();
  }

  @override
  void dispose() {
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    _controller?.dispose();
    super.dispose();
  }

  void _watchRequest() {
    final id = widget.registrationId;
    final client = Supabase.instance.client;
    _channel = client.channel('selfie-request-$id')
      ..on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(
          event: 'UPDATE',
          schema: 'public',
          table: 'registrations',
          filter: 'id=eq.$id',
        ),
        (payload, [_]) {
          final rec = (payload['new'] as Map?) ?? {};
          _requestChanged(rec['status'] as String?, rec['rejection_reason'] as String?);
        },
      )
      // Deletes can't be filtered, so check the id here.
      ..on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(event: 'DELETE', schema: 'public', table: 'registrations'),
        (payload, [_]) {
          if ((payload['old'] as Map?)?['id'] == id) {
            _requestChanged(null, null, removed: true);
          }
        },
      )
      ..subscribe();

    // The request may already have ended before the camera opened.
    client
        .from('registrations')
        .select('status, rejection_reason')
        .eq('id', id)
        .maybeSingle()
        .then((row) {
      if (row == null) {
        _requestChanged(null, null, removed: true);
      } else {
        _requestChanged(row['status'] as String?, row['rejection_reason'] as String?);
      }
    }).catchError((Object e) {
      debugPrint('Selfie request check failed: $e');
    });
  }

  Future<void> _requestChanged(String? status, String? reason,
      {bool removed = false}) async {
    // Our own upload flips the status to photo_submitted — not news.
    if (_closing || _uploading || !mounted) return;
    final message = selfieRequestEndedMessage(status,
        rejectionReason: reason, removed: removed);
    if (message == null) return;
    _closing = true;
    await Swal.fire(
      context,
      icon: SwalIcon.info,
      title: 'No photo needed',
      text: message,
      allowOutsideClick: false,
    );
    if (mounted) Navigator.of(context).pop(false);
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
      _controller = CameraController(cam, ResolutionPreset.medium, enableAudio: false);
      await _controller!.initialize();
      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      debugPrint('Selfie camera failed to start: $e');
      if (mounted) {
        setState(() => _error = friendlyError(e,
            fallback: 'The camera couldn’t be started. Close other apps that '
                'use the camera and try again.'));
      }
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
        showErrorAlert(context, e,
            title: 'Couldn’t take the photo', fallback: 'Please try again.');
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
        setState(() => _uploading = false);
        showErrorAlert(context, e, title: 'Couldn’t send your selfie');
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
