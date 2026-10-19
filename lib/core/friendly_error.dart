import 'dart:async' show TimeoutException;

import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException, StorageException;

// ─────────────────────────────────────────────────────────────────────────────
// Error messages people can act on.
//
// Supabase reports failures in database terms — "duplicate key value violates
// unique constraint …", "new row violates row-level security policy …",
// "ClientException: XMLHttpRequest error." — which mean nothing to a student
// or an organizer. friendlyError() turns any error, or an error message from
// an Edge Function, into a plain sentence.
//
// Messages the database raises on purpose (RAISE EXCEPTION in the migrations,
// e.g. "Registration is closed — the deadline has passed.") are already
// written for people and pass through unchanged.
//
// Show the result with showErrorAlert() (shared/widgets/error_alert.dart).
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown by app code with a message that is already written for people.
class FriendlyException implements Exception {
  final String message;
  const FriendlyException(this.message);

  @override
  String toString() => message;
}

/// The plain-language messages, so screens and tests can refer to them.
abstract final class FriendlyErrors {
  static const generic = 'Something went wrong. Please try again.';
  static const offline =
      'Couldn’t connect to EventHub. Check your internet connection and try again.';
  static const timeout =
      'The connection is taking too long. Check your internet connection and try again.';
  static const session = 'Your session has expired. Please sign in again.';
  static const permission = 'You don’t have permission to do that.';
  static const notFound =
      'We couldn’t find that record — it may have been removed. Refresh and try again.';
  static const duplicate = 'This record already exists.';
  static const inUse =
      'This can’t be removed because other records still depend on it.';
  static const missingLink =
      'Something this depends on no longer exists. Refresh and try again.';
  static const missingInfo =
      'Some required information is missing. Please fill in every required field.';
  static const invalid =
      'Some of the information isn’t valid. Please check it and try again.';
  static const tooLong =
      'Some of the text is too long. Please shorten it and try again.';
  static const notSetUp =
      'This feature needs a database update that hasn’t been installed yet. '
      'Please contact the system administrator.';
  static const server =
      'The server ran into a problem. Please try again in a moment.';
  static const conflict =
      'Someone else changed this at the same time. Please try again.';
  static const rateLimit =
      'Too many attempts. Please wait a moment and try again.';
  static const fileTooLarge =
      'This file is too large. Please choose a smaller one.';
  static const fileType = 'This file type isn’t supported.';
  static const credentials =
      'Incorrect login details. Please check them and try again.';
}

/// [error] as a sentence a student, organizer or admin understands.
///
/// [error] may be an exception or a message string (e.g. an Edge Function's
/// `message`). [fallback] is used when the error says nothing useful.
String friendlyError(Object? error, {String fallback = FriendlyErrors.generic}) {
  if (error == null) return fallback;
  if (error is FriendlyException) {
    return error.message.trim().isEmpty ? fallback : error.message.trim();
  }
  if (error is TimeoutException) return FriendlyErrors.timeout;
  if (error is PostgrestException) return _postgrest(error) ?? fallback;
  if (error is AuthException) return _auth(error) ?? fallback;
  if (error is StorageException) return _storage(error) ?? fallback;

  final text = error is String ? error : error.toString();
  if (_offline.hasMatch(text)) return FriendlyErrors.offline;
  // Programming errors (TypeError, RangeError, …) never mean anything to the
  // person using the app. StateError is how app code reports a readable
  // "Bad state: …" problem, so it's let through.
  if (error is Error && error is! StateError) return fallback;

  final plain = text.replaceFirst(_prefix, '').trim();
  return _fromText(plain) ?? (_looksReadable(plain) ? plain : fallback);
}

// ── PostgREST (database) ─────────────────────────────────────────────────────

