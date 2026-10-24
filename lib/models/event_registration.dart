/// Holds the data needed to display a student's QR-code ticket.
/// Constructed from a Supabase registrations row after registration completes.
class EventRegistration {
  final String   registrationId;
  final String   eventTitle;
  final String   studentId;
  final String   studentName;
  final DateTime registrationDate;
  final String   qrCodeData;
  /// The short code the organizer can type when the QR won't scan
  /// (registrations.ticket_code — every registration has one).
  final String   ticketCode;

  EventRegistration({
    required this.registrationId,
    required this.eventTitle,
    required this.studentId,
    required this.studentName,
    required this.registrationDate,
    required this.qrCodeData,
    required this.ticketCode,
  });
}
