import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Check-in feedback — always paired with what the screen shows.
///
/// Organizer app scanner (the web portal has none): a vibration, no sound,
/// once EventHub has checked the ticket — not merely when the camera reads a
/// code:
///   • [accepted] one firm tap: valid ticket, now (or still) in check-in;
///   • [blocked]  two vibrations: unknown QR, check-in closed, already
///     checked in, rejected, or the check couldn't run.
/// Student app: [ticketScanned] a soft chime when their ticket is scanned.
///
/// The chime lives in assets/sounds/ and never pauses music playing on the device.
class ScanFeedback {
  ScanFeedback._();

  /// Statuses a scan can't move forward — the scanner signals these as blocked.
  static const _blockedStatuses = {'checked_in', 'rejected'};

  /// Whether a scanned registration with [status] counts as accepted.
  static bool isAccepted(String? status) => !_blockedStatuses.contains(status);

  /// The verdict for a ticket EventHub found, from its (updated) status.
  static Future<void> forStatus(String? status) =>
      isAccepted(status) ? accepted() : blocked();

  /// Valid ticket: one firm tap.
  static Future<void> accepted() => HapticFeedback.heavyImpact();

  /// Can't check in: two vibrations.
  static Future<void> blocked() async {
    HapticFeedback.vibrate();
    Future.delayed(const Duration(milliseconds: 160), HapticFeedback.vibrate);
  }

  static Future<AudioPlayer?>? _ticket;

  static Future<AudioPlayer?> get _ticketPlayer =>
      _ticket ??= _load('sounds/ticket_scanned.wav', _studentContext, 0.7);

  // Student: the notification volume, so a phone on silent stays silent.
  static final _studentContext = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.notificationEvent,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  /// Student's phone: their ticket was just scanned at the door.
  static Future<void> ticketScanned() async {
    HapticFeedback.mediumImpact();
    await _play(_ticketPlayer);
  }

  static Future<AudioPlayer?> _load(String asset, AudioContext context, double volume) async {
    try {
      final player = AudioPlayer();
      await player.setReleaseMode(ReleaseMode.stop);
      if (!kIsWeb) {
        await player.setAudioContext(context);
        // Android's low-latency mode plays short sounds right away.
        if (defaultTargetPlatform == TargetPlatform.android) {
          await player.setPlayerMode(PlayerMode.lowLatency);
        }
      }
      await player.setVolume(volume);
      await player.setSource(AssetSource(asset));
      return player;
    } catch (e) {
      debugPrint('ScanFeedback: could not load $asset: $e');
      return null;
    }
  }

  static Future<void> _play(Future<AudioPlayer?> player) async {
    try {
      final p = await player;
      if (p == null) return;
      await p.stop(); // restart if it's still playing
      await p.resume();
    } catch (e) {
      debugPrint('ScanFeedback: could not play a sound: $e');
    }
  }
}
