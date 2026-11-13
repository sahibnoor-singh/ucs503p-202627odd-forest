// Text on the picture, the colour look and music: the colour maths, the panels, and what reaches the posted recipe.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:forest_app/data/fake_feed_repository.dart';
import 'package:forest_app/features/editor/adjust_filter.dart';
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
  final f = File('${_dir.path}/$name')..writeAsBytesSync(List.filled(bytes, 5));
  return f.path;
}

/// Applies a Flutter colour matrix (4x5, offsets in 0-255) to an rgb colour given as 0..1 numbers; returns 0..1 numbers.
List<double> _apply(List<double> m, double r, double g, double b) {
  double row(int i) => (m[i * 5] * r + m[i * 5 + 1] * g + m[i * 5 + 2] * b + m[i * 5 + 4] / 255).clamp(0.0, 1.0);
  return [row(0), row(1), row(2)];
}

void main() {
  setUp(() => _dir = Directory.systemTemp.createTempSync('forest_extras'));
  tearDown(() => _dir.deleteSync(recursive: true));

  group('colour look maths', () {
    test('no change is the identity', () {
      final out = _apply(adjustMatrix(const Adjust()), .2, .5, .8);
      expect(out[0], closeTo(.2, 1e-9));
      expect(out[1], closeTo(.5, 1e-9));
      expect(out[2], closeTo(.8, 1e-9));
    });

    test('colour 0 gives grey, brightness lifts, contrast pushes away from mid-grey', () {
      final grey = _apply(adjustMatrix(const Adjust(saturation: 0)), .9, .2, .1);
      expect(grey[0], closeTo(grey[1], 1e-6));
      expect(grey[1], closeTo(grey[2], 1e-6));

      final lifted = _apply(adjustMatrix(const Adjust(brightness: .2)), .3, .3, .3);
      expect(lifted[0], closeTo(.5, 1e-6));

      final hard = _apply(adjustMatrix(const Adjust(contrast: 2)), .75, .25, .5);
      expect(hard[0], closeTo(1.0, 1e-6));
      expect(hard[1], closeTo(0.0, 1e-6));
      expect(hard[2], closeTo(.5, 1e-6), reason: 'mid-grey stays put');
    });

    test('a half turn of tint keeps grey grey and moves colours', () {
      final m = adjustMatrix(const Adjust(hue: 180));
      final g = _apply(m, .4, .4, .4);
      expect(g[0], closeTo(.4, 1e-3));
      expect(g[1], closeTo(.4, 1e-3));
      final red = _apply(m, 1, 0, 0);
      expect(red[0], lessThan(.5), reason: 'red is no longer red');
    });

    test('presets are found again from their values', () {
      for (final p in LookPreset.all) {
        expect(p.matches(p.adjust), isTrue, reason: p.name);
      }
      expect(LookPreset.all.where((p) => p.matches(const Adjust(contrast: 1.234))), isEmpty);
    });
  });

  group('controller', () {
    test('adding text selects it, removing keeps the selection pointing at the right one', () {
      final c = EditorController(mode: EditorMode.text);
      addTearDown(c.dispose);
      c.addOverlay(const TextOverlay(text: 'a'));
      c.addOverlay(const TextOverlay(text: 'b'));
      c.addOverlay(const TextOverlay(text: 'c'));
      expect(c.selectedOverlay, 2);
      c.removeOverlay(0);
      expect(c.recipe.overlays.map((o) => o.text), ['b', 'c']);
      expect(c.selectedOverlay, 1, reason: 'still "c"');
      c.removeOverlay(1);
      expect(c.selectedOverlay, isNull);
    });

    test('no more than five', () {
      final c = EditorController(mode: EditorMode.text);
      addTearDown(c.dispose);
      for (var i = 0; i < 7; i++) {
        c.addOverlay(TextOverlay(text: '$i'));
      }
      expect(c.recipe.overlays, hasLength(5));
    });

    test('music: a good file is kept with default settings; a wrong type or a big file is refused with a reason', () async {
      final c = EditorController(mode: EditorMode.text, pickers: FakePickers(musicFile: PickedMusic(_file('song.mp3'), 'song.mp3')));
      addTearDown(c.dispose);
      await c.pickMusic();
      expect(c.musicPath, isNotNull);
      expect(c.recipe.music!.volume, .8);
      c.clearMusic();
      expect(c.musicPath, isNull);
      expect(c.recipe.music, isNull);

      final wrong = EditorController(mode: EditorMode.text, pickers: FakePickers(musicFile: PickedMusic(_file('talk.flac'), 'talk.flac')));
      addTearDown(wrong.dispose);
      await wrong.pickMusic();
      expect(wrong.musicPath, isNull);
      expect(wrong.notice, contains('MP3'));

      final big = EditorController(mode: EditorMode.text, pickers: FakePickers(musicFile: PickedMusic(_file('long.mp3', bytes: 15 * 1024 * 1024 + 1), 'long.mp3')));
      addTearDown(big.dispose);
      await big.pickMusic();
      expect(big.musicPath, isNull);
      expect(big.notice, contains('15 MB'));
    });
  });

  group('screen', () {
    Future<({FakeFeedRepository repo, FakePickers pickers})> open(WidgetTester tester, {FakePickers? pickers}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final repo = FakeFeedRepository.sample(now: DateTime.utc(2026, 10, 10, 12));
      final feed = FeedController(repo, pollInterval: const Duration(milliseconds: 5));
      addTearDown(feed.dispose);
      final p = pickers ?? FakePickers();
      await tester.pumpWidget(ChangeNotifierProvider<FeedController>.value(
        value: feed,
        child: MaterialApp(
          theme: ForestTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(child: TextButton(onPressed: () => openEditor(context, mode: EditorMode.text, pickers: p), child: const Text('open'))),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await settle(tester);
      return (repo: repo, pickers: p);
    }

    EditorController ctl(WidgetTester tester) => tester.element(find.byType(EditorScreen)).read<EditorController>();

    /// Opens a tool, scrolling the tool bar if it does not fit.
    Future<void> tool(WidgetTester tester, String label) async {
      final bar = find.byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.horizontal).last;
      await tester.scrollUntilVisible(find.text(label), 120, scrollable: bar);
      await settle(tester);
      await tester.tap(find.text(label));
      await settle(tester);
    }

    testWidgets('Add text puts text on the picture, and what you type and pick reaches the recipe', (tester) async {
      await open(tester);
      await tool(tester, 'Add text');
      expect(find.textContaining('Add text, then drag'), findsOneWidget);
      await tester.tap(find.text('+ Add text'));
      await settle(tester);
      expect(ctl(tester).recipe.overlays.single.text, 'Your text');
      expect(find.text('Your text'), findsWidgets);

      await tester.enterText(find.byType(TextFormField), 'Source: Hindu, 2024');
      await tester.pump();
      expect(ctl(tester).recipe.overlays.single.text, 'Source: Hindu, 2024');

      await tester.tap(find.text('Mono'));
      await settle(tester);
      expect(ctl(tester).recipe.overlays.single.font, EditorFont.mono);
    });

    testWidgets('dragging the text on the picture moves it', (tester) async {
      await open(tester);
      await tool(tester, 'Add text');
      await tester.tap(find.text('+ Add text'));
      await settle(tester);
      final before = ctl(tester).recipe.overlays.single;
      await tester.drag(find.text('Your text').first, const Offset(0, 60), warnIfMissed: false);
      await settle(tester);
      final after = ctl(tester).recipe.overlays.single;
      expect(after.y, greaterThan(before.y));
    });

    testWidgets('Remove this text takes it away', (tester) async {
      await open(tester);
      await tool(tester, 'Add text');
      await tester.tap(find.text('+ Add text'));
      await settle(tester);
      await tester.ensureVisible(find.text('Remove this text'));
      await tester.tap(find.text('Remove this text'));
      await settle(tester);
      expect(ctl(tester).recipe.overlays, isEmpty);
    });

    testWidgets('a look preset changes the recipe and is shown as chosen', (tester) async {
      await open(tester);
      await tool(tester, 'Look');
      await tester.tap(find.text('Mono'));
      await settle(tester);
      expect(ctl(tester).recipe.adjust.saturation, 0);
      await tester.tap(find.text('Original'));
      await settle(tester);
      expect(ctl(tester).recipe.adjust.isDefault, isTrue);
      expect(find.textContaining('changes the background, not the words'), findsOneWidget);
    });

    testWidgets('music: choose, see its name, change the volume, remove', (tester) async {
      await open(tester, pickers: FakePickers(musicFile: PickedMusic(_file('chill.mp3'), 'chill.mp3')));
      await tool(tester, 'Music');
      expect(find.textContaining('right to use'), findsOneWidget);
      await tester.tap(find.text('Choose music'));
      await settle(tester);
      expect(find.text('chill.mp3'), findsOneWidget);
      expect(ctl(tester).musicPath, isNotNull);
      expect(find.text('80%'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove music'));
      await settle(tester);
      expect(ctl(tester).musicPath, isNull);
      expect(find.text('Choose music'), findsOneWidget);
    });

    testWidgets('Post sends the text, the look and the music file together', (tester) async {
      final song = _file('chill.mp3');
      final rig = await open(tester, pickers: FakePickers(musicFile: PickedMusic(song, 'chill.mp3')));
      final c = ctl(tester);
      c.update((r) => r.copyWith(text: const TextSpec(content: 'Hello there')));
      c.addOverlay(const TextOverlay(text: 'Source', y: .9, size: 30));
      c.update((r) => r.copyWith(adjust: const Adjust(saturation: 0)));
      await c.pickMusic();
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Post'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      final sent = rig.repo.composed.single;
      final recipe = sent['recipe'] as Map;
      expect(sent['musicPath'], song);
      expect((recipe['overlays'] as List).single['text'], 'Source');
      expect(recipe['adjust'], {'saturation': 0.0});
      expect(recipe['music'], {'volume': .8, 'startSec': 0.0});
    });
  });
}
