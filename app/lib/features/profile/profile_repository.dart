import 'package:flutter/foundation.dart' show debugPrint;

import '../../services/api_client.dart';
import 'profile_models.dart';

class ProfileRepository {
  ProfileRepository(this._api);

  final ApiClient _api;

  static Map<String, dynamic> _map(Object? json) {
    if (json is Map<String, dynamic>) return json;
    throw const ApiException('The server sent an answer the app does not understand.');
  }

  /// Full profile for a user.
  Future<UserProfile> getProfile(String userId) async =>
      UserProfile.fromJson(_map(await _api.getJson('/api/users/$userId/profile')));

  /// User's videos, paginated.
  Future<({List<ProfilePost> posts, String? nextCursor})> getUserVideos(
    String userId, {
    int limit = 20,
    String? cursor,
  }) async {
    final json = _map(await _api.getJson(
      '/api/users/$userId/videos',
      query: {'limit': '$limit', 'cursor': ?cursor},
    ));
    final posts = <ProfilePost>[];
    for (final raw in json['posts'] as List<dynamic>) {
      try {
        posts.add(ProfilePost.fromJson(raw as Map<String, dynamic>));
      } on Object catch (e) {
        debugPrint('Skipping a profile post: $e');
      }
    }
    return (posts: posts, nextCursor: json['nextCursor'] as String?);
  }

  /// Update own profile.
  Future<UserProfile> updateProfile({
    String? fullName,
    String? bio,
    List<String>? personalityKeywords,
    String? personalitySummary,
    bool? personalitySummaryApproved,
    List<String>? interests,
  }) async {
    final body = <String, dynamic>{};
    if (fullName != null) body['fullName'] = fullName;
    if (bio != null) body['bio'] = bio;
    if (personalityKeywords != null) body['personalityKeywords'] = personalityKeywords;
    if (personalitySummary != null) body['personalitySummary'] = personalitySummary;
    if (personalitySummaryApproved != null) body['personalitySummaryApproved'] = personalitySummaryApproved;
    if (interests != null) body['interests'] = interests;
    return UserProfile.fromJson(_map(await _api.sendJson('PATCH', '/api/me/profile', body: body)));
  }

  /// Generate an AI personality summary from keywords.
  Future<String> generatePersonalitySummary(List<String> keywords) async {
    final json = _map(await _api.sendJson(
      'POST',
      '/api/me/personality/generate-summary',
      body: {'keywords': keywords},
    ));
    return json['summary'] as String;
  }

  /// Bookmarks (private, owner only).
  Future<List<Bookmark>> getBookmarks() async {
    final json = _map(await _api.getJson('/api/me/bookmarks'));
    return [
      for (final raw in json['bookmarks'] as List<dynamic>)
        Bookmark.fromJson(raw as Map<String, dynamic>),
    ];
  }

  Future<void> addBookmark(String postId) async {
    await _api.sendJson('POST', '/api/me/bookmarks/$postId');
  }

  Future<void> removeBookmark(String postId) async {
    await _api.sendJson('DELETE', '/api/me/bookmarks/$postId');
  }

  /// Follow/unfollow (reuses existing endpoints).
  Future<void> setFollowing(String userId, bool following) async {
    await _api.sendJson(following ? 'POST' : 'DELETE', '/api/users/$userId/follow');
  }

  /// Followers list.
  Future<({List<FollowEntry> users, String? nextCursor})> getFollowers(
    String userId, {
    int limit = 20,
    String? cursor,
  }) async {
    final json = _map(await _api.getJson(
      '/api/users/$userId/followers',
      query: {'limit': '$limit', 'cursor': ?cursor},
    ));
    return (
      users: [
        for (final raw in json['users'] as List<dynamic>)
          FollowEntry.fromJson(raw as Map<String, dynamic>),
      ],
      nextCursor: json['nextCursor'] as String?,
    );
  }

  /// Following list.
  Future<({List<FollowEntry> users, String? nextCursor})> getFollowing(
    String userId, {
    int limit = 20,
    String? cursor,
  }) async {
    final json = _map(await _api.getJson(
      '/api/users/$userId/following',
      query: {'limit': '$limit', 'cursor': ?cursor},
    ));
    return (
      users: [
        for (final raw in json['users'] as List<dynamic>)
          FollowEntry.fromJson(raw as Map<String, dynamic>),
      ],
      nextCursor: json['nextCursor'] as String?,
    );
  }

  /// Resolve a media URL.
  String mediaUrl(String relativePath) => _api.resolveUrl(relativePath);
}
