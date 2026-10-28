import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eventhub/core/app_colors.dart';
import 'package:eventhub/features/organizer/web/event_table_cells.dart';
import 'package:eventhub/features/organizer/web/web_shared.dart';

// Compact date / time / status labels shared by the organizer web Events
// table and the app's event cards.
void main() {
  group('timeRangeLabel', () {
    test('same half of the day shares one AM/PM', () {
      expect(timeRangeLabel('13:00:00', '16:00:00'), '1:00–4:00 PM');
      expect(timeRangeLabel('10:00', '11:30'), '10:00–11:30 AM');
    });
    test('across noon keeps both', () {
      expect(timeRangeLabel('08:00:00', '17:00:00'), '8:00 AM–5:00 PM');
    });
    test('noon and midnight read as 12', () {
      expect(timeRangeLabel('00:15:00', '12:00:00'), '12:15 AM–12:00 PM');
    });
    test('start only, or nothing', () {
      expect(timeRangeLabel('09:05:00', null), '9:05 AM');
      expect(timeRangeLabel(null, '10:00:00'), '');
    });
  });

  group('dateRangeLabel', () {
    test('no year in the list', () {
      expect(dateRangeLabel(DateTime(2026, 10, 25), DateTime(2026, 10, 25)), 'Oct 25');
      expect(dateRangeLabel(DateTime(2026, 10, 25), null), 'Oct 25');
      expect(dateRangeLabel(DateTime(2026, 10, 25), DateTime(2026, 10, 27)), 'Oct 25–27');
      expect(dateRangeLabel(DateTime(2026, 10, 30), DateTime(2026, 11, 2)), 'Oct 30 – Nov 2');
      expect(dateRangeLabel(DateTime(2026, 12, 30), DateTime(2027, 1, 2)), 'Dec 30 – Jan 2');
    });
    test('with the year for the hover text', () {
      String full(DateTime a, DateTime? b) => dateRangeLabel(a, b, withYear: true);
      expect(full(DateTime(2026, 10, 25), null), 'Oct 25, 2026');
      expect(full(DateTime(2026, 10, 25), DateTime(2026, 10, 27)), 'Oct 25–27, 2026');
      expect(full(DateTime(2026, 10, 30), DateTime(2026, 11, 2)), 'Oct 30 – Nov 2, 2026');
      expect(full(DateTime(2026, 12, 30), DateTime(2027, 1, 2)), 'Dec 30, 2026 – Jan 2, 2027');
    });
  });

  group('organizerEventStatus (web pill and app chip)', () {
    Map<String, dynamic> event(String approval, {String date = '2099-01-10', String? extra}) => {
      'approval_status': approval,
      'event_date': date,
      'start_time': '09:00:00',
      'end_time': '12:00:00',
      'event_status': extra == 'cancelled' ? 'cancelled' : 'upcoming',
      if (extra == 'archived') 'archived_at': '2026-10-01T00:00:00Z',
    };
    String label(Map<String, dynamic> e) => organizerEventStatus(e).label;

    test('review state wins over the schedule', () {
      expect(label(event('pending')), 'Pending review');
      expect(label(event('rejected')), 'Rejected');
      // Nobody reviewed it before it started: it counts as rejected.
      expect(label(event('pending', date: '2020-01-10')), 'Rejected');
    });
    test('approved events show where they are in the schedule', () {
      expect(label(event('approved')), 'Upcoming');
      expect(label(event('approved', date: '2020-01-10')), 'Ended');
      expect(label(event('approved', extra: 'cancelled')), 'Cancelled');
    });
    test('archived comes first', () {
      expect(label(event('rejected', extra: 'archived')), 'Archived');
      expect(label(event('approved', date: '2020-01-10', extra: 'archived')), 'Archived');
    });
  });

  group('organizerEventFilterOf (the Status filter, app and web)', () {
    Map<String, dynamic> event(String approval, {String date = '2099-01-10', String? extra}) => {
      'approval_status': approval,
      'event_date': date,
      'start_time': '09:00:00',
      'end_time': '12:00:00',
      'event_status': extra == 'cancelled' ? 'cancelled' : 'upcoming',
      if (extra == 'archived') 'archived_at': '2026-10-01T00:00:00Z',
    };

    test('waiting for the admin is its own filter, not Upcoming', () {
      expect(organizerEventFilterOf(event('pending')), 'Pending review');
      expect(organizerEventFilterOf(event('approved')), 'Upcoming');
    });
    test('rejected and archived come first', () {
      expect(organizerEventFilterOf(event('rejected')), 'Rejected');
      // Nobody reviewed it before it started: it counts as rejected.
      expect(organizerEventFilterOf(event('pending', date: '2020-01-10')), 'Rejected');
      expect(organizerEventFilterOf(event('approved', extra: 'archived')), 'Archived');
    });
    test('approved events follow the schedule', () {
      expect(organizerEventFilterOf(event('approved'), now: DateTime(2099, 1, 10, 10)), 'Ongoing');
      // Ended, check-in still open until 2 PM: under Ended.
      expect(organizerEventFilterOf(event('approved'), now: DateTime(2099, 1, 10, 13)), 'Ended');
      expect(organizerEventFilterOf(event('approved', extra: 'cancelled')), 'Cancelled');
    });
    test('each event is under the filter its pill names', () {
      for (final e in [event('pending'), event('rejected'), event('approved'),
          event('approved', extra: 'cancelled'), event('approved', extra: 'archived')]) {
        expect(organizerEventFilterOf(e), organizerEventStatus(e).label);
      }
    });
  });

  test('app chip text clears 4.5:1 on the card, light and dark', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
    }
    const colors = [
      Color(0xFF3B82F6), Color(0xFF10B981), Color(0xFF6B7280), Color(0xFFEF4444),
      Color(0xFFF59E0B), kCheckInOpenColor, Color(0xFF6366F1),
    ];
    for (final dark in [false, true]) {
      for (final c in colors) {
        expect(contrast(readableStatusColor(c, dark), AppTk(dark).card),
            greaterThanOrEqualTo(4.5), reason: '$c in ${dark ? 'dark' : 'light'} mode');
      }
    }
  });

  test('status text clears 4.5:1 on its own tint, light and dark', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
    }
    const colors = {
      'upcoming': Color(0xFF3B82F6), 'ongoing': Color(0xFF10B981),
      'ended': Color(0xFF6B7280), 'red': Color(0xFFEF4444),
      'amber': Color(0xFFF59E0B), 'check-in': kCheckInOpenColor,
      'archived': Color(0xFF6366F1),
    };
    for (final dark in [false, true]) {
      final card = WebTk(dark).card;
      for (final entry in colors.entries) {
        final c  = entry.value;
        final bg = Color.alphaBlend(c.withValues(alpha: dark ? 0.16 : 0.10), card);
        expect(contrast(readableStatusColor(c, dark), bg), greaterThanOrEqualTo(4.5),
            reason: '${entry.key} in ${dark ? 'dark' : 'light'} mode');
      }
    }
  });
}
