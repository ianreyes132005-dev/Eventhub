import 'package:flutter/foundation.dart';
import '../event_audience.dart' show GradeCount;
import 'supabase_service.dart';

/// Event capacity = the number of active students who can register.
///
/// Each student registers once, so the most registrations an event can have
/// is the number of active students in its group — every student
/// ([activeStudents]) unless the event is only for some grades or strands
/// ([gradeCounts], added up by EventAudience.capacity). Adding (or
/// reactivating) students raises the capacity with them. Organizers don't
/// set a number. See supabase/migrations/202610180011_capacity_from_students.sql
/// and 202611030001_event_audience.sql.
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

  static List<GradeCount>?          _counts;
  static DateTime?                  _countsAt;
  static Future<List<GradeCount>?>? _countsInFlight;

  /// The last breakdown read, if any.
  static List<GradeCount>? get cachedCounts => _counts;
  /// Active students per grade and strand (active_student_counts()), for
  /// events open to only some of them. Cached for a minute, one request at a
  /// time; null when it can't be read (before migration 202611030001 is
  /// run), so callers show those events' registrations without a limit.
  static Future<List<GradeCount>?> gradeCounts({bool refresh = false}) {
    final fresh = _countsAt != null && DateTime.now().difference(_countsAt!) < _ttl;
    if (!refresh && fresh) return Future.value(_counts);
    return _countsInFlight ??= _fetchCounts().whenComplete(() => _countsInFlight = null);
  }

  static Future<List<GradeCount>?> _fetchCounts() async {
    try {
      final rows = await SupabaseService.client.rpc('active_student_counts');
      _counts = [
        for (final r in rows as List)
          (
            grade: (r['grade'] as num?)?.toInt(),
            strand: r['strand'] as String?,
            students: (r['students'] as num?)?.toInt() ?? 0,
          ),
      ];
      _countsAt = DateTime.now();
      return _counts;
    } catch (e) {
      debugPrint('active_student_counts unavailable: $e');
      return _counts;   // keep the last known breakdown
    }
  }
}
