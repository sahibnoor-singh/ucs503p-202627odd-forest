import 'package:flutter/foundation.dart' show debugPrint;

import '../../models/user.dart';
import '../../models/video.dart';
import '../../services/api_client.dart';

/// Which part of search to show. The names are what `GET /api/search?type=` expects.
enum SearchType { all, accounts, posts }

/// One person in the results (`accounts[]` in docs/api.md "Search").
class AccountHit {
  const AccountHit({
    required this.user,
    required this.followerCount,
    required this.postCount,
    required this.followedByMe,
    required this.isMe,
  });

  factory AccountHit.fromJson(Map<String, dynamic> json) => AccountHit(
        user: User.fromJson(json['user'] as Map<String, dynamic>),
        followerCount: (json['followerCount'] as num?)?.toInt() ?? 0,
        postCount: (json['postCount'] as num?)?.toInt() ?? 0,
        followedByMe: json['followedByMe'] == true,
        isMe: json['isMe'] == true,
      );

  final User user;
  final int followerCount;
  final int postCount;
  final bool followedByMe;
  final bool isMe;

  AccountHit copyWith({int? followerCount, bool? followedByMe}) => AccountHit(
        user: user,
        followerCount: followerCount ?? this.followerCount,
        postCount: postCount,
        followedByMe: followedByMe ?? this.followedByMe,
        isMe: isMe,
      );
}

/// One answer from the server: people and/or posts, and where the next page starts.
class SearchPage {
  const SearchPage({this.accounts = const [], this.posts = const [], this.nextCursor});

  final List<AccountHit> accounts;
  final List<Video> posts;
  final String? nextCursor;
}

/// `GET /api/search`. Rows the app cannot read are skipped, so one odd row never blanks the results.
class SearchRepository {
  SearchRepository(this._api);

  final ApiClient _api;

  Future<SearchPage> search(String query, {SearchType type = SearchType.all, String? cursor, int limit = 20}) async {
    final json = await _api.getJson('/api/search', query: {'q': query, 'type': type.name, 'limit': '$limit', 'cursor': ?cursor});
    if (json is! Map<String, dynamic>) throw const ApiException('The server sent an answer the app does not understand.');
    return SearchPage(
      accounts: _rows(json['accounts'], AccountHit.fromJson),
      posts: _rows(json['posts'], Video.fromJson).where((v) => v.id.isNotEmpty && v.filename.isNotEmpty).toList(),
      nextCursor: json['nextCursor'] as String?,
    );
  }

  /// Where to load a post's still picture from, or null.
  String? coverUrl(Video video) => video.coverUrl == null ? null : _api.resolveUrl(video.coverUrl!);

  static List<T> _rows<T>(Object? list, T Function(Map<String, dynamic>) parse) {
    if (list is! List) return const [];
    final out = <T>[];
    for (final raw in list) {
      try {
        out.add(parse(raw as Map<String, dynamic>));
      } on Object catch (error) {
        debugPrint('Skipping a search result the app could not read: $error');
      }
    }
    return out;
  }
}
