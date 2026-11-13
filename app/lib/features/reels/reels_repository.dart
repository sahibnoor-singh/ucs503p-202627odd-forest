import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../models/video.dart';
import '../../services/api_client.dart';

class FeedPage {
  final List<Video> videos;
  final String? nextCursor;

  FeedPage({required this.videos, this.nextCursor});
}

class OpinionResult {
  final String side;
  final Video? strongestReply;

  OpinionResult({required this.side, this.strongestReply});
}

/// The Discover (reels) tab's view of the backend: `docs/api.md` → "Discover".
///
/// It talks through the shared [ApiClient], so it uses the same server address
/// and the same login as the Home tab. Nothing here pretends: when the server
/// cannot be reached the calls throw an [ApiException] (its message is fit to
/// show) and the screen decides what to display. Only fire-and-forget
/// reporting calls ([recordInteraction], [recordView]) swallow errors, because
/// a lost watch-time ping must never interrupt someone watching a video.
class ReelsRepository {
  ReelsRepository(this._api);

  final ApiClient _api;

  static Map<String, dynamic> _map(Object? json) {
    if (json is Map<String, dynamic>) return json;
    throw const ApiException('The server sent an answer the app does not understand.');
  }

  /// Parses a list of videos, skipping rows the app cannot read (one bad row
  /// must not blank the whole feed).
  static List<Video> _videos(Object? json) {
    if (json is! List) {
      throw const ApiException('The server sent an answer the app does not understand.');
    }
    final out = <Video>[];
    for (final raw in json) {
      try {
        final row = _map(raw);
        // Video.fromJson is forgiving (it fills gaps with defaults), so check the two
        // things a playable reel cannot do without: a real id and a file to play.
        final id = row['id'];
        final file = row['filename'];
        if (id is! String || id.isEmpty || file is! String || file.isEmpty) {
          debugPrint('Skipping a video with no id or file');
          continue;
        }
        out.add(Video.fromJson(row));
      } on Object catch (error) {
        debugPrint('Skipping a video the app could not read: $error');
      }
    }
    return out;
  }

  /// Where to play a video from. Files are served by the same server, no login needed.
  String videoUrl(Video video) {
    if (video.filename.startsWith('http://') || video.filename.startsWith('https://')) {
      return video.filename;
    }
    return _api.resolveUrl('/uploads/${Uri.encodeComponent(video.filename)}');
  }

  /// Where to load a video's still picture from, or null when it has none.
  String? coverUrl(Video video) => video.coverUrl == null ? null : _api.resolveUrl(video.coverUrl!);

  /// Ranked opinions for this person. [cursor] is the previous page's `nextCursor`.
  Future<FeedPage> getFeed({String? cursor, int limit = 10}) async {
    final json = _map(await _api.getJson(
      '/api/videos/feed',
      query: {'limit': '$limit', 'cursor': ?cursor},
    ));
    return FeedPage(videos: _videos(json['videos']), nextCursor: json['nextCursor'] as String?);
  }

  Future<Video> getVideo(String id) async =>
      Video.fromJson(_map(await _api.getJson('/api/videos/${Uri.encodeComponent(id)}')));

  /// Direct video replies, best first; [side] is `FOR` or `AGAINST`.
  Future<List<Video>> getReplies(String videoId, {String? side}) async {
    return _videos(await _api.getJson(
      '/api/videos/${Uri.encodeComponent(videoId)}/replies',
      query: {if (side != null && side.isNotEmpty) 'side': side.toUpperCase()},
    ));
  }

  Future<Video?> getStrongestReply(String videoId, String side) async {
    final json = _map(await _api.getJson(
      '/api/videos/${Uri.encodeComponent(videoId)}/strongest-reply',
      query: {'side': side.toUpperCase()},
    ));
    final reply = json['reply'];
    return reply == null ? null : Video.fromJson(_map(reply));
  }

  /// The whole debate this video belongs to, root first.
  Future<List<Video>> getTree(String videoId) async =>
      _videos(await _api.getJson('/api/videos/${Uri.encodeComponent(videoId)}/tree'));

