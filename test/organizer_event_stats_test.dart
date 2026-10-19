import 'package:flutter_test/flutter_test.dart';
import 'package:eventhub/core/app_colors.dart';

void main() {
  final now = DateTime(2026, 10, 19, 12);

  Map<String, dynamic> event({
    required String date,
    required String start,
    required String end,
    String approval = 'approved',
    String status = 'upcoming',
    String? archivedAt,
  }) => {
    'event_date': date,
    'end_date': date,
    'start_time': start,
    'end_time': end,
    'event_status': status,
    'approval_status': approval,
    'archived_at': archivedAt,
  };

  test('active stats follow approval, archive and clock rules', () {
    final events = [
      event(date: '2026-10-20', start: '09:00:00', end: '10:00:00'),
      event(date: '2026-10-19', start: '11:00:00', end: '13:00:00'),
      event(date: '2026-10-19', start: '08:00:00', end: '09:00:00'),
      event(date: '2026-10-20', start: '09:00:00', end: '10:00:00',
          approval: 'pending'),
      event(date: '2026-10-20', start: '09:00:00', end: '10:00:00',
          archivedAt: '2026-10-18T00:00:00Z'),
      event(date: '2026-10-20', start: '09:00:00', end: '10:00:00',
          status: 'cancelled'),
    ];

    expect(activeApprovedEventCount(events, now: now), 2);
  });

  test('total includes only approved, non-archived events', () {
    final events = [
      event(date: '2026-10-19', start: '08:00:00', end: '09:00:00'),
      event(date: '2026-10-20', start: '09:00:00', end: '10:00:00',
          approval: 'pending'),
      event(date: '2026-10-20', start: '09:00:00', end: '10:00:00',
          archivedAt: '2026-10-18T00:00:00Z'),
      event(date: '2026-10-20', start: '09:00:00', end: '10:00:00',
          status: 'cancelled'),
    ];

    expect(totalApprovedEventCount(events), 2);
  });
}