String? _postgrest(PostgrestException e) {
  final code = (e.code ?? '').toUpperCase();
  final message = e.message.trim();
  final all = '${e.message} ${e.details ?? ''} ${e.hint ?? ''}'.toLowerCase();
  if (_offline.hasMatch(all)) return FriendlyErrors.offline;

  // RAISE EXCEPTION in a trigger or function — written for people.
  if (code == 'P0001') return message.isEmpty ? null : message;

  switch (code) {
    case 'P0002':
    case 'PGRST116':
      return FriendlyErrors.notFound;
    case '23505':
    case '23P01':
      return _duplicate(all);
    case '23503':
      return all.contains('update or delete on table')
          ? FriendlyErrors.inUse
          : FriendlyErrors.missingLink;
    case '23502':
      return FriendlyErrors.missingInfo;
    case '23514':
      return FriendlyErrors.invalid;
    case '22001':
      return FriendlyErrors.tooLong;
    case '42501':
      return FriendlyErrors.permission;
    case '42P01': // undefined table
    case '42703': // undefined column
    case '42883': // undefined function
    case '42704': // undefined object
    case 'PGRST200': // relationship not in the schema cache
    case 'PGRST202': // function not in the schema cache
    case 'PGRST204': // column not in the schema cache
    case 'PGRST205': // table not in the schema cache
      return FriendlyErrors.notSetUp;
    case 'PGRST301':
    case 'PGRST302':
    case 'PGRST303':
      return FriendlyErrors.session;
    case '40001':
    case '40P01':
      return FriendlyErrors.conflict;
    case '57014':
      return FriendlyErrors.server;
  }
  if (code.startsWith('22')) return FriendlyErrors.invalid;
  if (code.startsWith('08') ||
      code.startsWith('53') ||
      code.startsWith('58') ||
      code.startsWith('XX') ||
      code.startsWith('PGRST00')) {
    return FriendlyErrors.server;
  }

  // Non-JSON responses carry the HTTP status as the code.
  final status = int.tryParse(code);
  if (status != null) {
    final byStatus = _fromStatus(status);
    if (byStatus != null) return byStatus;
  }
  return _fromText(message) ?? (_looksReadable(message) ? message : null);
}

// ── GoTrue (sign-in, passwords) ──────────────────────────────────────────────

String? _auth(AuthException e) {
  final m = e.message.toLowerCase();
  final status = int.tryParse(e.statusCode ?? '');
  if (_offline.hasMatch(m)) return FriendlyErrors.offline;
  if (m.contains('invalid login credentials') || m.contains('invalid credentials')) {
    return FriendlyErrors.credentials;
  }
  if (m.contains('email not confirmed')) {
    return 'This account hasn’t been activated yet. Please contact the administrator.';
  }
  if (m.contains('already registered') || m.contains('already been registered')) {
    return 'An account with these details already exists.';
  }
  if (m.contains('banned')) {
    return 'This account has been disabled. Please contact the administrator.';
  }
  if (m.contains('rate limit') || status == 429) return FriendlyErrors.rateLimit;
  if (m.contains('refresh token') || m.contains('jwt') || m.contains('session')) {
    return FriendlyErrors.session;
  }
  // e.g. "Database error querying schema", "Database error saving new user"
  if (m.contains('database error') || (status != null && status >= 500)) {
    return FriendlyErrors.server;
  }
  return _fromText(e.message) ?? (_looksReadable(e.message) ? e.message.trim() : null);
}

// ── Storage (banners, profile photos, selfies) ───────────────────────────────

String? _storage(StorageException e) {
  final m = '${e.message} ${e.error ?? ''}'.toLowerCase();
  final status = int.tryParse(e.statusCode ?? '');
  if (_offline.hasMatch(m)) return FriendlyErrors.offline;
  if (status == 413 || m.contains('too large') || m.contains('maximum allowed size')) {
    return FriendlyErrors.fileTooLarge;
  }
  if (m.contains('mime') || m.contains('file type')) return FriendlyErrors.fileType;
  if (m.contains('bucket not found')) return FriendlyErrors.notSetUp;
  if (m.contains('jwt') || status == 401) return FriendlyErrors.session;
  if (m.contains('row-level security') || m.contains('unauthorized') || status == 403) {
    return FriendlyErrors.permission;
  }
  if (m.contains('not found') || status == 404) {
    return 'The file couldn’t be found — it may have been removed.';
  }
  if (m.contains('already exists') || status == 409) {
    return 'A file with the same name already exists. Please try again.';
  }
  if (status != null && status >= 500) return FriendlyErrors.server;
  return null;
}

// ── Shared rules ─────────────────────────────────────────────────────────────

