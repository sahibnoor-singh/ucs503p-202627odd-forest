// Tapping "N FOR · N AGAINST" opens the debate graph (the Discover tree screen), and the full-screen viewer lets taps through its
// shaded strips to the video's own buttons (CC, mute, progress bar).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:forest_app/features/reels/open_debate_graph.dart';
import 'package:forest_app/features/reels/reels_repository.dart';
import 'package:forest_app/features/reels/reply_tree_screen.dart';
import 'package:forest_app/models/post.dart';
import 'package:forest_app/services/api_client.dart';
import 'package:forest_app/ui/action_bar.dart';
import 'package:forest_app/ui/post_media.dart';

import 'support/harness.dart';

Post _post({int forCount = 2, int againstCount = 1}) => Post.fromJson({
      'id': 'reply1',
      'kind': 'VIDEO',
      'parentId': 'root1',
      'rootId': 'root1',
      'depth': 1,
      'title': null,
      'body': null,
      'mediaUrl': '/uploads/a.mp4',
      'stance': 'FOR',
      'status': 'READY',
      'summary': null,
      'createdAt': '2026-10-10T12:00:00.000Z',
      'likeCount': 0,
      'likedByMe': false,
      'replyCount': 0,
      'forCount': forCount,
      'againstCount': againstCount,
    });

ReelsRepository _repository(http.Response Function(http.Request) handler, [List<Uri>? seen]) {
  final client = MockClient((request) async {
    seen?.add(request.url);
    return handler(request);
  });
  return ReelsRepository(ApiClient(baseUrl: 'http://api.test', devUser: 'me', client: client));
}

Widget _app(ReelsRepository repository, Post post) => Provider<ReelsRepository>.value(
      value: repository,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(child: TextButton(onPressed: () => openDebateGraph(context, post), child: const Text('open graph'))),
          ),
        ),
      ),
    );

void main() {
  group('the score', () {
    testWidgets('is a button when something listens, and does not claim to be one otherwise', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ActionBar(post: _post(), onScore: () => taps++))));
      await tester.tap(find.text('2 FOR · 1 AGAINST'));
      expect(taps, 1);
      expect(find.bySemanticsLabel('Open the debate graph'), findsOneWidget);

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ActionBar(post: _post()))));
      await tester.tap(find.text('2 FOR · 1 AGAINST')); // nothing happens, and nothing breaks
      expect(tester.takeException(), isNull);
    });

    testWidgets('a post nobody has taken a side on shows no score', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ActionBar(post: _post(forCount: 0, againstCount: 0), onScore: () {}))));
      expect(find.textContaining('FOR'), findsNothing);
    });
  });

  group('openDebateGraph', () {
    final tree = jsonEncode([
      {'id': 'root1', 'filename': 'root.mp4', 'status': 'ready', 'role': 'PARENT', 'title': 'Phones in class?', 'userName': 'ananya_r'},
      {'id': 'reply1', 'filename': 'a.mp4', 'status': 'ready', 'role': 'CHILD', 'parent_video_id': 'root1', 'stance': 'FOR', 'userName': 'dev'},
    ]);

    testWidgets('loads the whole debate of that post and opens the tree screen on its root', (tester) async {
      final seen = <Uri>[];
      await tester.pumpWidget(_app(_repository((_) => http.Response(tree, 200, headers: {'content-type': 'application/json'}), seen), _post()));
      await tester.tap(find.text('open graph'));
      await settle(tester);

      expect(seen.first.path, '/api/videos/reply1/tree', reason: 'asked for the debate of the post that was tapped');
      final screen = tester.widget<ReplyTreeScreen>(find.byType(ReplyTreeScreen));
      expect(screen.rootVideo.id, 'root1', reason: 'the debate is drawn from its first opinion, not from the reply that was tapped');
      expect(screen.onSelectVideo, isNull, reason: 'there is no reel to go back to from Home, so no "Watch in Reel" button');
      expect(find.text('Watch in Reel'), findsNothing);
      expect(find.text('Debate Tree'), findsOneWidget);
    });

    testWidgets('a server that cannot be reached leaves a message, not a crash', (tester) async {
      await tester.pumpWidget(_app(_repository((_) => http.Response('{"error":"boom"}', 500, headers: {'content-type': 'application/json'})), _post()));
      await tester.tap(find.text('open graph'));
      await settle(tester);
      expect(find.byType(ReplyTreeScreen), findsNothing);
      expect(find.text('Could not open the debate graph. Try again.'), findsOneWidget);
    });
  });

  testWidgets('the full-screen viewer lets taps through its shaded top and bottom strips', (tester) async {
    useTallScreen(tester);
    await pumpHome(tester, sampleRepo());
    await tester.tap(find.byWidgetPredicate((w) => w is PostMedia && w.post.id == 'p1' && !w.fullscreen).first);
    await settle(tester);
    expect(find.byTooltip('Back to feed'), findsOneWidget);

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    bool shadeTakesTapAt(Offset at) {
      final result = HitTestResult();
      tester.binding.hitTestInView(result, at, tester.view.viewId);
      return result.path.map((entry) => entry.target).whereType<RenderDecoratedBox>().any((box) {
        final d = box.decoration;
        return d is BoxDecoration && d.gradient != null;
      });
    }

    // where the CC and mute buttons sit (top right), and where the progress bar sits (the bottom edge)
    expect(shadeTakesTapAt(Offset(size.width - 60, 60)), isFalse, reason: 'CC and mute must stay tappable');
    expect(shadeTakesTapAt(Offset(size.width / 2, size.height - 12)), isFalse, reason: 'the progress bar must stay draggable');
  });
}
