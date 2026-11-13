// The video screen: a labelled Reply, the author's picture and name that open the profile, a long title that opens and closes,
// a debate bar whose ends are buttons, and arrow keys for a laptop.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:forest_app/features/reels/reel_controller.dart';
import 'package:forest_app/features/reels/reel_overlay.dart';
import 'package:forest_app/features/reels/reels_repository.dart';
import 'package:forest_app/features/reels/video_reel.dart';
import 'package:forest_app/models/video.dart';

import 'support/fake_server.dart';

const _long = 'Was the police response to the peaceful agitation at Jantar Mantar proportionate, and who should be held accountable if it was not, '
    'given everything that the courts have said about the right to protest in the last ten years?';

Video _video({String title = 'Short title', String? authorId = 'u-harpreet', String stance = 'PARENT', String id = 'root', String? parent}) => Video.fromJson({
      'id': id, 'title': title, 'filename': '$id.mp4', 'status': 'ready', 'role': parent == null ? 'PARENT' : 'CHILD', 'stance': stance,
      'parentVideoId': parent, 'userName': 'harpreet_g', 'authorId': authorId, 'createdAt': 't', 'likeCount': 0, 'replyCount': 0,
      'forCount': 0, 'againstCount': 0,
    });

Widget _overlay(Video v, {bool expanded = false, VoidCallback? onToggle, VoidCallback? onReply, VoidCallback? onProfile, VoidCallback? onFor, VoidCallback? onAgainst, VoidCallback? onFollow, bool following = false, VoidCallback? onComments, int fors = 2, int againsts = 3}) =>
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 700,
          child: ReelOverlay(
            video: v, rootVideo: v, muteNotifier: ValueNotifier(false), onToggleMute: () {}, onLike: () {}, onOpenTree: () {},
            onOpenReplySheet: onReply ?? () {}, onMoreOptions: () {}, forCount: fors, againstCount: againsts, onOpenProfile: onProfile,
            onShowFor: onFor, onShowAgainst: onAgainst, titleExpanded: expanded, onToggleTitle: onToggle, onFollow: onFollow, following: following,
            onComments: onComments,
          ),
        ),
      ),
    );