String? _fromStatus(int status) {
  if (status == 401) return FriendlyErrors.session;
  if (status == 403) return FriendlyErrors.permission;
  if (status == 404 || status == 406) return FriendlyErrors.notFound;
  if (status == 409) return FriendlyErrors.duplicate;
  if (status == 413) return FriendlyErrors.tooLong;
  if (status == 429) return FriendlyErrors.rateLimit;
  if (status >= 500) return FriendlyErrors.server;
  return null;
}

/// Recognises database / network wording inside a plain message (Edge
/// Functions pass some of it through, and older code wrapped it in
/// `Exception(message)`).
String? _fromText(String raw) {
  final m = raw.toLowerCase();
  if (m.isEmpty) return null;
  if (_offline.hasMatch(m)) return FriendlyErrors.offline;
  if (m.contains('timed out') || m.contains('timeoutexception')) return FriendlyErrors.timeout;
  if (m.contains('invalid login credentials')) return FriendlyErrors.credentials;
  if (m.contains('jwt') ||
      m.contains('refresh token') ||
      m.contains('auth session missing') ||
      m == 'unauthorized.' ||
      m == 'unauthorized' ||
      m == 'not authenticated') {
    return FriendlyErrors.session;
  }
  if (m.contains('row-level security') || m.contains('permission denied')) {
    return FriendlyErrors.permission;
  }
  if (m.contains('duplicate key')) return _duplicate(m);
  if (m.contains('violates foreign key')) {
    return m.contains('update or delete on table')
        ? FriendlyErrors.inUse
        : FriendlyErrors.missingLink;
  }
  if (m.contains('violates not-null') || m.contains('null value in column')) {
    return FriendlyErrors.missingInfo;
  }
  if (m.contains('violates check constraint')) return FriendlyErrors.invalid;
  if (m.contains('value too long')) return FriendlyErrors.tooLong;
  if (m.contains('invalid input syntax') ||
      m.contains('invalid input value') ||
      m.contains('out of range for type')) {
    return FriendlyErrors.invalid;
  }
  if (m.contains('schema cache') ||
      (m.contains('does not exist') &&
          (m.contains('relation') || m.contains('column') || m.contains('function')))) {
    return FriendlyErrors.notSetUp;
  }
  if (m.contains('payload too large') || m.contains('maximum allowed size')) {
    return FriendlyErrors.fileTooLarge;
  }
  if (m.contains('rate limit') || m.contains('too many requests')) {
    return FriendlyErrors.rateLimit;
  }
  if (m.contains('database error') ||
      m.contains('internal server error') ||
      m.contains('bad gateway') ||
      m.contains('service unavailable') ||
      m.contains('gateway timeout')) {
    return FriendlyErrors.server;
  }
  return null;
}

String _duplicate(String all) {
  if (all.contains('event_revisions')) {
    return 'This event already has changes waiting for review.';
  }
  if (all.contains('registrations')) return 'You’re already registered for this event.';
  if (all.contains('(lrn)') || all.contains('_lrn')) {
    return 'A student with this LRN already exists.';
  }
  if (all.contains('organizer_id')) return 'This organizer ID is already in use.';
  if (all.contains('email')) return 'An account with this email already exists.';
  return FriendlyErrors.duplicate;
}

/// True for a sentence written for people; false for anything that reads
/// like a stack trace, SQL, JSON or an exception dump.
bool _looksReadable(String s) {
  final text = s.trim();
  return text.length >= 4 &&
      text.length <= 300 &&
      text.contains(' ') &&
      !_technical.hasMatch(text);
}

final _prefix = RegExp(r'^(Exception|Bad state|FormatException|StateError):\s*');

final _offline = RegExp(
  r'socketexception|clientexception|handshakeexception|httpexception|'
  r'failed host lookup|xmlhttprequest error|failed to fetch|networkerror|'
  r'network is unreachable|no address associated|software caused connection abort|'
  r'connection (refused|reset|closed|failed|abort|timed out)',
  caseSensitive: false,
);

final _technical = RegExp(
  r'exception|error:|stack ?trace|violates|constraint|relation "|column "|'
  r'syntax error|schema cache|pgrst|sqlstate|postgres|\bjwt\b|uuid|'
  r'null check|nosuchmethod|typeerror|is not a subtype|rangeerror|'
  r'<html|<!doctype|\{"|":|instance of|#\d+\s',
  caseSensitive: false,
);
