// A post's cover picture: read from the server's JSON, and shown in the card until the video can play.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:forest_app/data/fake_feed_repository.dart';
import 'package:forest_app/features/home/feed_controller.dart';
import 'package:forest_app/models/post.dart';
import 'package:forest_app/ui/post_media.dart';

Map<String, dynamic> _json({String? coverUrl}) => {
      'id': 'p1',
      'kind': 'VIDEO',
      'parentId': null,
      'rootId': 'p1',
      'depth': 0,
      'title': 'T',
      'body': null,
      'mediaUrl': '/uploads/a-composed.mp4',
      'coverUrl': ?coverUrl,
      'stance': 'PARENT',
      'status': 'READY',
      'summary': null,
      'createdAt': '2026-10-10T12:00:00.000Z',
      'likeCount': 0,
      'likedByMe': false,
      'replyCount': 0,
      'forCount': 0,
      'againstCount': 0,
    };

void main() {
  test('the cover comes from the server JSON, and is absent for older posts', () {
    expect(Post.fromJson(_json(coverUrl: '/uploads/a-composed-cover.jpg')).coverUrl, '/uploads/a-composed-cover.jpg');
    expect(Post.fromJson(_json()).coverUrl, isNull);
    final post = Post.fromJson(_json(coverUrl: '/uploads/c.jpg'));
    expect(post.copyWith(likeCount: 3).coverUrl, '/uploads/c.jpg', reason: 'kept when the post is updated');
  });

  test('the controller turns the relative cover into a full address', () {
    final feed = FeedController(FakeFeedRepository.sample(now: DateTime.utc(2026, 10, 10, 12)));
    addTearDown(feed.dispose);
    expect(feed.coverUrl(Post.fromJson(_json(coverUrl: '/uploads/c.jpg'))), 'http://fake.test/uploads/c.jpg');
    expect(feed.coverUrl(Post.fromJson(_json())), isNull);
  });

  testWidgets('a card whose video is not loaded yet shows the cover instead of an empty frame', (tester) async {
    final post = Post.fromJson(_json(coverUrl: '/uploads/c.jpg'));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PostMedia(post: post, mediaUrl: 'http://x/a.mp4', coverUrl: 'http://x/c.jpg', muted: true, onToggleMute: () {}),
      ),
    ));
    await tester.pump();
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).url, 'http://x/c.jpg');
    expect(image.fit, BoxFit.contain, reason: 'fitted like the video, never cropped');
  });

  testWidgets('without a cover the frame stays empty, and a post still being made shows its status instead', (tester) async {
    final post = Post.fromJson(_json());
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PostMedia(post: post, mediaUrl: 'http://x/a.mp4', muted: true, onToggleMute: () {})),
    ));
    await tester.pump();
    expect(find.byType(Image), findsNothing);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PostMedia(post: post.copyWith(status: PostStatus.processing), mediaUrl: null, coverUrl: 'http://x/c.jpg', muted: true, onToggleMute: () {}),
      ),
    ));
    await tester.pump();
    expect(find.text('Processing…'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
