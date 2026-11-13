// The Discover grid: where tiles go on any screen width (pure math), how pages load, and what the screen does with them.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:forest_app/features/discover/discover_controller.dart';
import 'package:forest_app/features/discover/discover_screen.dart';
import 'package:forest_app/features/discover/discover_tile.dart';
import 'package:forest_app/features/discover/grid_layout.dart';
import 'package:forest_app/features/discover/search_repository.dart';
import 'package:forest_app/features/reels/reels_feed.dart';
import 'package:forest_app/features/reels/reels_repository.dart';
import 'package:forest_app/models/video.dart';
import 'package:forest_app/ui/chips.dart';

import 'support/fake_server.dart';

Map<String, dynamic> _video(String id, {String? cover, bool bot = false, int forCount = 0, int againstCount = 0}) => {
      'id': id, 'title': 'Title $id', 'caption': 'Title $id', 'filename': '$id.mp4', 'coverUrl': cover, 'status': 'ready', 'role': 'PARENT',
      'parentVideoId': null, 'stance': 'PARENT', 'credibility': 50, 'durationS': 0, 'userId': 'aman', 'userName': 'aman', 'isBot': bot,
      'createdAt': '2026-10-10T10:00:00.000Z', 'likeCount': 0, 'replyCount': 0, 'forCount': forCount, 'againstCount': againstCount,
      'viewerSide': null, 'liked': false, 'transcript': null,
    };