  Future<OpinionResult> setOpinion(String videoId, String side) async {
    final json = _map(await _api.sendJson(
      'PUT',
      '/api/videos/${Uri.encodeComponent(videoId)}/opinion',
      body: {'side': side},
    ));
    final reply = json['strongestReply'];
    return OpinionResult(
      side: json['side'] as String? ?? side,
      strongestReply: reply == null ? null : Video.fromJson(_map(reply)),
    );
  }

  Future<void> deleteOpinion(String videoId) async {
    await _api.sendJson('DELETE', '/api/videos/${Uri.encodeComponent(videoId)}/opinion');
  }

  /// Likes the video; returns the server's like count.
  Future<int> setLike(String videoId) async {
    final json = _map(await _api.sendJson('PUT', '/api/videos/${Uri.encodeComponent(videoId)}/like'));
    return (json['likeCount'] as num?)?.toInt() ?? 0;
  }

  Future<int> deleteLike(String videoId) async {
    final json = _map(await _api.sendJson('DELETE', '/api/videos/${Uri.encodeComponent(videoId)}/like'));
    return (json['likeCount'] as num?)?.toInt() ?? 0;
  }

  Future<void> recordView(String videoId, int watchedMs, bool completed) =>
      recordInteraction(videoId: videoId, watchDurationMs: watchedMs, completed: completed);

  /// Tells the recommender what the person did. Best effort: never throws.
  Future<void> recordInteraction({
    required String videoId,
    int? watchDurationMs,
    bool? completed,
    bool? skipped,
    bool? rewatched,
    bool? saved,
    bool? shared,
  }) async {
    try {
      await _api.sendJson('POST', '/api/videos/${Uri.encodeComponent(videoId)}/interactions', body: {
        'watchDurationMs': ?watchDurationMs,
        'completed': ?completed,
        'skipped': ?skipped,
        'rewatched': ?rewatched,
        'saved': ?saved,
        'shared': ?shared,
      });
    } on ApiException catch (error) {
      debugPrint('Could not record interaction: ${error.message}');
    }
  }

  Future<Map<String, dynamic>> getUserProfile() async =>
      _map(await _api.getJson('/api/videos/profile'));

  /// Forgets what the recommender learned. True when the server confirmed it.
  Future<bool> resetUserProfile() async {
    try {
      await _api.sendJson('POST', '/api/videos/profile/reset');
      return true;
    } on ApiException {
      return false;
    }
  }

  /// Files a report. Throws if it could not be saved (so the screen does not claim it was).
  Future<void> reportVideo(String videoId, String reason) async {
    await _api.sendJson('POST', '/api/videos/${Uri.encodeComponent(videoId)}/report', body: {'reason': reason});
  }

  /// `{id, status: processing|ready|failed, stance, credibility}`.
  Future<Map<String, dynamic>> getStatus(String videoId) async =>
      _map(await _api.getJson('/api/videos/${Uri.encodeComponent(videoId)}/status'));

  /// Posts a recorded opinion, or a reply when [parentVideoId] is given, with
  /// the same endpoint as the Upload tab (`POST /api/posts`). Returns at once with
  /// `status: processing`; poll [getStatus] until it is `ready`.
  Future<Video> uploadVideo(
    File file, {
    String? title,
    String? parentVideoId,
  }) async {
    final isReply = parentVideoId != null && parentVideoId.isNotEmpty;
    final json = _map(await _api.postMultipart(
      '/api/posts',
      fields: {
        'kind': 'VIDEO',
        if (isReply) 'parentId': parentVideoId,
        // Only opinions carry a title; replies are identified by who they answer.
        if (!isReply && title != null && title.trim().isNotEmpty) 'title': title.trim(),
      },
      filePath: file.path,
    ));
    final post = _map(json['post']);
    final media = post['mediaUrl'] as String?;
    return Video(
      id: post['id'] as String,
      title: post['title'] as String?,
      filename: media == null ? '' : media.split('/').last,
      status: (post['status'] as String? ?? 'processing').toLowerCase(),
      role: isReply ? 'CHILD' : 'PARENT',
      parentVideoId: post['parentId'] as String?,
      stance: post['stance'] as String? ?? 'PARENT',
      userName: _map(json['actor'])['username'] as String? ?? '',
      createdAt: post['createdAt'] as String? ?? '',
    );
  }
}
