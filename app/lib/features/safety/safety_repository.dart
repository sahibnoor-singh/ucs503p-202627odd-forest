import 'package:flutter/foundation.dart';

import '../../data/feed_repository.dart' show ReportReason;
import '../../models/user.dart';
import '../../services/api_client.dart';

/// Reporting and blocking from anywhere in the app (docs/api.md "Moderation"): one client so the reels, the messages and the search
/// results all do the same thing and say the same words.
class SafetyRepository {
  SafetyRepository(this._api);

  final ApiClient _api;

  Future<void> report(String postId, ReportReason reason) async {
    await _api.sendJson('POST', '/api/posts/$postId/report', body: {'reason': reason.wire});
  }

  /// Blocking also removes the follow in both directions (server side).
  Future<void> block(String userId) async {
    await _api.sendJson('POST', '/api/users/$userId/block');
  }

  Future<void> unblock(String userId) async {
    await _api.sendJson('DELETE', '/api/users/$userId/block');
  }

  /// `GET /api/me/blocks`: the people this person has blocked, newest first.
  Future<List<User>> blocked() async {
    final json = await _api.getJson('/api/me/blocks');
    final rows = json is Map<String, dynamic> ? json['users'] : null;
    if (rows is! List) throw const ApiException('The server sent an answer the app does not understand.');
    return [for (final raw in rows) User.fromJson(raw as Map<String, dynamic>)];
  }
}

/// The people blocked during this session, so screens can hide them at once instead of waiting for the next refresh.
class BlocklistController extends ChangeNotifier {
  final Set<String> _ids = {};

  bool isBlocked(String? userId) => userId != null && _ids.contains(userId);

  void add(String userId) {
    if (_ids.add(userId)) notifyListeners();
  }

  void remove(String userId) {
    if (_ids.remove(userId)) notifyListeners();
  }
}
