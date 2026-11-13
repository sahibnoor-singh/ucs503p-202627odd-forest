// Video posts: the trim rules, the file rules, and the trim and sound panels.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:forest_app/data/fake_feed_repository.dart';
import 'package:forest_app/features/editor/editor_controller.dart';
import 'package:forest_app/features/editor/editor_pickers.dart';
import 'package:forest_app/features/editor/editor_screen.dart';
import 'package:forest_app/features/editor/recipe.dart';
import 'package:forest_app/features/home/feed_controller.dart';
import 'package:forest_app/theme/forest_theme.dart';

import 'editor_photos_test.dart' show FakePickers;
import 'support/harness.dart';

late Directory _dir;

String _file(String name, {int bytes = 16}) {
  final f = File('${_dir.path}/$name')..writeAsBytesSync(List.filled(bytes, 3));
  return f.path;
}

void main() {
  setUp(() => _dir = Directory.systemTemp.createTempSync('forest_video'));
  tearDown(() => _dir.deleteSync(recursive: true));

  group('controller', () {
    test('a picked video starts with its first minute kept', () {
      final c = EditorController(mode: EditorMode.video);
      addTearDown(c.dispose);
      expect(c.problem, 'Choose or record a video first.');
      c.setVideo(_file('a.mp4'), 25);
      expect(c.recipe.trim!.startSec, 0);
      expect(c.recipe.trim!.endSec, 25);
      expect(c.problem, isNull);

      c.setVideo(_file('b.mp4'), 200);
      expect(c.recipe.trim!.endSec, 60, reason: 'a long video starts at its first 60 seconds');
      expect(c.length, 60);
      expect(c.problem, isNull);
    });

    test('the trim handles keep between half a second and a minute', () {
      final c = EditorController(mode: EditorMode.video);
      addTearDown(c.dispose);
      c.setVideo(_file('a.mp4'), 100);
      c.setTrim(end: 100); // would be 100 s: the start is pushed along
      expect(c.recipe.trim!.length, 60);
      expect(c.recipe.trim!.endSec, 100);
      c.setTrim(start: 99.9);
      expect(c.recipe.trim!.length, greaterThanOrEqualTo(0.5));
      expect(c.recipe.trim!.endSec, 100, reason: 'dragging the start never moves the end');
      c.setTrim(start: 10, end: 20);
      expect(c.recipe.trim!.startSec, 10);
      expect(c.recipe.trim!.endSec, 20);
      c.setTrim(end: 10.1); // too short: the end is pushed out
      expect(c.recipe.trim!.length, greaterThanOrEqualTo(0.5));
      c.setTrim(start: -5);
      expect(c.recipe.trim!.startSec, 0);
    });

    test('a file type or size the server refuses is left out with a reason', () {
      final c = EditorController(mode: EditorMode.video);
      addTearDown(c.dispose);
      c.useVideo(_file('clip.avi'), 10);
      expect(c.videoPath, isNull);
      expect(c.notice, contains('not supported'));
      c.clearNotice();
      c.useVideo(_file('big.mp4', bytes: 50 * 1024 * 1024 + 1), 10);
      expect(c.videoPath, isNull);
      expect(c.notice, contains('50 MB'));
      c.useVideo(_file('ok.mov'), 10);
      expect(c.videoPath, isNotNull);
    });

    test('mute is sent, and the whole thing goes out as a VIDEO recipe with the file', () {
      final path = _file('a.mp4');
      final c = EditorController(mode: EditorMode.video, videoPath: path, videoSeconds: 30);
      addTearDown(c.dispose);
      c.setTrim(start: 5, end: 20);
      c.update((r) => r.copyWith(muteOriginal: true));
      expect(c.recipe.toJson(videoSeconds: 30), {
        'mode': 'VIDEO',
        'trim': {'startSec': 5.0, 'endSec': 20.0},
        'muteOriginal': true,
      });
    });
  });

  group('screen', () {
    Future<FakeFeedRepository> open(WidgetTester tester, {String? path, double? seconds, FakePickers? pickers}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final repo = FakeFeedRepository.sample(now: DateTime.utc(2026, 10, 10, 12));
      final feed = FeedController(repo, pollInterval: const Duration(milliseconds: 5));
      addTearDown(feed.dispose);
      await tester.pumpWidget(ChangeNotifierProvider<FeedController>.value(
        value: feed,
        child: MaterialApp(
          theme: ForestTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => openEditor(context, mode: EditorMode.video, videoPath: path, videoSeconds: seconds, pickOnOpen: path == null && pickers != null, pickers: pickers),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await settle(tester);
      return repo;
    }

    testWidgets('with no video yet it offers to record or choose, and Post is off', (tester) async {
      await open(tester);
      expect(find.text('Record'), findsWidgets);
      expect(find.text('Choose a video'), findsWidgets);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Post')).onPressed, isNull);
    });

    testWidgets('choosing a video from the gallery loads it', (tester) async {
      final pickers = FakePickers(video: PickedVideo(_file('g.mp4'), 42));
      await open(tester, pickers: pickers);
      expect(pickers.asked, ['video']);
      final c = tester.element(find.byType(EditorScreen)).read<EditorController>();
      expect(c.videoSeconds, 42);
      expect(find.textContaining('Keep this part'.toUpperCase()), findsOneWidget);
    });

    testWidgets('the trim panel shows the kept part and warns about a long video', (tester) async {
      await open(tester, path: _file('long.mp4'), seconds: 95);
      expect(find.textContaining('60.0 s'), findsOneWidget);
      expect(find.textContaining('60 seconds at most'), findsOneWidget);
      expect(find.byType(RangeSlider), findsOneWidget);
      final c = tester.element(find.byType(EditorScreen)).read<EditorController>();
      c.setTrim(start: 40, end: 80);
      await settle(tester);
      expect(find.textContaining('40.0 s'), findsOneWidget);
    });

    testWidgets('the Sound tool switches the original sound off', (tester) async {
      await open(tester, path: _file('a.mp4'), seconds: 20);
      await tester.tap(find.text('Sound'));
      await settle(tester);
      await tester.tap(find.byType(Switch));
      await settle(tester);
      final c = tester.element(find.byType(EditorScreen)).read<EditorController>();
      expect(c.recipe.muteOriginal, isTrue);
      expect(find.textContaining('the AI reads only your text'), findsOneWidget);
    });

    testWidgets('Post sends the video file with its trim', (tester) async {
      final path = _file('a.mp4');
      final repo = await open(tester, path: path, seconds: 30);
      final c = tester.element(find.byType(EditorScreen)).read<EditorController>();
      c.setTrim(start: 2, end: 12);
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Post'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      final sent = repo.composed.single;
      expect(sent['videoPath'], path);
      expect(((sent['recipe'] as Map)['trim'] as Map)['startSec'], 2.0);
      expect(((sent['recipe'] as Map)['trim'] as Map)['endSec'], 12.0);
    });
  });
}
