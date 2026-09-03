/// Strongly-typed representation of a row from the `events` table.
class Event {
  final String  eventId;
  final String  title;
  final String? description;
  final String? location;
  final String? eventDate;
  final String? endDate;
  final String? startTime;
  final String? endTime;
  final String? eventStatus;
  final String? eventType;
  final String? eventImageUrl;
  final int?    maxParticipants;
  final int?    currentParticipants;
  final String? organizerId;
  final String? registrationDeadline;
  final String? createdAt;

  const Event({
    required this.eventId,
    required this.title,
    this.description,
    this.location,
    this.eventDate,
    this.endDate,
    this.startTime,
    this.endTime,
    this.eventStatus,
    this.eventType,
    this.eventImageUrl,
    this.maxParticipants,
    this.currentParticipants,
    this.organizerId,
    this.registrationDeadline,
    this.createdAt,
  });

  factory Event.fromMap(Map<String, dynamic> m) => Event(
    eventId:              m['event_id']              as String,
    title:                m['title']                 as String,
    description:          m['description']           as String?,
    location:             m['location']              as String?,
    eventDate:            m['event_date']            as String?,
    endDate:              m['end_date']              as String?,
    startTime:            m['start_time']            as String?,
    endTime:              m['end_time']              as String?,
    eventStatus:          m['event_status']          as String?,
    eventType:            m['event_type']            as String?,
    eventImageUrl:        m['event_image_url']       as String?,
    maxParticipants:      m['max_participants']      as int?,
    currentParticipants:  m['current_participants']  as int?,
    organizerId:          m['organizer_id']          as String?,
    registrationDeadline: m['registration_deadline'] as String?,
    createdAt:            m['created_at']            as String?,
  );

  Map<String, dynamic> toMap() => {
    'event_id':              eventId,
    'title':                 title,
    'description':           description,
    'location':              location,
    'event_date':            eventDate,
    'end_date':              endDate,
    'start_time':            startTime,
    'end_time':              endTime,
    'event_status':          eventStatus,
    'event_type':            eventType,
    'event_image_url':       eventImageUrl,
    'max_participants':      maxParticipants,
    'current_participants':  currentParticipants,
    'organizer_id':          organizerId,
    'registration_deadline': registrationDeadline,
    'created_at':            createdAt,
  };
}