http.Response _ok(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

void main() {
  displayTitleTests();
  testWidgets('Reply is a labelled button with the common reply arrow, not a camera', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_overlay(_video(), onReply: () => taps++));
    await tester.tap(find.text('Reply'));
    expect(taps, 1);
    expect(find.byIcon(Icons.reply_rounded), findsOneWidget);
    expect(find.byIcon(Icons.videocam_rounded), findsNothing);
  });

  testWidgets('the comment button shows only when someone listens, and opens them', (tester) async {
    await tester.pumpWidget(_overlay(_video()));
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsNothing);
    var taps = 0;
    await tester.pumpWidget(_overlay(_video(), onComments: () => taps++));
    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    expect(taps, 1);
  });

  testWidgets('Follow sits beside the name; it turns into Following; no Follow when there is nobody to follow', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_overlay(_video(), onFollow: () => taps++));
    expect(find.text('Follow'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reel-follow')));
    expect(taps, 1);
    await tester.pumpWidget(_overlay(_video(), onFollow: () => taps++, following: true));
    expect(find.text('Following'), findsOneWidget);
    await tester.pumpWidget(_overlay(_video()));
    expect(find.byKey(const Key('reel-follow')), findsNothing);
  });

  testWidgets('the tally is plain text, with no coloured bar and no swipe hint', (tester) async {
    await tester.pumpWidget(_overlay(_video()));
    expect(find.text('2 FOR'), findsOneWidget);
    expect(find.text('3 AGAINST'), findsOneWidget);
    expect(find.textContaining('Swipe'), findsNothing);
  });

  testWidgets('the author row opens the profile; without an author id nothing is tappable', (tester) async {
    var opened = 0;
    await tester.pumpWidget(_overlay(_video(), onProfile: () => opened++));
    await tester.tap(find.text('@harpreet_g'));
    expect(opened, 1);
    await tester.pumpWidget(_overlay(_video(authorId: null)));
    await tester.tap(find.text('@harpreet_g'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short title has no "more"; a long one shows two lines and "more", then all of it with "less"', (tester) async {
    await tester.pumpWidget(_overlay(_video()));
    expect(find.byKey(const Key('title-more')), findsNothing);

    var expanded = false;
    late StateSetter set;
    await tester.pumpWidget(StatefulBuilder(builder: (context, setState) {
      set = setState;
      return _overlay(_video(title: _long), expanded: expanded, onToggle: () => set(() => expanded = !expanded));
    }));
    expect(find.byKey(const Key('title-more')), findsOneWidget);
    expect(find.byKey(const Key('title-expanded')), findsNothing);
    // strictly two lines, "more" included: the title is never taller than two lines of 16 px text at 1.3
    expect(tester.getSize(find.byKey(const Key('title-more'))).height, lessThanOrEqualTo(16 * 1.3 * 2 + 1));
    expect(find.textContaining('more', findRichText: true), findsOneWidget);
    await tester.tap(find.byKey(const Key('title-more')));
    await tester.pump();
    expect(find.byKey(const Key('title-expanded')), findsOneWidget);
    expect(find.byKey(const Key('title-less')), findsOneWidget);
    await tester.tap(find.byKey(const Key('title-less')));
    await tester.pump();
    expect(find.byKey(const Key('title-expanded')), findsNothing);
    expect(find.byKey(const Key('title-more')), findsOneWidget);
  });

  testWidgets('both ends of the debate bar are buttons', (tester) async {
    var fors = 0, againsts = 0;
    await tester.pumpWidget(_overlay(_video(), onFor: () => fors++, onAgainst: () => againsts++));
    await tester.tap(find.byKey(const Key('bar-for')));
    await tester.tap(find.byKey(const Key('bar-against')));
    expect((fors, againsts), (1, 1));
    expect(find.text('2 FOR'), findsOneWidget);
    expect(find.text('3 AGAINST'), findsOneWidget);
  });

  group('in the reel', () {
    Future<(ReelController, FakeServer)> pumpReel(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Map<String, dynamic> json(Video v) => {
            'id': v.id, 'title': v.title, 'filename': '${v.id}.mp4', 'status': 'ready', 'role': v.role, 'stance': v.stance,
            'parentVideoId': v.parentVideoId, 'userName': v.userName, 'authorId': v.authorId, 'createdAt': 't', 'likeCount': 0,
            'replyCount': 0, 'forCount': 0, 'againstCount': 0,
          };
      final tree = [
        _video(title: _long),
        _video(id: 'f1', title: 'The FOR answer', stance: 'FOR', parent: 'root'),
        _video(id: 'a1', title: 'The AGAINST answer', stance: 'AGAINST', parent: 'root'),
      ];
      final server = FakeServer()
        ..on('GET /api/videos/root/tree', (_) => _ok(tree.map(json).toList()))
        ..on('GET /api/videos/root/replies', (_) => _ok([]));
      final reel = ReelController(muteNotifier: ValueNotifier(false));
      addTearDown(reel.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: VideoReel(rootVideo: tree.first, index: 0, reelController: reel, repository: ReelsRepository(server.client()), onOpenTree: () {}, onOpenReplySheet: () {}),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      return (reel, server);
    }

    testWidgets('a tap on the picture closes an open title instead of pausing', (tester) async {
      await pumpReel(tester);
      await tester.tap(find.byKey(const Key('title-more')));
      await tester.pump();
      expect(find.byKey(const Key('title-expanded')), findsOneWidget);
      await tester.tapAt(const Offset(200, 200));
      await tester.pump();
      expect(find.byKey(const Key('title-expanded')), findsNothing);
    });

    testWidgets('the arrow keys do what the swipes do: left goes to a FOR reply, then right comes back', (tester) async {
      await pumpReel(tester);
      expect(find.byKey(const Key('title-more')), findsOneWidget, reason: 'starts on the long main video');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('The FOR answer'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // on a reply, right goes back to what it answers
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('The FOR answer'), findsNothing);
    });

    testWidgets('tapping AGAINST on the bar goes to the AGAINST reply', (tester) async {
      await pumpReel(tester);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('bar-against')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('The AGAINST answer'), findsOneWidget);
    });
  });
}

void displayTitleTests() {
  test('a video is never called by its id on screen', () {
    expect(_video(title: 'Short title').displayTitle, 'Short title');
    final untitled = Video.fromJson({
      'id': '2fedebea-81fe-445f-aeab-1089fd951092', 'filename': 'x.mp4', 'status': 'ready', 'role': 'CHILD', 'stance': 'FOR',
      'parentVideoId': 'root', 'userName': 'ishaan_c', 'createdAt': 't', 'likeCount': 0, 'replyCount': 0, 'forCount': 0, 'againstCount': 0,
    });
    expect(untitled.displayTitle, 'Video reply by @ishaan_c');
    expect(untitled.displayTitle, isNot(contains('2fedebea')));
    final summarised = untitled.copyWith(summary: 'A student argues that the police response was disproportionate.');
    expect(summarised.displayTitle, startsWith('A student argues'));
  });
}
