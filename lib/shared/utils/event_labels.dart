import 'package:flutter/material.dart';

// Compact event date / time / status-colour labels shared by the organizer
// web Events table (event_table_cells.dart) and the app's event cards
// (organizer_events.dart), so both read the same.

const _kMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Oct 25".
String monthDayLabel(DateTime d) => '${_kMonths[d.month - 1]} ${d.day}';

/// "5:00 PM" today, otherwise "Oct 26, 5:00 PM".
String clockLabel(DateTime d) {
  final time = '${_h12(d.hour, d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
  return DateUtils.isSameDay(d, DateTime.now()) ? time : '${monthDayLabel(d)}, $time';
}

String _h12(int h, int m) => '${h % 12 == 0 ? 12 : h % 12}:${m.toString().padLeft(2, '0')}';

(int, int)? _hourMinute(String? t) {
  final p = (t ?? '').split(':');
  final h = int.tryParse(p[0]);
  final m = p.length > 1 ? int.tryParse(p[1]) : null;
  return h == null || m == null ? null : (h, m);
}

/// Compact time slot from "13:00:00"-style times: "1:00–4:00 PM",
/// "8:00 AM–5:00 PM". Empty when there's no start time.
String timeRangeLabel(String? from, String? to) {
  final a = _hourMinute(from);
  final b = _hourMinute(to);
  if (a == null) return '';
  String period(int h) => h < 12 ? 'AM' : 'PM';
  if (b == null) return '${_h12(a.$1, a.$2)} ${period(a.$1)}';
  return period(a.$1) == period(b.$1)
      ? '${_h12(a.$1, a.$2)}–${_h12(b.$1, b.$2)} ${period(b.$1)}'
      : '${_h12(a.$1, a.$2)} ${period(a.$1)}–${_h12(b.$1, b.$2)} ${period(b.$1)}';
}

/// "Oct 25"; multi-day: "Oct 25–27", "Oct 30 – Nov 2", "Dec 30 – Jan 2".
///
/// [withYear] (hover text): "Oct 25, 2026", "Oct 25–27, 2026",
/// "Oct 30 – Nov 2, 2026", "Dec 30, 2026 – Jan 2, 2027".
String dateRangeLabel(DateTime start, DateTime? end, {bool withYear = false}) {
  if (!withYear) {
    if (end == null || DateUtils.isSameDay(start, end)) return monthDayLabel(start);
    if (start.year == end.year && start.month == end.month) {
      return '${monthDayLabel(start)}–${end.day}';
    }
    return '${monthDayLabel(start)} – ${monthDayLabel(end)}';
  }
  String full(DateTime d) => '${monthDayLabel(d)}, ${d.year}';
  if (end == null || DateUtils.isSameDay(start, end)) return full(start);
  if (start.year == end.year && start.month == end.month) {
    return '${monthDayLabel(start)}–${end.day}, ${end.year}';
  }
  if (start.year == end.year) return '${monthDayLabel(start)} – ${full(end)}';
  return '${full(start)} – ${full(end)}';
}

/// Status text shifted toward black (light) or white (dark) so it reads on its
/// own tint — every status colour clears 5.7:1 this way.
Color readableStatusColor(Color c, bool dark) =>
    Color.lerp(c, dark ? Colors.white : Colors.black, dark ? 0.35 : 0.45)!;
