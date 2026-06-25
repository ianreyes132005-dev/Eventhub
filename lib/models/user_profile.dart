/// Shared profile data for both students and organizers.
class UserProfile {
  final String  userId;
  final String  fullName;
  final String? email;
  final String? avatarUrl;
  final String  role; // 'student' | 'organizer' | 'admin'

  const UserProfile({
    required this.userId,
    required this.fullName,
    this.email,
    this.avatarUrl,
    required this.role,
  });

  factory UserProfile.fromMap(Map<String, dynamic> m, {required String role}) =>
      UserProfile(
        userId:    m['user_id']    as String,
        fullName:  m['full_name']  as String? ?? '',
        email:     m['email']      as String?,
        avatarUrl: m['avatar_url'] as String?,
        role:      role,
      );
}
