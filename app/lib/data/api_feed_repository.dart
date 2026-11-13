import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import '../features/editor/recipe.dart';
import '../models/feed_item.dart';
import '../models/user.dart';
import '../services/api_client.dart';
import 'feed_repository.dart';

/// The real thing: `docs/api.md` over HTTP.
class ApiFeedRepository implements FeedRepository {
  ApiFeedRepository(this._api);

  final ApiClient _api;

  static Map<String, dynamic> _map(Object? json) {
    if (json is Map<String, dynamic>) return json;
    throw const ApiException('The server sent an answer the app does not understand.');
  }

  @override
  Future<User> me() async {
    final json = _map(await _api.getJson('/api/me'));
    return User.fromJson(_map(json['user']));
  }

  @override
  Future<HomePage> home({String? cursor, int limit = 20}) async {
    final json = _map(await _api.getJson(
      '/api/home',
      query: {'limit': '$limit', 'cursor': ?cursor},
    ));
    final items = <FeedItem>[];
    for (final raw in json['items'] as List<dynamic>) {
      // One malformed row must not blank the whole feed.
      try {
        items.add(FeedItem.fromJson(_map(raw)));
      } on Object catch (error) {
        debugPrint('Skipping a feed item the app could not read: $error');
      }
    }
    return HomePage(items: items, nextCursor: json['nextCursor'] as String?);
  }

  @override
  Future<FeedItem> post(String id) async =>
      FeedItem.fromJson(_map(await _api.getJson('/api/posts/$id')));

  @override
  Future<ThreadResponse> thread(String id, {int limit = 100}) async =>
      ThreadResponse.fromJson(_map(await _api.getJson(
        '/api/posts/$id/thread',
        query: {'limit': '$limit'},
      )));

  @override
  Future<LikeResult> setLiked(String postId, bool liked) async =>
      LikeResult.fromJson(_map(await _api.sendJson(
        liked ? 'POST' : 'DELETE',
        '/api/posts/$postId/like',
      )));

  @override
  Future<FeedItem> replyText({
    required String parentId,
    required String body,
  }) async =>
      FeedItem.fromJson(_map(await _api.postMultipart(
        '/api/posts',
        fields: {'kind': 'TEXT', 'parentId': parentId, 'body': body},
      )));

  @override
  Future<FeedItem> replyVideo({
    required String parentId,
    required String filePath,
    String? caption,
  }) async =>
      FeedItem.fromJson(_map(await _api.postMultipart(
        '/api/posts',
        fields: {
          'kind': 'VIDEO',
          'parentId': parentId,
          if (caption != null && caption.trim().isNotEmpty) 'body': caption.trim(),
        },
        filePath: filePath,
      )));

  @override
  Future<FeedItem> compose({
    required Recipe recipe,
    double? videoSeconds,
    String? parentId,
    String? title,
    String? body,
    String? videoPath,
    List<String> photoPaths = const [],
    String? musicPath,
    String? promptDay,
    String? roomId,
  }) async =>
      FeedItem.fromJson(_map(await _api.postMultipartFiles(
        '/api/posts/compose',
        fields: {
          'recipe': jsonEncode(recipe.toJson(videoSeconds: videoSeconds)),
          'parentId': ?parentId,
          'promptDay': ?promptDay,
          'roomId': ?roomId,
          if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
          if (body != null && body.trim().isNotEmpty) 'body': body.trim(),
        },
        files: [
          if (videoPath != null) (field: 'video', path: videoPath),
          for (final p in photoPaths) (field: 'photos', path: p),
          if (musicPath != null) (field: 'music', path: musicPath),
        ],
      )));

  @override
  Future<FeedItem> retryPost(String postId) async =>
      FeedItem.fromJson(_map(await _api.sendJson('POST', '/api/posts/$postId/retry')));

  @override
  Future<List<SuggestedUser>> suggestedUsers({int limit = 10}) async {
    final json = _map(await _api.getJson('/api/users/suggested', query: {'limit': '$limit'}));
    final people = <SuggestedUser>[];
    for (final raw in json['users'] as List<dynamic>) {
      try {
        people.add(SuggestedUser.fromJson(_map(raw)));
      } on Object catch (error) {
        debugPrint('Skipping a suggested person the app could not read: $error');
      }
    }
    return people;
  }

  @override
  Future<void> report(String postId, ReportReason reason) async {
    await _api.sendJson(
      'POST',
      '/api/posts/$postId/report',
      body: {'reason': reason.wire},
    );
  }

  @override
  Future<void> setBlocked(String userId, bool blocked) async {
    await _api.sendJson(blocked ? 'POST' : 'DELETE', '/api/users/$userId/block');
  }

  @override
  Future<void> setFollowing(String userId, bool following) async {
    await _api.sendJson(following ? 'POST' : 'DELETE', '/api/users/$userId/follow');
  }

  @override
  String mediaUrl(String relativePath) => _api.resolveUrl(relativePath);
}
