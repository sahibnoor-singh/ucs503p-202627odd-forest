/// `User` in docs/api.md.
class User {
  const User({
    required this.id,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
    required this.isBot,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        username: json['username'] as String,
        fullName: json['fullName'] as String,
        avatarUrl: json['avatarUrl'] as String?,
        isBot: json['isBot'] as bool,
      );

  final String id;
  final String username;
  final String fullName;
  final String? avatarUrl;

  /// Bot/seed accounts must always be labelled in the UI (CLAUDE.md).
  final bool isBot;
}

/// One row of `GET /api/users/suggested`: someone worth following.
class SuggestedUser {
  const SuggestedUser({required this.user, required this.followerCount, required this.postCount});

  factory SuggestedUser.fromJson(Map<String, dynamic> json) => SuggestedUser(
        user: User.fromJson(json['user'] as Map<String, dynamic>),
        followerCount: (json['followerCount'] as num?)?.toInt() ?? 0,
        postCount: (json['postCount'] as num?)?.toInt() ?? 0,
      );

  final User user;
  final int followerCount;
  final int postCount;
}
