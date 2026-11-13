import '../../models/user.dart';
import '../../services/api_client.dart';

/// One line in the list: today only "@someone followed you" (docs/api.md, "Notifications").
class AppNotification {
  const AppNotification({required this.id, required this.text, required this.createdAt, required this.read, required this.actor, this.postId, this.postTitle, this.coverUrl});

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'] as Map<String, dynamic>;
    final post = json['post'] as Map<String, dynamic>?;
    return AppNotification(
      id: json['id'] as String,
      text: json['text'] as String,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      read: json['read'] == true,
      actor: User(
        id: actor['id'] as String,
        username: actor['username'] as String,
        fullName: actor['fullName'] as String? ?? actor['username'] as String,
        avatarUrl: actor['avatarUrl'] as String?,
        isBot: actor['isBot'] == true,
      ),
      postId: post?['id'] as String?,
      postTitle: post?['title'] as String?,
      coverUrl: post?['coverUrl'] as String?,
    );
  }

  final String id;
  final String text;
  final DateTime createdAt;
  final bool read;
  final User actor;

  /// The video the person followed from, when it was a reel (its cover is the picture on the right of the line, and opens it).
  final String? postId;
  final String? postTitle;
  final String? coverUrl;
}

class NotificationsRepository {
  NotificationsRepository(this._api);

  final ApiClient _api;

  /// Newest first, with the number not yet read.
  Future<({int unread, List<AppNotification> items})> load() async {
    final json = await _api.getJson('/api/notifications');
    if (json is! Map<String, dynamic>) throw const ApiException('The server sent an answer the app does not understand.');
    final items = <AppNotification>[];
    for (final raw in (json['notifications'] as List? ?? const [])) {
      try {
        items.add(AppNotification.fromJson(raw as Map<String, dynamic>));
      } on Object {
        // one odd row must not hide the rest
      }
    }
    return (unread: (json['unread'] as num?)?.toInt() ?? 0, items: items);
  }

  Future<void> markAllRead() => _api.sendJson('POST', '/api/notifications/read');
}
