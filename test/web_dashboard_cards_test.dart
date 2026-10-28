import 'package:eventhub/features/organizer/web/dashboard_page.dart';
import 'package:flutter_test/flutter_test.dart';

// The organizer web Dashboard's "Photos to review" card (it replaced
// Attendance Rate): selfies that can still be approved.
void main() {
  // Jan 10, 2099, 9:00 AM – 12:00 PM: check-in runs 8:00 AM – 2:00 PM.
  Map<String, dynamic> event(String id, {String date = '2099-01-10', bool cancelled = false}) => {
        'event_id': id,
        'event_date': date,
        'start_time': '09:00:00',
        'end_time': '12:00:00',
        'approval_status': 'approved',
        'event_status': cancelled ? 'cancelled' : 'upcoming',
      };
  Map<String, dynamic> reg(String eventId, String status) =>
      {'event_id': eventId, 'status': status};

  test('counts submitted photos only while their check-in is open', () {
    final review = photosToReview(
      [event('today'), event('next-month', date: '2099-02-10')],
      [
        reg('today', 'photo_submitted'),
        reg('today', 'photo_submitted'),
        reg('today', 'checked_in'),
        reg('next-month', 'photo_submitted'),
      ],
      now: DateTime(2099, 1, 10, 10),
    );
    expect(review.waiting, 2);
    expect(review.checkInOpen, isTrue);
  });

  test('a closed or cancelled check-in has nothing to review', () {
    final review = photosToReview(
      [event('last-week', date: '2099-01-03'), event('cancelled', cancelled: true)],
      [reg('last-week', 'photo_submitted'), reg('cancelled', 'photo_submitted')],
      now: DateTime(2099, 1, 10, 10),
    );
    expect(review.waiting, 0);
    expect(review.checkInOpen, isFalse);
  });
}
