import 'dart:io';

import 'package:eventhub/features/student/events/my_registered_events_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// My Registered Events: each ticket's badge says where check-in stands. A new
// registration ('pending' — the normal state right after registering) used
// to read "Failed to Register" with no QR button.
void main() {
  test('every status has its own badge', () {
    String label(String? s) => ticketStatusBadge(s).label;
    expect(label('pending'), 'Registered');
    expect(label(null), 'Registered');
    expect(label('qr_scanned'), 'Scanned');
    expect(label('photo_required'), 'Selfie needed');
    expect(label('photo_submitted'), 'Under review');
    expect(label('checked_in'), 'Checked In');
    expect(label('rejected'), 'Declined');
    // Too late to check in (registrationMissed).
    expect(ticketStatusBadge('pending', missed: true).label, 'Missed');
    expect(ticketStatusBadge('photo_submitted', missed: true).label, 'Missed');
  });

  test('white badge text clears 4.5:1 on every badge colour', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
    }
    for (final s in ['pending', 'qr_scanned', 'photo_required', 'photo_submitted',
        'checked_in', 'rejected']) {
      expect(contrast(Colors.white, ticketStatusBadge(s).color),
          greaterThanOrEqualTo(4.5), reason: s);
    }
    expect(contrast(Colors.white, ticketStatusBadge('pending', missed: true).color),
        greaterThanOrEqualTo(4.5), reason: 'missed');
  });

  test('a registered student is never told their registration failed', () {
    final page = File('lib/features/student/events/my_registered_events_page.dart')
        .readAsStringSync();
    expect(page, isNot(contains('Failed to Register')));
    expect(page, contains('Registration declined'));
  });
}
