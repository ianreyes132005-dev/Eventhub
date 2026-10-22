import 'registration_service.dart';

/// Signed links to check-in selfies. The `selfies` bucket is private, so a
/// link stops working after [RegistrationService.selfieLinkLifetime].
///
/// The app's Registrations tab stays open all day, so a link is renewed once
/// it's [renewAfter] old — before it breaks — and a new submission always
/// gets a new link: a re-taken selfie keeps the same file path, and the old
/// link would show the old photo from the image cache.
class SelfieLinks {
  SelfieLinks({
    Future<String> Function(String path)? sign,
    DateTime Function()? now,
  })  : _sign = sign ?? RegistrationService.getSelfieSignedUrl,
        _now = now ?? DateTime.now;

  /// Renewed this long after it was made — well inside the 1-hour lifetime.
  static const renewAfter = Duration(minutes: 45);

  final Future<String> Function(String path) _sign;
  final DateTime Function() _now;
  final Map<String, String> _urls = {};
  final Map<String, ({String path, DateTime at})> _made = {};

  /// The link to a registration's selfie, once one was made.
  String? operator [](String registrationId) => _urls[registrationId];

  /// Whether [registrationId] needs a (new) link for the selfie at [path]:
  /// none yet, a different file, or one that's getting old.
  bool needsLink(String registrationId, String path) {
    final made = _made[registrationId];
    return made == null ||
        made.path != path ||
        !_now().isBefore(made.at.add(renewAfter));
  }

  /// Makes links for the selfies in [paths] (registration id → storage path)
  /// that need one — every one of them with [fresh] (just submitted).
  /// Resolves to true when any link changed. A link that can't be made is
  /// left as it was.
  Future<bool> fetch(Map<String, String> paths, {bool fresh = false}) async {
    final due = {
      for (final e in paths.entries)
        if (e.value.isNotEmpty && (fresh || needsLink(e.key, e.value)))
          e.key: e.value,
    };
    if (due.isEmpty) return false;
    final at = _now(); // before asking: the link's hour starts about now
    final made = await Future.wait(due.entries.map((e) async {
      try {
        return (id: e.key, path: e.value, url: await _sign(e.value));
      } catch (_) {
        return null;
      }
    }));
    var changed = false;
    for (final m in made) {
      if (m == null) continue;
      _urls[m.id] = m.url;
      _made[m.id] = (path: m.path, at: at);
      changed = true;
    }
    return changed;
  }

  /// A working link right before the photo is shown (renewed if old).
  Future<String?> linkFor(String registrationId, String path) async {
    await fetch({registrationId: path});
    return _urls[registrationId];
  }

  void remove(String registrationId) {
    _urls.remove(registrationId);
    _made.remove(registrationId);
  }
}
