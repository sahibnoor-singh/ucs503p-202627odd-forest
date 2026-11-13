// The Dart models must match docs/api.md exactly. The fixtures in
// test/fixtures are real responses captured from app/backend after
// `npm run seed`, so this also guards against the docs drifting from the server.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:forest_app/models/feed_item.dart';
import 'package:forest_app/models/post.dart';
import 'package:forest_app/models/user.dart';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('GET /api/home: every seeded item parses', () {
    final json = _fixture('home_seed.json');
    final items = [
      for (final i in json['items'] as List<dynamic>)
        FeedItem.fromJson(i as Map<String, dynamic>),
    ];
    expect(items, hasLength(6));
    expect(json['nextCursor'], isNull);

    final types = items.map((i) => i.type).toSet();
    expect(types, {ItemType.post, ItemType.videoReply, ItemType.textReply});

    for (final item in items) {
      expect(item.post.createdAt.isUtc, isTrue);
      expect(item.actor.isBot, isTrue, reason: 'seed people are all bots');
      if (item.type == ItemType.post) {
        expect(item.parent, isNull);
        expect(item.post.parentId, isNull);
        expect(item.post.rootId, item.post.id);
        expect(item.post.stance, Stance.parent);
        expect(item.post.depth, 0);
      } else {
        expect(item.parent, isNotNull);
        expect(item.post.parentId, item.parent!.post.id);
        expect(item.post.depth, greaterThan(0));
      }
      // root is only set when it differs from the direct parent
      if (item.root != null) {
        expect(item.root!.id, isNot(item.parent!.post.id));
      }
      expect(item.post.analysis, isNull, reason: 'analysis is detail-only');
    }
  });

  test('seed video posts have no file: mediaUrl is null', () {
    final items = (_fixture('home_seed.json')['items'] as List<dynamic>)
        .map((i) => FeedItem.fromJson(i as Map<String, dynamic>));
    final videos = items.where((i) => i.post.kind == PostKind.video);
    expect(videos, isNotEmpty);
    expect(videos.every((i) => i.post.mediaUrl == null), isTrue);
  });

  test('GET /api/posts/:id/thread parses item, flat replies and total', () {
    final thread = ThreadResponse.fromJson(_fixture('thread_seed.json'));
    expect(thread.replies, isNotEmpty);
    expect(thread.total, thread.replies.length);
    // Every reply points at the root or at another reply in the list.
    final ids = {thread.item.post.id, ...thread.replies.map((r) => r.post.id)};
    for (final r in thread.replies) {
      expect(ids, contains(r.post.parentId));
      expect(r.post.rootId, thread.item.post.id);
    }
  });

  test('GET /api/posts/:id adds post.analysis', () {
    final item = FeedItem.fromJson(_fixture('post_detail_seed.json'));
    final analysis = item.post.analysis;
    expect(analysis, isNotNull);
    expect(analysis!.overallSummary, isNotNull);
    expect(analysis.claims, isA<List<Map<String, dynamic>>>());
  });

  test('User, like result and enums follow the documented wire names', () {
    final user = User.fromJson({
      'id': 'u1',
      'username': 'aman_s',
      'fullName': 'Aman Singh',
      'avatarUrl': null,
      'isBot': false,
    });
    expect(user.avatarUrl, isNull);
    expect(user.isBot, isFalse);

    final like = LikeResult.fromJson({'liked': true, 'likeCount': 3});
    expect(like.liked, isTrue);
    expect(like.likeCount, 3);

    expect(Stance.parse('FOR'), Stance.forSide);
    expect(PostStatus.parse('PROCESSING'), PostStatus.processing);
    expect(PostKind.parse('TEXT'), PostKind.text);
    expect(ItemType.parse('VIDEO_REPLY'), ItemType.videoReply);
    expect(() => Stance.parse('MAYBE'), throwsFormatException);
  });

  test('Post.copyWith only changes what it is told to', () {
    final post = FeedItem.fromJson(
      (_fixture('home_seed.json')['items'] as List<dynamic>).first
          as Map<String, dynamic>,
    ).post;
    final liked = post.copyWith(likedByMe: true, likeCount: post.likeCount + 1);
    expect(liked.likedByMe, isTrue);
    expect(liked.likeCount, post.likeCount + 1);
    expect(liked.id, post.id);
    expect(liked.replyCount, post.replyCount);
    expect(liked.status, post.status);
  });
}
