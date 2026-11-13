// Home tab on fake data (no network). video_player has no platform
// implementation under `flutter test`, so every video that has a file lands in
// its "Video unavailable" state; these tests are about cards, labels and states.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:forest_app/features/home/feed_controller.dart';
import 'package:forest_app/features/home/stories_row.dart';
import 'package:forest_app/models/post.dart';
import 'package:forest_app/services/api_client.dart';
import 'package:forest_app/theme/forest_theme.dart';
import 'package:forest_app/ui/chips.dart';
import 'package:forest_app/ui/post_media.dart';

import 'support/harness.dart';

void main() {
  testWidgets('renders opinion, video-reply and text-reply cards', (tester) async {
    useTallScreen(tester);
    await pumpHome(tester, sampleRepo());

    // An opinion needs no label (everything at the top of a debate is one); replies carry their stance.
    expect(find.text('OPINION'), findsNothing);
    expect(find.text('AGAINST'), findsNWidgets(2)); // r1, r2
    expect(find.text('FOR'), findsOneWidget); // r3
    expect(find.text('UNRESOLVED'), findsOneWidget); // r4

    // Header sub-lines by card type.
    expect(find.textContaining('replied ·'), findsNWidgets(2)); // video replies r1, r3
    expect(find.textContaining('replied to @aman_s'), findsOneWidget); // text reply r2
    expect(find.textContaining('replied to @forest_daily'), findsOneWidget); // text reply r4

    // Video replies quote their parent; the reply-to-a-reply links to its root.
    expect(find.text('Parent video'), findsNWidgets(2));
    expect(find.text('in @aman_s’s debate →'), findsOneWidget);

    // The opinion's title is in its caption.
    expect(find.textContaining('Should Punjabi be mandatory'), findsWidgets);
    expect(find.textContaining('Mandates hurt students'), findsWidgets);
    expect(find.textContaining('Most states that did this'), findsWidgets);
  });

  testWidgets('a video with no file (or one that will not load) shows a placeholder', (tester) async {
    useTallScreen(tester);
    await pumpHome(tester, sampleRepo());
    // Six video frames in the sample feed. r3 and p2 have no file, so they say
    // so (r3's frame, p2's frame, and p2 again as the original under r4).
    // Frames whose file cannot be opened under test stay blank; nothing throws.
    expect(find.byType(PostMedia), findsNWidgets(6));
    expect(find.text('Video unavailable'), findsNWidgets(3));
  });

  testWidgets('bot accounts are labelled BOT', (tester) async {
    useTallScreen(tester);
    await pumpHome(tester, sampleRepo());
    // forest_daily is a bot: header on its own post, and in the caption + quote.
    expect(find.byType(BotTag), findsWidgets);
    expect(find.text('BOT'), findsWidgets);
  });

  testWidgets('PROCESSING and FAILED posts show a status instead of a video', (tester) async {
    final repo = sampleRepo();
    final post = (await repo.home()).items.firstWhere((i) => i.post.id == 'p1').post;
    Future<void> show(Post p) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PostMedia(post: p, mediaUrl: 'http://x/y.mp4', muted: true, onToggleMute: () {}),
        ),
      ));
      await tester.pump();
    }

    await show(post.copyWith(status: PostStatus.processing));
    expect(find.text('Processing…'), findsOneWidget);
    await show(post.copyWith(status: PostStatus.failed));
    expect(find.text('Processing failed'), findsOneWidget);
  });

  testWidgets('end of feed shows the caught-up footer', (tester) async {
    useTallScreen(tester);
    await pumpHome(tester, sampleRepo());
    expect(find.text('You’re all caught up'), findsOneWidget);
    expect(find.text('Go to Discover'), findsOneWidget);
  });

  testWidgets('a load error shows the reason and Retry recovers', (tester) async {
    useTallScreen(tester);
    final repo = sampleRepo()..failNext = const ApiException('Sign in required', statusCode: 401);
    await pumpHome(tester, repo);

    expect(find.text('Could not load Home'), findsOneWidget);
    expect(find.text('Sign in required'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(find.text('Could not load Home'), findsNothing);
    expect(find.text('OPINION'), findsNothing);
  });

  testWidgets('light theme renders too', (tester) async {
    useTallScreen(tester);
    await pumpHome(tester, sampleRepo(), theme: ThemeData.light());
    expect(find.text('OPINION'), findsNothing);
  });

  group('stories row', () {
    Finder inRow(Finder f) => find.descendant(of: find.byType(StoriesRow), matching: f);

    /// The row on its own (Home does not show it until stories exist), fed by a real controller on the sample data.
    Future<FeedController> pumpRow(WidgetTester tester) async {
      final c = FeedController(sampleRepo(), pollInterval: const Duration(milliseconds: 50));
      addTearDown(c.dispose);
      c.ensureLoaded();
      await tester.pumpWidget(MaterialApp(
        theme: ForestTheme.dark,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) => StoriesRow(users: c.storyUsers, isSeen: c.isStorySeen, onToggleSeen: c.toggleStorySeen, onYourStory: () {}),
          ),
        ),
      ));
      await settle(tester);
      return c;
    }

    testWidgets('Home does not show a stories row: there are no stories behind it yet', (tester) async {
      useTallScreen(tester);
      await pumpHome(tester, sampleRepo());
      expect(find.byType(StoriesRow), findsNothing);
      expect(find.text('Your story'), findsNothing);
    });

    testWidgets('Your story first, then the people you follow, in feed order', (tester) async {
      await pumpRow(tester);

      final names = [
        for (final t in tester.widgetList<Text>(inRow(find.byType(Text))))
          if (t.data != '+' && t.data != 'BOT') t.data,
      ];
      expect(names, ['Your story', 'kabir_m', 'riya_k', 'simran.v', 'aman_s', 'forest_daily', 'dev.p']);
    });

    testWidgets('bot accounts get a BOT mark on the ring; names are never shortened for it',
        (tester) async {
      await pumpRow(tester);
      // forest_daily is the only bot in the sample.
      final tags = inRow(find.byType(BotTag));
      expect(tags, findsOneWidget);
      expect(tester.widget<BotTag>(tags).compact, isTrue);
      // The mark overlaps its own ring, not the row below it.
      final ring = tester.getRect(find.byKey(const ValueKey('story-ring-u7')));
      final tag = tester.getRect(tags);
      expect(tag.center.dx, closeTo(ring.center.dx, 0.5));
      expect(tag.bottom, greaterThan(ring.bottom - 1));
      expect(tag.bottom, lessThan(ring.bottom + 6));
      // The name is the full name (the label has no " · BOT" suffix).
      expect(inRow(find.text('forest_daily')), findsOneWidget);
    });

    testWidgets('tapping a ring toggles seen (ring goes grey) and back', (tester) async {
      final c = await pumpRow(tester);
      final tokens = ForestTokens.dark;
      Color ringColor() {
        final box = tester.widget<Container>(find.byKey(const ValueKey('story-ring-u3')));
        return ((box.decoration! as BoxDecoration).border! as Border).top.color;
      }

      expect(ringColor(), tokens.fg);
      await tester.tap(find.byKey(const ValueKey('story-u3')));
      await settle(tester);
      expect(c.isStorySeen(c.storyUsers.firstWhere((u) => u.id == 'u3')), isTrue);
      expect(ringColor(), tokens.border);

      await tester.tap(find.byKey(const ValueKey('story-u3')));
      await settle(tester);
      expect(ringColor(), tokens.fg);
    });

    testWidgets('there is no Repost button (Lab-only in the prototype)', (tester) async {
      useTallScreen(tester);
      await pumpHome(tester, sampleRepo());
      expect(find.bySemanticsLabel('Repost'), findsNothing);
      expect(find.byIcon(Icons.repeat), findsNothing);
    });
  });
}
