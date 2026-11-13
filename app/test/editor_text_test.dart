// The editor screen for a text post: writing, styling, the Post button, and closing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:forest_app/data/fake_feed_repository.dart';
import 'package:forest_app/features/editor/editor_controller.dart';
import 'package:forest_app/features/editor/editor_screen.dart';
import 'package:forest_app/features/editor/recipe.dart';
import 'package:forest_app/features/home/feed_controller.dart';
import 'package:forest_app/services/api_client.dart';
import 'package:forest_app/theme/forest_theme.dart';

import 'support/harness.dart';

class _Rig {
  _Rig(this.repo, this.feed);
  final FakeFeedRepository repo;
  final FeedController feed;
  bool? result;
}

Future<_Rig> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = FakeFeedRepository.sample(now: DateTime.utc(2026, 10, 10, 12));
  final feed = FeedController(repo, pollInterval: const Duration(milliseconds: 5));
  addTearDown(feed.dispose);
  final rig = _Rig(repo, feed);
  await tester.pumpWidget(ChangeNotifierProvider<FeedController>.value(
    value: feed,
    child: MaterialApp(
      theme: ForestTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => rig.result = await openEditor(context, mode: EditorMode.text),
              child: const Text('open editor'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open editor'));
  await settle(tester);
  return rig;
}

EditorController _controller(WidgetTester tester) => tester.element(find.byType(EditorScreen)).read<EditorController>();

/// Long enough for a screen to slide away (the preview animates forever, so pumpAndSettle cannot be used).
Future<void> _slideAway(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Opens a tool by its name, scrolling the tool bar when it is off the edge.
Future<void> _tool(WidgetTester tester, String label) async {
  final bar = find.byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.horizontal).last;
  await tester.scrollUntilVisible(find.text(label), 120, scrollable: bar);
  await settle(tester);
  await tester.tap(find.text(label));
  await settle(tester);
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump();
}

void main() {
  testWidgets('starts empty: Post is off, the tools are there, and the preview invites you to write', (tester) async {
    await _open(tester);
    expect(find.text('New opinion'), findsOneWidget);
    final post = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Post'));
    expect(post.onPressed, isNull);
    for (final label in ['Backdrop', 'Text', 'Motion', 'Add text', 'Look']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Your words appear here'), findsOneWidget);
  });

  testWidgets('writing turns Post on and the words show in the preview', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Text'));
    await settle(tester);
    await _type(tester, 'Exams should be open-book');
    await tester.pump(const Duration(seconds: 2)); // past the fade-in
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Post')).onPressed, isNotNull);
    expect(_controller(tester).recipe.text.content, 'Exams should be open-book');
    expect(find.text('Exams should be open-book'), findsWidgets);
  });

  testWidgets('a hint explains what is wrong once there is something to fix', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Text'));
    await settle(tester);
    await _type(tester, 'x' * 280);
    _controller(tester).update((r) => r.copyWith(durationSec: 2));
    await tester.pump();
    expect(find.textContaining('3 to 60 seconds'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Post')).onPressed, isNull);
  });

  testWidgets('Hindi, Punjabi and English draw without a word; emoji and other scripts get a note', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Text'));
    await settle(tester);
    await _type(tester, 'Hello, how are you? 100% fine!');
    expect(find.textContaining('boxes'), findsNothing);
    await _type(tester, 'नमस्ते ਸਤ ਸ੍ਰੀ ਅਕਾਲ');
    expect(find.textContaining('boxes'), findsNothing);
    expect(find.textContaining('one colour'), findsNothing);
    await _type(tester, 'Nice 😀');
    expect(find.textContaining('one colour'), findsOneWidget);
    expect(find.textContaining('boxes'), findsNothing);
    await _type(tester, 'வணக்கம்');
    expect(find.textContaining('boxes'), findsOneWidget);
  });

  testWidgets('background, motion and size changes reach the recipe', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Backdrop'));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Dusk gradient'), warnIfMissed: false);
    final semantics = tester.ensureSemantics();
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Dusk gradient'));
    await tester.pump();
    expect(_controller(tester).recipe.background.isGradient, isTrue);
    expect(_controller(tester).recipe.background.from, const Color(0xFF2B1055));

    await tester.tap(find.text('Motion'));
    await settle(tester);
    await tester.tap(find.text('Typewriter'));
    await tester.pump();
    expect(_controller(tester).recipe.text.animation, TextAnimation.typewriter);
    semantics.dispose();
  });

  testWidgets('Post sends the recipe, the question and the caption, and closes the editor', (tester) async {
    final rig = await _open(tester);
    await tester.tap(find.text('Text'));
    await settle(tester);
    await _type(tester, 'Open-book exams');
    await _tool(tester, 'Details');
    await tester.enterText(find.byType(TextField).first, 'Should exams be open-book?');
    await tester.enterText(find.byType(TextField).last, 'my take');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Post'));
    await _slideAway(tester);

    expect(rig.repo.composed, hasLength(1));
    final sent = rig.repo.composed.single;
    expect(sent['title'], 'Should exams be open-book?');
    expect(sent['body'], 'my take');
    expect((sent['recipe'] as Map)['mode'], 'TEXT');
    expect(((sent['recipe'] as Map)['text'] as Map)['content'], 'Open-book exams');
    expect(rig.result, isTrue);
    expect(find.byType(EditorScreen), findsNothing);
  });

  testWidgets('a server refusal stays on screen and the editor stays open', (tester) async {
    final rig = await _open(tester);
    await tester.tap(find.text('Text'));
    await settle(tester);
    await _type(tester, 'hello');
    rig.repo.failNext = const ApiException('You are posting too fast.', statusCode: 429);
    await tester.tap(find.widgetWithText(FilledButton, 'Post'));
    await settle(tester);
    expect(find.text('You are posting too fast.'), findsOneWidget);
    expect(find.byType(EditorScreen), findsOneWidget);
    expect(rig.result, isNull);
  });

  testWidgets('closing with nothing written just closes; closing with text asks first', (tester) async {
    final rig = await _open(tester);
    await tester.tap(find.byTooltip('Close'));
    await _slideAway(tester);
    expect(find.byType(EditorScreen), findsNothing);
    expect(rig.result, isNull);

    await tester.tap(find.text('open editor'));
    await settle(tester);
    await tester.tap(find.text('Text'));
    await settle(tester);
    await _type(tester, 'a thought');
    await tester.tap(find.byTooltip('Close'));
    await settle(tester);
    expect(find.text('Discard this post?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await settle(tester);
    expect(find.byType(EditorScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await settle(tester);
    await tester.tap(find.text('Discard'));
    await _slideAway(tester); // the dialog and the screen both slide away
    expect(find.byType(EditorScreen), findsNothing);
  });
}
