// "You have heard both sides": the note shown on a debate, driven by what was actually watched.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:forest_app/features/reels/reel_controller.dart';
import 'package:forest_app/features/reels/reels_repository.dart';
import 'package:forest_app/features/reels/sides_heard.dart';
import 'package:forest_app/features/reels/video_reel.dart';
import 'package:forest_app/models/video.dart';

import 'support/fake_server.dart';

Map<String, dynamic> _v(String id, {String stance = 'PARENT', String? parent}) => {
      'id': id, 'title': 'Title $id', 'filename': '$id.mp4', 'status': 'ready', 'role': parent == null ? 'PARENT' : 'REPLY',
      'stance': stance, 'parentVideoId': parent, 'userName': 'aman', 'createdAt': 't', 'likeCount': 0, 'replyCount': 0,
      'forCount': 0, 'againstCount': 0,
    };

http.Response _ok(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

void main() {
  group('SidesHeard', () {
    test('says "both" exactly once, only for FOR and AGAINST', () {
      final s = SidesHeard();
      expect(s.record('d1', 'PARENT'), isFalse);
      expect(s.record('d1', 'UNRESOLVED'), isFalse);
      expect(s.record('d1', 'for'), isFalse, reason: 'one side is not both');
      expect(s.record('d1', 'FOR'), isFalse, reason: 'the same side twice is still one side');
      expect(s.heardBoth('d1'), isFalse);
      expect(s.record('d1', 'AGAINST'), isTrue);
      expect(s.record('d1', 'AGAINST'), isFalse, reason: 'told once');
      expect(s.heardBoth('d1'), isTrue);
      expect(s.heardBoth('other-debate'), isFalse, reason: 'debates are counted separately');
    });

    test('the note points to the side not yet heard, in words that match the swipe directions', () {
      final s = SidesHeard();
      expect(s.noteFor('d', onRoot: true), isNull, reason: 'nothing heard yet, nothing to say');
      expect(s.noteFor('d', onRoot: false), isNull, reason: 'nothing useful to say on a reply nobody has watched yet');
      s.record('d', 'FOR');
      expect(s.noteFor('d', onRoot: true)!.text, contains('Now hear AGAINST'));
      expect(s.noteFor('d', onRoot: false)!.text, contains('Go back'), reason: 'on a reply, right goes back');
      final other = SidesHeard()..record('d', 'AGAINST');
      expect(other.noteFor('d', onRoot: true)!.text, contains('Now hear FOR'));
      s.record('d', 'AGAINST');
      final done = s.noteFor('d', onRoot: true)!;
      expect(done.done, isTrue);
      expect(done.text, 'You have heard both sides');
    });
  });

  testWidgets('a debate with replies on both sides says nothing until a side has been heard', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tree = [
      _v('root'),
      _v('f1', stance: 'FOR', parent: 'root'),
      _v('a1', stance: 'AGAINST', parent: 'root'),
    ];
    final server = FakeServer()
      ..on('GET /api/videos/root/tree', (_) => _ok(tree))
      ..on('GET /api/videos/root/replies', (_) => _ok([]));
    final reel = ReelController(muteNotifier: ValueNotifier(false));
    addTearDown(reel.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VideoReel(
          rootVideo: Video.fromJson(_v('root')), index: 0, reelController: reel, repository: ReelsRepository(server.client()),
          onOpenTree: () {}, onOpenReplySheet: () {},
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('sides-note')), findsNothing, reason: 'nothing has been heard yet, so nothing to say');
  });

  testWidgets('watching a FOR reply for a few seconds counts FOR as heard and says what is left', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tree = [_v('root'), _v('f1', stance: 'FOR', parent: 'root'), _v('a1', stance: 'AGAINST', parent: 'root')];
    final server = FakeServer()
      ..on('GET /api/videos/root/tree', (_) => _ok(tree))
      ..on('GET /api/videos/root/replies', (_) => _ok([]));
    final reel = ReelController(muteNotifier: ValueNotifier(false));
    addTearDown(reel.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VideoReel(
          rootVideo: Video.fromJson(_v('root')),
          activeVideo: Video.fromJson(_v('f1', stance: 'FOR', parent: 'root')),
          index: 0, reelController: reel, repository: ReelsRepository(server.client()),
          onOpenTree: () {}, onOpenReplySheet: () {},
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('You have heard FOR'), findsNothing, reason: 'not counted before it has been watched');
    await tester.pump(const Duration(seconds: 4));
    expect(reel.sidesHeard.of('root'), {'FOR'});
    expect(find.text('You have heard FOR. Go back to hear AGAINST'), findsOneWidget);
    reel.sidesHeard.record('root', 'AGAINST'); // the other side was heard on another visit to this debate
    await tester.pump();
    expect(reel.sidesHeard.heardBoth('root'), isTrue);
  });
}
