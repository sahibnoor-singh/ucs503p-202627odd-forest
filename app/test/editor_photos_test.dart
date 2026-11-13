// Photo posts: picking, the rules the server has about files, reordering, timing and posting.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:forest_app/data/fake_feed_repository.dart';
import 'package:forest_app/features/editor/editor_controller.dart';
import 'package:forest_app/features/editor/editor_panels.dart';
import 'package:forest_app/features/editor/editor_pickers.dart';
import 'package:forest_app/features/editor/editor_screen.dart';
import 'package:forest_app/features/editor/recipe.dart';
import 'package:forest_app/features/home/feed_controller.dart';
import 'package:forest_app/theme/forest_theme.dart';

import 'support/harness.dart';

/// Hands the editor files without a phone.
class FakePickers implements EditorPickers {
  FakePickers({this.photoPaths = const [], this.video, this.musicFile});

  List<String> photoPaths;
  PickedVideo? video;
  PickedMusic? musicFile;
  final asked = <String>[];

  @override
  Future<List<String>> photos({required int limit}) async {
    asked.add('photos:$limit');
    return photoPaths.take(limit).toList();
  }

  @override
  Future<PickedVideo?> galleryVideo() async {
    asked.add('video');
    return video;
  }

  @override
  Future<PickedMusic?> music() async {
    asked.add('music');
    return musicFile;
  }
}

/// A real 1x1 PNG, so Image.file has something to decode.
final _png = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06,
  0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0, 0x1F, 0x00, 0x05, 0x00,
  0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

late Directory _dir;

String _file(String name, {int? bytes}) {
  final f = File('${_dir.path}/$name');
  f.writeAsBytesSync(bytes == null ? _png : List.filled(bytes, 7));
  return f.path;
}

void main() {
  setUp(() => _dir = Directory.systemTemp.createTempSync('forest_photos'));
  tearDown(() => _dir.deleteSync(recursive: true));

  group('controller', () {
    test('adds photos, keeps the recipe in step and refuses an 11th', () async {
      final c = EditorController(mode: EditorMode.photos, pickers: FakePickers(photoPaths: [for (var i = 0; i < 12; i++) _file('p$i.png')]));
      addTearDown(c.dispose);
      expect(c.problem, 'Pick at least one photo.');
      await c.pickMorePhotos();
      expect(c.photos, hasLength(10), reason: 'only as many as fit');
      expect(c.recipe.photoCount, 10);
      await c.pickMorePhotos();
      expect(c.notice, contains('up to 10'));
    });

    test('leaves out files the server would refuse and says why', () async {
      final c = EditorController(
        mode: EditorMode.photos,
        pickers: FakePickers(photoPaths: [_file('ok.jpg'), _file('phone.heic'), _file('huge.png', bytes: 10 * 1024 * 1024 + 1)]),
      );
      addTearDown(c.dispose);
      await c.pickMorePhotos();
      expect(c.photos.map(fileNameOf), ['ok.jpg']);
      expect(c.notice, contains('2 photos were left out'));
      expect(c.notice, contains('not a JPG'));
    });

    test('one refused photo is named', () async {
      final c = EditorController(mode: EditorMode.photos, pickers: FakePickers(photoPaths: [_file('scan.gif')]));
      addTearDown(c.dispose);
      await c.pickMorePhotos();
      expect(c.photos, isEmpty);
      expect(c.notice, '"scan.gif" is not a JPG, PNG or WebP photo.');
    });

    test('reordering and removing keep the list and the count right', () async {
      final a = _file('a.png'), b = _file('b.png'), d = _file('c.png');
      final c = EditorController(mode: EditorMode.photos, pickers: FakePickers(photoPaths: [a, b, d]));
      addTearDown(c.dispose);
      await c.pickMorePhotos();
      c.movePhoto(0, 2);
      expect(c.photos, [b, d, a]);
      c.removePhoto(1);
      expect(c.photos, [b, a]);
      expect(c.recipe.photoCount, 2);
      c.removePhoto(9); // nothing there: ignored
      expect(c.photos, hasLength(2));
    });

    test('too many seconds is caught before sending', () async {
      final c = EditorController(mode: EditorMode.photos, pickers: FakePickers(photoPaths: [for (var i = 0; i < 10; i++) _file('p$i.png')]));
      addTearDown(c.dispose);
      await c.pickMorePhotos();
      c.update((r) => r.copyWith(slideSeconds: 8, transition: PhotoTransition.none));
      expect(c.problem, contains('60 seconds'));
      c.update((r) => r.copyWith(slideSeconds: 4));
      expect(c.problem, isNull);
    });
  });

  group('screen', () {
    Future<({FakeFeedRepository repo, FakePickers pickers})> open(WidgetTester tester, FakePickers pickers) async {
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
                  onPressed: () => openEditor(context, mode: EditorMode.photos, pickOnOpen: true, pickers: pickers),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await settle(tester);
      return (repo: repo, pickers: pickers);
    }

    testWidgets('asks for photos when it opens, shows them, and Post sends them in order', (tester) async {
      final a = _file('a.png'), b = _file('b.png');
      final rig = await open(tester, FakePickers(photoPaths: [a, b]));
      expect(rig.pickers.asked, ['photos:10']);
      expect(find.text('Photos'), findsWidgets);
      expect(find.textContaining('2 / 10'), findsOneWidget);
      expect(find.byType(Image), findsWidgets);

      await tester.tap(find.widgetWithText(FilledButton, 'Post'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      final sent = rig.repo.composed.single;
      expect(sent['photoPaths'], [a, b]);
      expect((sent['recipe'] as Map)['mode'], 'PHOTOS');
      expect((sent['recipe'] as Map)['slideSeconds'], 3.0);
    });

    testWidgets('removing a photo updates the count; with none left Post is off', (tester) async {
      final rig = await open(tester, FakePickers(photoPaths: [_file('a.png')]));
      expect(rig.pickers.asked, isNotEmpty);
      await tester.tap(find.descendant(of: find.byType(PhotosPanel), matching: find.byIcon(Icons.close_rounded)));
      await settle(tester);
      expect(find.textContaining('0 / 10'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Post')).onPressed, isNull);
    });

    testWidgets('the Timing tool changes the seconds and warns above a minute', (tester) async {
      await open(tester, FakePickers(photoPaths: [for (var i = 0; i < 10; i++) _file('p$i.png')]));
      await tester.tap(find.text('Timing'));
      await settle(tester);
      final c = tester.element(find.byType(EditorScreen)).read<EditorController>();
      c.update((r) => r.copyWith(slideSeconds: 8));
      await settle(tester);
      expect(find.textContaining('over the 60 second limit'), findsOneWidget);
      c.update((r) => r.copyWith(slideSeconds: 3));
      await settle(tester);
      expect(find.textContaining('over the 60 second limit'), findsNothing);
    });
  });
}
