import 'dart:async';

import 'package:eventhub/core/friendly_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

PostgrestException pg(String code, String message, {String? details}) =>
    PostgrestException(message: message, code: code, details: details);

void main() {
  group('database errors', () {
    test('rules raised on purpose pass through unchanged', () {
      expect(
        friendlyError(pg('P0001', 'Registration is closed — the deadline has passed.')),
        'Registration is closed — the deadline has passed.',
      );
    });

    test('duplicates name what already exists', () {
      expect(
        friendlyError(pg('23505',
            'duplicate key value violates unique constraint "students_lrn_key"',
            details: 'Key (lrn)=(123456260001) already exists.')),
        'A student with this LRN already exists.',
      );
      expect(
        friendlyError(pg('23505',
            'duplicate key value violates unique constraint "event_revisions_one_pending"')),
        'This event already has changes waiting for review.',
      );
      expect(friendlyError(pg('23505', 'duplicate key value violates unique constraint "x_key"')),
          FriendlyErrors.duplicate);
    });

    test('row-level security reads as a permission problem', () {
      expect(
        friendlyError(pg('42501', 'new row violates row-level security policy for table "events"')),
        FriendlyErrors.permission,
      );
    });

    test('foreign keys distinguish "in use" from "gone"', () {
      expect(
        friendlyError(pg('23503',
            'update or delete on table "events" violates foreign key constraint '
            '"registrations_event_id_fkey" on table "registrations"')),
        FriendlyErrors.inUse,
      );
      expect(
        friendlyError(pg('23503',
            'insert or update on table "registrations" violates foreign key constraint')),
        FriendlyErrors.missingLink,
      );
    });

    test('a missing migration says a database update is needed', () {
      expect(
        friendlyError(pg('PGRST202',
            'Could not find the function public.active_student_count without parameters in the schema cache')),
        FriendlyErrors.notSetUp,
      );
      expect(friendlyError(pg('42703', 'column events.archived_at does not exist')),
          FriendlyErrors.notSetUp);
    });

    test('other codes map to plain sentences', () {
      expect(friendlyError(pg('PGRST116', 'JSON object requested, multiple (or no) rows returned')),
          FriendlyErrors.notFound);
      expect(friendlyError(pg('PGRST301', 'JWT expired')), FriendlyErrors.session);
      expect(friendlyError(pg('23502', 'null value in column "title" violates not-null constraint')),
          FriendlyErrors.missingInfo);
      expect(friendlyError(pg('22P02', 'invalid input syntax for type uuid: "abc"')),
          FriendlyErrors.invalid);
      expect(friendlyError(pg('22001', 'value too long for type character varying(200)')),
          FriendlyErrors.tooLong);
      expect(friendlyError(pg('503', '<html><body>Service Unavailable</body></html>')),
          FriendlyErrors.server);
    });
  });

  group('network and sign-in', () {
    test('offline errors on mobile and web', () {
      expect(friendlyError(Exception('SocketException: Failed host lookup: x.supabase.co')),
          FriendlyErrors.offline);
      expect(friendlyError(Exception('ClientException: XMLHttpRequest error.')),
          FriendlyErrors.offline);
    });

    test('timeouts', () {
      expect(friendlyError(TimeoutException('Future not completed')), FriendlyErrors.timeout);
    });

    test('auth messages', () {
      expect(friendlyError(const AuthException('Invalid login credentials', statusCode: '400')),
          FriendlyErrors.credentials);
      expect(friendlyError(const AuthException('Database error querying schema', statusCode: '500')),
          FriendlyErrors.server);
      expect(
        friendlyError(const AuthException(
            'For security purposes, you can only request this after 42 seconds.')),
        'For security purposes, you can only request this after 42 seconds.',
      );
    });

    test('storage limits', () {
      expect(friendlyError(const StorageException('Payload too large', statusCode: '413')),
          FriendlyErrors.fileTooLarge);
      expect(
        friendlyError(const StorageException(
            'new row violates row-level security policy', statusCode: '403')),
        FriendlyErrors.permission,
      );
    });
  });

  group('app and Edge Function messages', () {
    test('readable app messages keep their wording', () {
      expect(friendlyError(Exception('The event wasn’t updated — it may have been removed.')),
          'The event wasn’t updated — it may have been removed.');
      expect(friendlyError(StateError('The announcement was not deleted.')),
          'The announcement was not deleted.');
      expect(friendlyError(const FriendlyException('Already done.')), 'Already done.');
      expect(friendlyError('LRN 123456-260001 already exists.'), 'LRN 123456-260001 already exists.');
    });

    test('database wording inside a plain message is translated', () {
      expect(
        friendlyError(
            'duplicate key value violates unique constraint "organizers_organizer_id_key"'),
        'This organizer ID is already in use.',
      );
      expect(friendlyError('Unauthorized.'), FriendlyErrors.session);
      expect(friendlyError(Exception('Not authenticated')), FriendlyErrors.session);
    });

    test('dumps and programming errors fall back', () {
      expect(friendlyError(TypeError()), FriendlyErrors.generic);
      expect(friendlyError(RangeError('Invalid value')), FriendlyErrors.generic);
      expect(friendlyError(Exception('PlatformException(photo_access_denied, null, null)')),
          FriendlyErrors.generic);
      expect(friendlyError('{"code":"x","message":"y"}'), FriendlyErrors.generic);
      expect(friendlyError(null, fallback: 'Could not save.'), 'Could not save.');
      expect(friendlyError('', fallback: 'Could not save.'), 'Could not save.');
    });
  });
}
