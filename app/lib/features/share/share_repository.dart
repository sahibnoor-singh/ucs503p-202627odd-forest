import '../../models/user.dart';
import '../../services/api_client.dart';

/// What happened to each person a video was sent to (`POST /api/posts/:id/share`).
class ShareResult {
  const ShareResult({required this.sent, required this.skipped});

  /// Ids of the people it is now with (including ones who already had it).
  final List<String> sent;

  /// Person id → why not (`NOT_FRIENDS`, `BOT`, `SELF`, `UNAVAILABLE`).
  final Map<String, String> skipped;
}

/// Sending videos to friends (docs/api.md "Sending a video to a friend"). What was sent to you is read in the messages.
class ShareRepository {
  ShareRepository(this._api);

  final ApiClient _api;

  static Map<String, dynamic> _map(Object? json) {
    if (json is Map<String, dynamic>) return json;
    throw const ApiException('The server sent an answer the app does not understand.');
  }

  /// People you can send to: you follow each other.
  Future<List<User>> friends() async {
    final json = _map(await _api.getJson('/api/users/friends'));
    return [for (final raw in (json['users'] as List? ?? const [])) User.fromJson(_map(raw))];
  }

  Future<ShareResult> send(String postId, List<String> recipientIds) async {
    final json = _map(await _api.sendJson('POST', '/api/posts/$postId/share', body: {'recipientIds': recipientIds}));
    return ShareResult(
      sent: [for (final id in (json['sent'] as List? ?? const [])) '$id'],
      skipped: {
        for (final s in (json['skipped'] as List? ?? const [])) '${_map(s)['userId']}': '${_map(s)['reason']}',
      },
    );
  }
}