http.Response _reply(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

List<Map<String, dynamic>> _videos(int from, int count, {bool cover = false}) =>
    [for (var i = from; i < from + count; i++) _video('v$i', cover: cover ? '/uploads/v$i-cover.jpg' : null)];

void main() {
  group('layout', () {
    test('every block is filled completely, with no tile overlapping another', () {
      for (final pattern in blockPatterns) {
        final taken = <String>{};
        for (final s in pattern) {
          for (var c = s.col; c < s.col + s.w; c++) {
            for (var r = s.row; r < s.row + s.h; r++) {
              expect(c < 3 && r < 3, isTrue, reason: 'inside the 3x3 block');
              expect(taken.add('$c,$r'), isTrue, reason: 'cell $c,$r used twice');
            }
          }
        }
        expect(taken.length, 9, reason: 'no hole in the block');
      }
    });

    test('the biggest slot of every block comes first, so the best-ranked post gets the most room', () {
      for (final pattern in blockPatterns) {
        final area = pattern.map((s) => s.w * s.h).toList();
        expect(area.first, area.reduce((a, b) => a > b ? a : b));
      }
    });

    test('columns follow the screen: one block on a phone, more blocks side by side on a wide screen', () {
      expect(blocksAcross(320), 1);
      expect(blocksAcross(411), 1);
      expect(blocksAcross(559), 1);
      expect(blocksAcross(600), 2);
      expect(blocksAcross(840), 3);
      expect(blocksAcross(5000), 4);
    });

    test('tiles always add up to the exact width, on any phone', () {
      for (final width in [320.0, 360.0, 393.0, 411.0, 430.0, 600.0, 768.0, 1024.0]) {
        final plan = planGrid(count: 60, width: width, complete: true);
        for (final band in plan.bands) {
          for (final tile in band.tiles) {
            expect(tile.rect.left, greaterThanOrEqualTo(0));
            expect(tile.rect.right, lessThanOrEqualTo(width + 0.001), reason: 'width $width');
          }
        }
        final first = plan.bands.first.tiles;
        final right = first.map((t) => t.rect.right).reduce((a, b) => a > b ? a : b);
        expect(right, closeTo(width, 0.001), reason: 'the grid spans the whole width at $width');
      }
    });

    test('every post is placed exactly once, in order, when all of them are loaded', () {
      for (final width in [360.0, 800.0]) {
        for (final count in [0, 1, 5, 6, 7, 14, 20, 28, 29, 61]) {
          final plan = planGrid(count: count, width: width, complete: true);
          final indexes = [for (final b in plan.bands) for (final t in b.tiles) t.index]..sort();
          expect(indexes, [for (var i = 0; i < count; i++) i], reason: '$count posts at $width');
          expect(plan.placed, count);
        }
      }
    });

    test('while more can load, a block that would not be full waits instead of leaving a hole', () {
      final plan = planGrid(count: 9, width: 360, complete: false);
      expect(plan.placed, 6, reason: 'one full block (6 tiles); the other 3 wait');
      final wide = planGrid(count: 9, width: 800, complete: false);
      expect(wide.placed, 0, reason: 'a band of 3 blocks needs 6 + 8 + 6 tiles before it can show');
    });

    test('tiles of one band never overlap', () {
      final plan = planGrid(count: 30, width: 600, complete: true);
      for (final band in plan.bands) {
        final tiles = band.tiles;
        for (var i = 0; i < tiles.length; i++) {
          for (var j = i + 1; j < tiles.length; j++) {
            expect(tiles[i].rect.deflate(0.01).overlaps(tiles[j].rect.deflate(0.01)), isFalse, reason: '${tiles[i].index} and ${tiles[j].index}');
          }
        }
        for (final tile in tiles) {
          expect(tile.rect.bottom, lessThanOrEqualTo(band.height + 0.001));
        }
      }
    });
  });

  group('controller', () {
    test('loads a page, then the next from its cursor, without repeating a post', () async {
      final server = FakeServer()
        ..on('GET /api/videos/feed', (s) {
          final cursor = s.uri.queryParameters['cursor'];
          return _reply(cursor == null
              ? {'videos': _videos(0, 3), 'nextCursor': 'c1'}
              : {'videos': [..._videos(2, 3)], 'nextCursor': null}); // v2 again: the server must not, but if it does we drop it
        });
      final c = DiscoverController(ReelsRepository(server.client()), pageSize: 3);
      await c.refresh();
      expect(c.videos.map((v) => v.id), ['v0', 'v1', 'v2']);
      expect(c.hasMore, isTrue);
      expect(server.last('GET /api/videos/feed').uri.queryParameters['limit'], '3');

      await c.loadMore();
      expect(c.videos.map((v) => v.id), ['v0', 'v1', 'v2', 'v3', 'v4']);
      expect(c.hasMore, isFalse);
      expect(server.last('GET /api/videos/feed').uri.queryParameters['cursor'], 'c1');
      await c.loadMore();
      expect(server.count('GET /api/videos/feed'), 2, reason: 'nothing is asked for once there is no more');
    });

    test('a failed first load says why; a failed refresh keeps the posts; a failed next page can be retried', () async {
      var fail = false;
      final server = FakeServer()
        ..on('GET /api/videos/feed', (s) {
          if (fail) return _reply({'error': 'down'}, status: 503);
          return _reply({'videos': _videos(0, 2), 'nextCursor': 'c1'});
        });
      fail = true;
      final c = DiscoverController(ReelsRepository(server.client()));
      await c.refresh();
      expect(c.videos, isEmpty);
      expect(c.error, 'down');
      expect(c.loading, isFalse);

      fail = false;
      await c.refresh();
      expect(c.error, isNull);
      expect(c.videos, hasLength(2));

      fail = true;
      await c.refresh();
      expect(c.videos, hasLength(2), reason: 'the posts stay');
      expect(c.error, isNull);
      expect(c.refreshError, 'down');

      await c.loadMore();
      expect(c.moreFailed, isTrue);
      expect(c.loadingMore, isFalse);
      fail = false;
      await c.loadMore();
      expect(c.moreFailed, isFalse);
    });

    test('an answer to an older refresh is dropped', () async {
      final answers = <String>[];
      final server = FakeServer()
        ..on('GET /api/videos/feed', (s) {
          answers.add('x');
          return _reply({'videos': _videos(answers.length == 1 ? 0 : 10, 1), 'nextCursor': null});
        });
      final c = DiscoverController(ReelsRepository(server.client()));
      final first = c.refresh();
      final second = c.refresh();
      await Future.wait([first, second]);
      expect(c.videos.single.id, 'v10', reason: 'the later question wins');
    });
  });

  group('screen', () {
    Future<void> pump(WidgetTester tester, FakeServer server, {Size size = const Size(400, 800)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: DiscoverScreen(
          repository: ReelsRepository(server.client()),
          searchRepository: SearchRepository(server.client()),
          setFollowing: (_, _) async {},
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    FakeServer feed(Map<String, dynamic> body) => FakeServer()..json('GET /api/videos/feed', body);

    testWidgets('shows the posts as tiles, with the BOT label and the debate score where they apply', (tester) async {
      await pump(tester, feed({
        'videos': [_video('a', forCount: 3, againstCount: 1), _video('b', bot: true), ..._videos(2, 4)],
        'nextCursor': null,
      }));
      expect(find.byType(DiscoverTile), findsNWidgets(6));
      expect(find.byType(BotTag), findsOneWidget, reason: 'only the bot account is labelled, and it always is');
      expect(find.text('3'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text("You've seen everything for now"), findsOneWidget);
    });

    testWidgets('a post without a picture shows its title instead of an empty square', (tester) async {
      await pump(tester, feed({'videos': _videos(0, 6), 'nextCursor': null}));
      expect(find.text('Title v1'), findsOneWidget);
    });

    testWidgets('the same posts fill a narrow and a wide screen with no overflow', (tester) async {
      final server = feed({'videos': _videos(0, 28), 'nextCursor': null});
      await pump(tester, server, size: const Size(320, 640));
      expect(tester.takeException(), isNull);
      final narrow = tester.getSize(find.byType(DiscoverTile).first);
      expect(narrow.width, greaterThan(100));

      await pump(tester, server, size: const Size(900, 700));
      expect(tester.takeException(), isNull);
      expect(find.byType(DiscoverTile), findsWidgets);
    });

    testWidgets('a server that is down shows why, and Try again loads the posts', (tester) async {
      var up = false;
      final server = FakeServer()
        ..on('GET /api/videos/feed', (_) => up ? _reply({'videos': _videos(0, 6), 'nextCursor': null}) : _reply({'error': 'Server is down'}, status: 503));
      await pump(tester, server);
      expect(find.text('Server is down'), findsOneWidget);
      expect(find.byType(DiscoverTile), findsNothing);
      up = true;
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(DiscoverTile), findsNWidgets(6));
    });

    testWidgets('no posts at all says so', (tester) async {
      await pump(tester, feed({'videos': [], 'nextCursor': null}));
      expect(find.textContaining('Nothing to discover yet'), findsOneWidget);
    });

    testWidgets('more loads as the end nears, and a short first page does not wait for a scroll', (tester) async {
      var pages = 0;
      final server = FakeServer()
        ..on('GET /api/videos/feed', (s) {
          pages++;
          final cursor = s.uri.queryParameters['cursor'];
          return _reply(cursor == null
              ? {'videos': _videos(0, 6), 'nextCursor': 'c1'}
              : {'videos': _videos(6, 6), 'nextCursor': null});
        });
      await pump(tester, server);
      await tester.pump(const Duration(milliseconds: 100));
      expect(pages, 2, reason: 'six tiles are shorter than the screen, so the next page is fetched at once');
      expect(find.byType(DiscoverTile), findsNWidgets(12));
    });

    testWidgets('tapping a tile opens the feed on that post and carries on from the grid cursor', (tester) async {
      final server = feed({'videos': _videos(0, 6), 'nextCursor': 'next'});
      await pump(tester, server);
      await tester.tap(find.text('Title v2').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final reels = tester.widget<ReelsFeed>(find.byType(ReelsFeed));
      expect(reels.initialDebateRoots!.map((v) => v.id), ['v2', 'v3', 'v4', 'v5'], reason: 'from the tapped post on');
      expect(reels.initialCursor, 'next');
      expect(reels.onClose, isNotNull);
    });
  });

  test('Video reads coverUrl and isBot from the server', () {
    final v = Video.fromJson(_video('a', cover: '/uploads/a-cover.jpg', bot: true));
    expect(v.coverUrl, '/uploads/a-cover.jpg');
    expect(v.isBot, isTrue);
    expect(Video.fromJson(_video('b')).coverUrl, isNull);
    expect(Video.fromJson({..._video('b'), 'coverUrl': ''}).coverUrl, isNull, reason: 'an empty string is no picture');
  });
}
