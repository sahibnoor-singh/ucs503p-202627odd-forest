// Discover's vertical list is a watch history: going from a video to one of its replies puts the video you left on the page above
// (older ones one further up), so swiping down walks back through what you watched, in order. (The players themselves need a
// phone; here they fail to start and the screen must cope.)


import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:forest_app/features/reels/reels_feed.dart';
import 'package:forest_app/features/reels/reels_repository.dart';
import 'package:forest_app/features/reels/video_reel.dart';

import 'support/fake_server.dart';

Map<String, dynamic> _video(String id, {String? parent, String stance = 'PARENT', String role = 'PARENT'}) => {
      'id': id, 'title': 'Title $id', 'caption': 'Title $id', 'filename': '$id.mp4', 'status': 'ready', 'role': role,
      'parentVideoId': parent, 'stance': stance, 'credibility': 50, 'durationS': 0, 'userId': 'aman', 'userName': 'aman',
      'createdAt': '2026-10-10T10:00:00.000Z', 'likeCount': 0, 'replyCount': 0, 'forCount': 0, 'againstCount': 0,
      'viewerSide': null, 'liked': false, 'transcript': null,
    };

/// Two debates (a, b). Debate a: a <- fa (FOR) <- fa2 (FOR), and aa (AGAINST) answering a.
FakeServer _server() => FakeServer()
  ..json('GET /api/videos/feed', {'videos': [_video('a'), _video('b')], 'nextCursor': null})
  ..json('GET /api/videos/a/tree', [
    _video('a'),
    _video('fa', parent: 'a', stance: 'FOR', role: 'CHILD'),
    _video('aa', parent: 'a', stance: 'AGAINST', role: 'CHILD'),
    _video('fa2', parent: 'fa', stance: 'FOR', role: 'CHILD'),
  ])
  ..json('GET /api/videos/b/tree', [_video('b')])
  ..json('GET /api/videos/fa/tree', [_video('a')])
  ..json('GET /api/videos/a/replies', [])
  ..json('GET /api/videos/fa/replies', [])
  ..json('GET /api/videos/b/replies', []);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _pump(WidgetTester tester, FakeServer server) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: ReelsFeed(repository: ReelsRepository(server.client()))));
  await _settle(tester);
}

/// The reel that is on screen (the others are built a page away, off screen).
Finder get _onScreen => find.byWidgetPredicate((w) => w is VideoReel).hitTestable();

Future<void> _swipeLeft(WidgetTester tester) async {
  await tester.drag(find.byType(VideoReel).hitTestable().first, const Offset(-220, 0));
  await _settle(tester);
}

Future<void> _swipeDown(WidgetTester tester) async {
  await tester.fling(find.byType(VideoReel).hitTestable().first, const Offset(0, 500), 1500);
  await _settle(tester);
}

Future<void> _swipeUp(WidgetTester tester) async {
  await tester.fling(find.byType(VideoReel).hitTestable().first, const Offset(0, -500), 1500);
  await _settle(tester);
}

/// The title showing on the reel that is on screen (the overlay writes the video's title).
String? _showing(WidgetTester tester) {
  for (final id in ['a', 'fa', 'fa2', 'aa', 'b']) {
    final title = find.descendant(of: _onScreen, matching: find.text('Title $id'));
    if (title.evaluate().isNotEmpty) return id;
  }
  return null;
}

void main() {
  testWidgets('going to a reply puts the video you left on the page above, and swiping down goes back to it', (tester) async {
    await _pump(tester, _server());
    expect(_showing(tester), 'a');

    await _swipeLeft(tester); // FOR
    expect(_showing(tester), 'fa', reason: 'the swipe took us to the FOR reply');

    await _swipeDown(tester);
    expect(_showing(tester), 'a', reason: 'one swipe down is the video we were just watching');

    await _swipeUp(tester);
    expect(_showing(tester), 'fa', reason: 'and back up to the reply, which now sits below it');

    await _swipeUp(tester);
    expect(_showing(tester), 'b', reason: 'the next page is still the next video of the feed');
  });

  testWidgets('every hop adds a page above: two hops, two swipes down to get back to where you started', (tester) async {
    await _pump(tester, _server());
    await _swipeLeft(tester); // a -> fa
    await _swipeLeft(tester); // fa -> fa2
    expect(_showing(tester), 'fa2');

    await _swipeDown(tester);
    expect(_showing(tester), 'fa', reason: 'the video watched just before');
    await _swipeDown(tester);
    expect(_showing(tester), 'a', reason: 'and the one before that: the older one was pushed one further up');
  });

  testWidgets('"Parent video" goes up to the page above when that is the parent, without adding another page', (tester) async {
    await _pump(tester, _server());
    await _swipeLeft(tester); // a -> fa
    expect(find.text('Parent video'), findsWidgets);

    await tester.tap(find.text('Parent video').hitTestable().first);
    await _settle(tester);
    expect(_showing(tester), 'a');

    // nothing was inserted: the page below is still the reply, then the next video
    await _swipeUp(tester);
    expect(_showing(tester), 'fa');
    await _swipeUp(tester);
    expect(_showing(tester), 'b');
  });

  testWidgets('swiping right on a reply returns to its parent the same way', (tester) async {
    await _pump(tester, _server());
    await _swipeLeft(tester); // a -> fa
    await tester.drag(find.byType(VideoReel).hitTestable().first, const Offset(220, 0));
    await _settle(tester);
    expect(_showing(tester), 'a');
  });

  testWidgets('a debate that was watched is not offered again further down the feed', (tester) async {
    await _pump(tester, _server());
    await _swipeLeft(tester);
    await _swipeDown(tester);
    // a (watched), fa, b: going all the way down never shows `a` twice
    await _swipeUp(tester);
    await _swipeUp(tester);
    expect(_showing(tester), 'b');
    expect(find.text('Title a'), findsNothing, reason: 'no second copy of the first debate is built near the end of the list');
  });
}
