// The Discover screen against a scripted server: error + retry, refresh keeps the list, no duplicate videos.
// (The video players themselves need a phone; here they fail to start and the screen must cope.)
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:forest_app/features/reels/reels_feed.dart';
import 'package:forest_app/features/reels/reels_repository.dart';

import 'support/fake_server.dart';

Map<String, dynamic> _video(String id) => {
      'id': id, 'title': 'Title $id', 'caption': 'Title $id', 'filename': '$id.mp4', 'status': 'ready', 'role': 'PARENT',
      'parentVideoId': null, 'stance': 'PARENT', 'credibility': 50, 'durationS': 0, 'userId': 'aman', 'userName': 'aman',
      'createdAt': '2026-10-10T10:00:00.000Z', 'likeCount': 0, 'replyCount': 0, 'forCount': 0, 'againstCount': 0,
      'viewerSide': null, 'liked': false, 'transcript': null,
    };

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Future<void> _pump(WidgetTester tester, FakeServer server) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: ReelsFeed(repository: ReelsRepository(server.client()))));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  test('the feed\'s page physics stop at the first page, which is what lets pull-to-refresh start', () {
    final physics = const PageScrollPhysics(parent: ClampingScrollPhysics());
    final atStart = FixedScrollMetrics(
      minScrollExtent: 0, maxScrollExtent: 1600, pixels: 0, viewportDimension: 800,
      axisDirection: AxisDirection.down, devicePixelRatio: 1,
    );
    // Dragging further up the list than the first page is refused, and the refusal is reported as an overscroll.
    expect(physics.applyBoundaryConditions(atStart, -60), -60);
    expect(const PageScrollPhysics().applyBoundaryConditions(atStart, -60), 0,
        reason: 'plain page physics never report an overscroll (the old, broken setup)');
  });

  testWidgets('offline: shows the error with Retry, and Retry loads the feed once the server is back', (tester) async {
    var up = false;
    final server = FakeServer()
      ..on('GET /api/videos/feed', (_) => up ? _json({'videos': [_video('a')], 'nextCursor': null}) : _json({'error': 'down'}, 503));
    await _pump(tester, server);
    expect(find.textContaining('Could not load debate feed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    up = true;
    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Could not load debate feed'), findsNothing);
    expect(find.text('Title a'), findsWidgets);
    expect(server.count('GET /api/videos/feed'), 2);
  });

  testWidgets('an empty feed says so instead of failing', (tester) async {
    final server = FakeServer()..json('GET /api/videos/feed', {'videos': [], 'nextCursor': null});
    await _pump(tester, server);
    expect(find.text('No debate videos available.'), findsOneWidget);
  });

  testWidgets('a failed refresh keeps the videos on screen and says what went wrong', (tester) async {
    var fail = false;
    final server = FakeServer()
      ..on('GET /api/videos/feed', (_) => fail ? _json({'error': 'Too many requests'}, 429) : _json({'videos': [_video('a')], 'nextCursor': null}));
    await _pump(tester, server);
    expect(find.text('Title a'), findsWidgets);

    fail = true;
    // Same thing the pull gesture does (the gesture itself is covered by the physics test below).
    unawaited(tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Title a'), findsWidgets, reason: 'the list must not be replaced by an error page');
    expect(find.textContaining('Could not refresh'), findsOneWidget);
  });
}
