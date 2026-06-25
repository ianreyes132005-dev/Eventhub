/// Holds the data needed to display a student's QR-code ticket.
/// Constructed from a Supabase registrations row after registration completes.
class EventRegistration {
  final String   registrationId;
  final String   eventId;
  final String   eventTitle;
  final String   studentId;
  final String   studentName;
  final DateTime registrationDate;
  final String   qrCodeData;

  EventRegistration({
    required this.registrationId,
    required this.eventId,
    required this.eventTitle,
    required this.studentId,
    required this.studentName,
    required this.registrationDate,
    required this.qrCodeData,
  });
}
