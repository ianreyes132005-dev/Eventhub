import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:eventhub/core/app_colors.dart';
import 'package:eventhub/core/services/organizer_notices.dart';

// An event the admin doesn't approve before it starts is Rejected — the
// statuses are Pending review, Approved and Rejected, with no "Expired".

Map<String, dynamic> _event(String? approval, {String? reason, String? reviewedAt}) => {
  'event_id': 'ev-1',
  'title': 'Science Fair',
  'approval_status': approval,
  'rejection_reason': reason,
  'reviewed_at': reviewedAt,
  'event_date': '2026-10-19',
  'end_date': '2026-10-19',
  'start_time': '09:00:00',
  'end_time': '12:00:00',
  'event_status': 'upcoming',
};

void main() {
  final before = DateTime(2026, 10, 19, 8, 59);
  final atStart = DateTime(2026, 10, 19, 9);

  test('pending until the start time, rejected from then on', () {
    expect(approvalStatusOf(_event('pending'), now: before), 'pending');
    expect(approvalStatusOf(_event('pending'), now: atStart), 'rejected');
    expect(pendingPastStart(_event('pending'), now: atStart), isTrue);
  });

  test('decided and legacy events keep their status', () {
    expect(approvalStatusOf(_event('approved'), now: atStart), 'approved');
    expect(approvalStatusOf(_event('rejected'), now: before), 'rejected');
    expect(approvalStatusOf(_event(null), now: atStart), 'approved');
  });

  test('the reason says nobody reviewed it; an admin reason wins', () {
    expect(rejectionReasonOf(_event('pending'), now: before), isNull);
    expect(rejectionReasonOf(_event('pending'), now: atStart), kNotReviewedInTimeReason);
    expect(rejectionReasonOf(_event('rejected', reason: 'Venue is booked'), now: atStart),
        'Venue is booked');
  });

  test('labels show Rejected — never Expired', () {
    final overdue = _event('pending');
    expect(organizerEventStatus(overdue).label, 'Rejected');
    expect(approvalLabelFor(overdue), 'Rejected');
    expect(approvalLabelFor(_event('pending')..['event_date'] = '2099-01-10'), 'Pending Review');
  });

  test('the organizer is told, as one notice before and after the database saves it', () {
    final now = DateTime(2026, 10, 19, 12);
    final shown = OrganizerNotices.eventDecisions([_event('pending')], now: now);
    expect(shown.single.kind, OrgNoticeKind.eventRejected);
    expect(shown.single.at, atStart);
    expect(shown.single.message,
        '“Science Fair” was rejected. Reason: $kNotReviewedInTimeReason');

    // reject_unreviewed_events saves the start time as reviewed_at.
    final saved = OrganizerNotices.eventDecisions([
      _event('rejected',
          reason: kNotReviewedInTimeReason, reviewedAt: atStart.toUtc().toIso8601String()),
    ], now: now);
    expect(saved.single.id, shown.single.id);
  });

  test('the database writes the same reason the app shows', () {
    final sql = File('supabase/migrations/202610210001_auto_reject_unreviewed_events.sql')
        .readAsStringSync();
    expect(sql, contains("rejection_reason = '$kNotReviewedInTimeReason'"));
  });
}
