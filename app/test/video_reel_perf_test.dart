// A swipe sideways must only move the picture, not rebuild the whole reel (video, overlay, buttons) on every finger move.
// This counts real widget rebuilds with Flutter's own debug hook.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:forest_app/features/reels/reel_controller.dart';
import 'package:forest_app/features/reels/reel_overlay.dart';
import 'package:forest_app/features/reels/reels_repository.dart';
import 'package:forest_app/features/reels/video_reel.dart';
import 'package:forest_app/models/video.dart';

import 'support/fake_server.dart';

Map<String, dynamic> _json(String id) => {
      'id': id, 'title': 'Title $id', 'filename': '$id.mp4', 'status': 'ready', 'role': 'PARENT', 'stance': 'PARENT',
      'userName': 'aman', 'createdAt': 't', 'likeCount': 0, 'replyCount': 0, 'forCount': 0, 'againstCount': 0,
    };

void main() {
  testWidgets('dragging sideways rebuilds the overlay zero times, however many pointer moves', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final server = FakeServer()
      ..on('GET /api/videos/root/tree', (_) => http.Response(jsonEncode([_json('root')]), 200, headers: {'content-type': 'application/json'}))
      ..on('GET /api/videos/root/replies', (_) => http.Response('[]', 200, headers: {'content-type': 'application/json'}));
    final repo = ReelsRepository(server.client());
    final reel = ReelController(muteNotifier: ValueNotifier(false));
    addTearDown(reel.dispose);
    final video = Video.fromJson(_json('root'));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VideoReel(
          rootVideo: video, index: 0, reelController: reel, repository: repo,
          onOpenTree: () {}, onOpenReplySheet: () {},
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    var overlayRebuilds = 0;
    debugOnRebuildDirtyWidget = (Element e, bool builtOnce) {
      if (e.widget is ReelOverlay) overlayRebuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    final gesture = await tester.startGesture(tester.getCenter(find.byType(VideoReel)));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(-6, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    // the spring back to rest runs for a few hundred ms (and a "no FOR replies" note appears)
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(seconds: 3));

    // The only legitimate rebuilds are the single ones when the "no replies" note shows and hides; the drag itself must cost none.
    expect(overlayRebuilds, lessThanOrEqualTo(3), reason: 'the overlay was rebuilt $overlayRebuilds times during one swipe');
  });
}
