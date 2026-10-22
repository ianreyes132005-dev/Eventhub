// ─────────────────────────────────────────────────────────────────────────────
// Ticket IDs — the short code under every student's QR code.
//
// The database gives each registration a random 4-digit code, unique within
// its event (trg_assign_ticket_code, migration 202610210002). When a QR code
// won't scan, the organizer types the code in the scanner instead.
// ─────────────────────────────────────────────────────────────────────────────

/// A registration whose Ticket ID matched, with its event.
typedef TicketMatch = ({
  Map<String, dynamic> registration,
  Map<String, dynamic> event,
});

/// What the organizer typed in the scanner's "Type Ticket ID" box.
enum TicketInputKind { ticketCode, qrValue, invalid }

final _qrValue = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final _ticketCode = RegExp(r'^\d{4,5}$');

/// Reads the typed entry: a Ticket ID ("4821" — spaces and a leading # are
/// fine), the full QR value pasted in (a registration's long ID), or neither.
({TicketInputKind kind, String value}) parseTicketInput(String raw) {
  final text = raw.trim();
  if (_qrValue.hasMatch(text)) {
    return (kind: TicketInputKind.qrValue, value: text.toLowerCase());
  }
  final digits = text.replaceAll(RegExp(r'[\s#]'), '');
  if (_ticketCode.hasMatch(digits)) {
    return (kind: TicketInputKind.ticketCode, value: digits);
  }
  return (kind: TicketInputKind.invalid, value: text);
}

/// The tickets to offer when a code matched in several of the organizer's
/// events: the ones whose check-in is open, when there are any (a single one
/// opens straight away), otherwise all of them.
List<T> ticketChoices<T>(List<T> matches, bool Function(T match) checkInOpen) {
  final open = matches.where(checkInOpen).toList();
  return open.isNotEmpty ? open : matches;
}
