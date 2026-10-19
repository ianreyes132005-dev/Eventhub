import 'package:flutter/foundation.dart';
import 'supabase_service.dart';

/// Event capacity = the number of active students.
///
/// Every student can register for every event, so the most registrations an
/// event can have is the school's student count — 200 active students means
/// 200 spots, and adding (or reactivating) students raises every event's
/// capacity with them. Organizers don't set a capacity. See
/// supabase/migrations/202610180011_capacity_from_students.sql.
class StudentCountService {
  StudentCountService._();

  static const _ttl = Duration(minutes: 1);

  static int?           _value;
  static DateTime?      _fetchedAt;
  static Future<int?>?  _inFlight;

  /// The last number read, if any.
  static int? get cached => _value;

  /// Active students right now (cached for a minute; one request at a time).
  /// Null when it can't be read — e.g. before the migration is run — so
  /// callers show the registration count without a limit.
  static Future<int?> activeStudents({bool refresh = false}) {
    final fresh = _fetchedAt != null && DateTime.now().difference(_fetchedAt!) < _ttl;
    if (!refresh && fresh) return Future.value(_value);
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  static Future<int?> _fetch() async {
    try {
      final res = await SupabaseService.client.rpc('active_student_count');
      final n = res is num ? res.toInt() : int.tryParse('$res');
      _value     = n != null && n > 0 ? n : null;
      _fetchedAt = DateTime.now();
      return _value;
    } catch (e) {
      debugPrint('active_student_count unavailable: $e');
      return _value;   // keep showing the last known number
    }
  }
}
