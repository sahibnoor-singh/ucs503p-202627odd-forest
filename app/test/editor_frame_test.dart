// Crop and cover: the controller rules, the draggable box, the "show only this part" window, and what reaches the posted recipe.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:forest_app/data/fake_feed_repository.dart';
import 'package:forest_app/features/editor/crop_editor.dart';
import 'package:forest_app/features/editor/editor_controller.dart';
import 'package:forest_app/features/editor/editor_screen.dart';
import 'package:forest_app/features/editor/recipe.dart';
import 'package:forest_app/features/home/feed_controller.dart';
import 'package:forest_app/theme/forest_theme.dart';

import 'support/harness.dart';

late Directory _dir;

String _file(String name) {
  final f = File('${_dir.path}/$name')..writeAsBytesSync(List.filled(16, 3));
  return f.path;
}

void main() {
  setUp(() => _dir = Directory.systemTemp.createTempSync('forest_frame'));
  tearDown(() => _dir.deleteSync(recursive: true));

  group('controller', () {
    test('a crop is kept, and a crop that cuts nothing off is dropped', () {
      final c = EditorController(mode: EditorMode.video, videoPath: _file('a.mp4'), videoSeconds: 20);
      addTearDown(c.dispose);
      expect(c.recipe.crop, isNull);
      c.setCrop(const Crop(x: .1, y: .1, w: .5, h: .5));
      expect(c.recipe.crop!.w, .5);
      expect(c.recipe.toJson(videoSeconds: 20)['crop'], {'x': .1, 'y': .1, 'w': .5, 'h': .5});
      c.setCrop(const Crop());
      expect(c.recipe.crop, isNull);
      c.setCrop(const Crop(w: .5));
      c.setCropRatio(1);
      c.resetCrop();
      expect(c.recipe.crop, isNull);
      expect(c.cropRatio, isNull);
    });

    test('choosing another video forgets the crop and the cover meant for the old one', () {
      final c = EditorController(mode: EditorMode.video, videoPath: _file('a.mp4'), videoSeconds: 20);
      addTearDown(c.dispose);
      c.setCrop(const Crop(w: .5));
      c.setCover(5);
      c.setVideo(_file('b.mp4'), 30);
      expect(c.recipe.crop, isNull);
      expect(c.recipe.coverSec, isNull);
    });

    test('the cover stays inside the kept part, also when the part is trimmed shorter afterwards', () {
      final c = EditorController(mode: EditorMode.video, videoPath: _file('a.mp4'), videoSeconds: 30);
      addTearDown(c.dispose);
      c.setCover(100);
      expect(c.recipe.coverSec, closeTo(29.9, 1e-9));
      c.setCover(-4);
      expect(c.recipe.coverSec, 0);
      c.setCover(25);
      c.setTrim(start: 0, end: 10);
      expect(c.recipe.coverSec, closeTo(9.9, 1e-9));
      c.setCover(null);
      expect(c.recipe.coverSec, isNull);
    });

    test('the recipe says where the cover is, for video only, and never beyond the end', () {
      final c = EditorController(mode: EditorMode.video, videoPath: _file('a.mp4'), videoSeconds: 30);
      addTearDown(c.dispose);
      expect(c.recipe.toJson(videoSeconds: 30).containsKey('coverSec'), isFalse, reason: 'unset: the server picks');
      c.setCover(12.345);
      expect(c.recipe.toJson(videoSeconds: 30)['coverSec'], 12.35);
      final text = EditorController(mode: EditorMode.text);
      addTearDown(text.dispose);
      text.update((r) => r.copyWith(coverSec: 3));
      expect(text.recipe.toJson().containsKey('coverSec'), isFalse);
    });

    test('photo posts take a crop too', () {
      final c = EditorController(mode: EditorMode.photos);
      addTearDown(c.dispose);
      c.addPhotos([_file('a.jpg')]);
      c.setCrop(const Crop(x: .25, w: .5));
      expect(c.recipe.toJson()['crop'], {'x': .25, 'y': 0.0, 'w': .5, 'h': 1.0});
    });
  });

  group('CropWindow', () {
    testWidgets('shows only the cropped part, scaled up to fill', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 100, // the shape of the right half of a 200 x 100 picture: 100 x 100
              height: 100,
              child: CropWindow(crop: const Crop(x: .5, w: .5), child: Container(key: const Key('whole'), color: Colors.red)),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byKey(const Key('whole'))), const Size(200, 100), reason: 'the whole picture is laid out at full size');
      final window = tester.getTopLeft(find.byType(CropWindow));
      expect(tester.getTopLeft(find.byKey(const Key('whole'))).dx - window.dx, -100, reason: 'its left half is pushed out of sight');
    });

    testWidgets('no crop leaves the picture alone', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(alignment: Alignment.topLeft, child: SizedBox(width: 100, height: 50, child: CropWindow(crop: null, child: Container(key: const Key('whole'))))),
        ),
      );
      expect(tester.getSize(find.byKey(const Key('whole'))), const Size(100, 50));
    });
  });

  group('CropEditor', () {
    Widget host(List<Crop?> changes, {Crop? crop, double? ratio, double aspect = .5}) => Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 200, // 200 x 400: a portrait picture
              height: 400,
              child: CropEditor(crop: crop, sourceAspect: aspect, ratio: ratio, onChanged: changes.add),
            ),
          ),
        );

    Offset at(WidgetTester tester, double x, double y) => tester.getTopLeft(find.byKey(const Key('crop-box'))) + Offset(x, y);

    testWidgets('dragging inside the box moves it', (tester) async {
      final changes = <Crop?>[];
      await tester.pumpWidget(host(changes, crop: const Crop(x: .25, y: .25, w: .5, h: .5))); // box: x 50..150, y 100..300
      await tester.dragFrom(at(tester, 100, 200), const Offset(20, 40));
      expect(changes, isNotEmpty);
      final c = changes.last!;
      expect(c.x, closeTo(.35, .01));
      expect(c.y, closeTo(.35, .01));
      expect(c.w, closeTo(.5, 1e-6));
      expect(c.h, closeTo(.5, 1e-6));
    });

    testWidgets('dragging a corner resizes it', (tester) async {
      final changes = <Crop?>[];
      await tester.pumpWidget(host(changes, crop: const Crop(x: .25, y: .25, w: .5, h: .5)));
      await tester.dragFrom(at(tester, 150, 300), const Offset(30, 50)); // bottom right corner
      final c = changes.last!;
      expect(c.x, closeTo(.25, 1e-6));
      expect(c.w, closeTo(.65, .01));
      expect(c.h, closeTo(.625, .01));
    });

    testWidgets('a free box can be pulled by one edge', (tester) async {
      final changes = <Crop?>[];
      await tester.pumpWidget(host(changes, crop: const Crop(x: .25, y: .25, w: .5, h: .5)));
      await tester.dragFrom(at(tester, 50, 200), const Offset(-25, 0)); // left edge
      final e = changes.last!;
      expect(e.x, closeTo(.125, .01));
      expect(e.w, closeTo(.625, .01));
      expect(e.h, closeTo(.5, 1e-6), reason: 'only one side moved');
    });

    testWidgets('a drag that starts outside the box does nothing', (tester) async {
      final changes = <Crop?>[];
      await tester.pumpWidget(host(changes, crop: const Crop(x: .25, y: .25, w: .5, h: .5)));
      await tester.dragFrom(at(tester, 10, 10), const Offset(30, 30));
      expect(changes, isEmpty);
    });

    testWidgets('choosing a shape re-fits the box to it', (tester) async {
      final changes = <Crop?>[];
      await tester.pumpWidget(host(changes));
      expect(changes, isEmpty);
      await tester.pumpWidget(host(changes, ratio: 1)); // a square on a 200 x 400 picture: 200 x 200
      await tester.pump(); // the box reports itself after the frame
      final c = changes.last!;
      expect(c.w * 200, closeTo(c.h * 400, 1), reason: 'square on screen');
      expect(c.w, closeTo(1, 1e-6), reason: 'as wide as the picture');
      expect(c.y, closeTo(.25, 1e-6), reason: 'centred');
    });

    testWidgets('with a shape held a corner keeps it', (tester) async {
      final changes = <Crop?>[];
      await tester.pumpWidget(host(changes, crop: const Crop(x: 0, y: .25, w: 1, h: .5), ratio: 1));
      await tester.dragFrom(at(tester, 195, 295), const Offset(-60, -60)); // bottom right corner (just inside the edge), pulled in
      final c = changes.last!;
      expect(c.w * 200, closeTo(c.h * 400, 1), reason: 'still square on screen');
      expect(c.w, lessThan(1));
      expect(c.x, 0.0, reason: 'the top left corner stayed');
    });
  });

  group('screen', () {
    Future<FakeFeedRepository> open(WidgetTester tester, {required EditorMode mode, String? path, double? seconds}) async {
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
              body: Center(child: TextButton(onPressed: () => openEditor(context, mode: mode, videoPath: path, videoSeconds: seconds), child: const Text('open'))),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await settle(tester);
      return repo;
    }

    EditorController ctl(WidgetTester tester) => tester.element(find.byType(EditorScreen)).read<EditorController>();

    Future<void> tool(WidgetTester tester, String label) async {
      final bar = find.byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.horizontal).last;
      await tester.scrollUntilVisible(find.text(label), 120, scrollable: bar);
      await settle(tester);
      await tester.tap(find.text(label));
      await settle(tester);
    }

    testWidgets('video: the Crop tool offers shapes, holds the chosen one, and puts everything back', (tester) async {
      await open(tester, mode: EditorMode.video, path: _file('a.mp4'), seconds: 20);
      await tool(tester, 'Crop');
      expect(find.textContaining('Drag the box'), findsOneWidget);
      for (final shape in ['Free', '1:1', '4:5', '9:16', '16:9']) {
        expect(find.text(shape), findsOneWidget, reason: shape);
      }
      await tester.tap(find.text('1:1'));
      await settle(tester);
      expect(ctl(tester).cropRatio, 1);
      ctl(tester).setCrop(const Crop(x: .1, y: .1, w: .5, h: .5));
      await settle(tester);
      await tester.tap(find.text('Use the whole picture'));
      await settle(tester);
      expect(ctl(tester).recipe.crop, isNull);
      expect(ctl(tester).cropRatio, isNull);
    });

    testWidgets('video: the Cover tool picks a moment and Post sends it with the crop', (tester) async {
      final repo = await open(tester, mode: EditorMode.video, path: _file('a.mp4'), seconds: 20);
      await tool(tester, 'Cover');
      expect(find.textContaining('before the video plays'), findsOneWidget);
      final slider = find.byType(Slider);
      await tester.drag(slider, const Offset(200, 0));
      await settle(tester);
      final cover = ctl(tester).recipe.coverSec;
      expect(cover, isNotNull);
      expect(cover, greaterThan(0));
      ctl(tester).setCrop(const Crop(x: 0, y: 0, w: .5, h: 1));
      await tester.tap(find.widgetWithText(FilledButton, 'Post'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      final recipe = repo.composed.single['recipe'] as Map;
      expect(recipe['coverSec'], closeTo(cover!, 0.01));
      expect(recipe['crop'], {'x': 0.0, 'y': 0.0, 'w': .5, 'h': 1.0});
    });

    testWidgets('photos: Crop is there with its own wording; with no photo it asks for one', (tester) async {
      await open(tester, mode: EditorMode.photos);
      await tool(tester, 'Crop');
      expect(find.text('Add a photo first.'), findsOneWidget);
      ctl(tester).addPhotos([_file('a.jpg')]);
      await settle(tester);
      expect(find.textContaining('in every photo'), findsOneWidget);
    });

    testWidgets('text posts have neither Crop nor Cover', (tester) async {
      await open(tester, mode: EditorMode.text);
      expect(find.text('Crop'), findsNothing);
      expect(find.text('Cover'), findsNothing);
    });
  });
}
