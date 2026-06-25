/// Represents a row from the `announcements` table.
class Announcement {
  final int     id;
  final String  title;
  final String  message;
  final String? createdBy;
  final String? createdAt;

  const Announcement({
    required this.id,
    required this.title,
    required this.message,
    this.createdBy,
    this.createdAt,
  });

  factory Announcement.fromMap(Map<String, dynamic> m) => Announcement(
    id:        m['id']         as int,
    title:     m['title']      as String,
    message:   m['message']    as String,
    createdBy: m['created_by'] as String?,
    createdAt: m['created_at'] as String?,
  );
}
