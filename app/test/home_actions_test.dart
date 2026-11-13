// The Home tab's interactions end to end on the fake repository: like,
// double-tap like, menu (report, block + Undo, copy link), reply sheet,
// thread sheet with composer, and the full-screen viewer.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:forest_app/services/api_client.dart';
import 'package:forest_app/ui/action_bar.dart';
import 'package:forest_app/ui/chips.dart';
import 'package:forest_app/ui/forest_icon.dart';
import 'package:forest_app/ui/post_media.dart';

import 'support/harness.dart';

Finder _mediaOf(String postId) =>
    find.byWidgetPredicate((w) => w is PostMedia && w.post.id == postId && !w.fullscreen);

/// One of the prototype's icons, by asset name.
Finder _icon(String name) => find.byWidgetPredicate((w) => w is ForestIcon && w.name == name);

/// Liked hearts (the double-tap burst overlay uses its own icon file).
Finder get _likedHearts => _icon(Icn.heartFilled);

void main() {
  testWidgets('tapping the heart likes, tapping again un-likes, and the server hears both',
      (tester) async {
    useTallScreen(tester);
    final repo = sampleRepo();
    await pumpHome(tester, repo);

    expect(_likedHearts, findsNothing);
    await tester.tap(_icon(Icn.heart).first);
    await settle(tester);
    expect(repo.log, ['like:r3']);
    expect(_likedHearts, findsOneWidget);

    await tester.tap(_likedHearts.first);
    await settle(tester);
    expect(repo.log, ['like:r3', 'unlike:r3']);
    expect(_likedHearts, findsNothing);
  });

  testWidgets('a like the server refuses rolls back and shows why', (tester) async {
    useTallScreen(tester);
    final repo = sampleRepo();
    await pumpHome(tester, repo);
    repo.failNext = const ApiException('Post not found');

    await tester.tap(_icon(Icn.heart).first);
    await settle(tester);
    expect(_likedHearts, findsNothing);
    expect(find.text('Post not found'), findsOneWidget);
  });

  testWidgets('double tap on a video likes it (and only likes)', (tester) async {
    useTallScreen(tester);
    final repo = sampleRepo();
    await pumpHome(tester, repo);

    final media = _mediaOf('p1').first;
    await tester.tap(media);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(media);
    await settle(tester);
    await tester.pump(const Duration(seconds: 1)); // heart burst
    expect(repo.log, ['like:p1']);
  });

  testWidgets('menu → Report → reason sends the report and says so', (tester) async {
    useTallScreen(tester);
    final repo = sampleRepo();
    await pumpHome(tester, repo);

    await tester.tap(_icon(Icn.more).first);
    await settle(tester);
    expect(find.text('Block @kabir_m'), findsOneWidget);
    await tester.tap(find.text('Report'));
    await settle(tester);
    expect(find.text('Why are you reporting this?'), findsOneWidget);
    expect(find.text('Violent or graphic content'), findsOneWidget);
    await tester.tap(find.text('Spam or fake account'));
    await settle(tester);

    expect(repo.log, ['report:r3:SPAM']);
    expect(find.text('Reported. We will review it.'), findsOneWidget);
  });

  testWidgets('menu → Block hides their cards; Undo brings them back and re-follows',
      (tester) async {
    useTallScreen(tester);
    final repo = sampleRepo();
    await pumpHome(tester, repo);
    expect(find.textContaining('The problem is the rollout'), findsOneWidget);

    await tester.tap(_icon(Icn.more).first);
    await settle(tester);
    await tester.tap(find.text('Block @kabir_m'));
    await settle(tester);
    expect(find.textContaining('The problem is the rollout'), findsNothing);
    expect(find.text('Blocked @kabir_m'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(repo.log, ['block:u3', 'unblock:u3', 'follow:u3']);
    expect(find.textContaining('The problem is the rollout'), findsOneWidget);
  });

  testWidgets('menu → Copy link puts the link on the clipboard', (tester) async {
    useTallScreen(tester);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    addTearDown(() =>
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpHome(tester, sampleRepo());

    await tester.tap(_icon(Icn.send).at(1));
    await settle(tester);
    await tester.tap(find.text('Copy link')); // the paper-plane sheet: send to a friend, or copy the link
    await settle(tester);
    expect(copied, startsWith('http'), reason: 'a real link to the public page, not a placeholder');
    expect(copied, endsWith('/p/r3'));
    expect(find.text('Link copied'), findsOneWidget);
  });

  testWidgets('Reply → Aa Text → write → Post reply sends a text reply', (tester) async {
    useTallScreen(tester);
    final repo = sampleRepo();
    await pumpHome(tester, repo);

    await tester.tap(find.text('Reply').first);
    await settle(tester);
    expect(find.text('Reply to @kabir_m'), findsOneWidget);
    expect(find.text('Upload video'), findsOneWidget);

    await tester.tap(find.text('Text'));
    await settle(tester);
    expect(find.text('Gemini will classify your stance'), findsOneWidget);
    expect(find.text('0/280'), findsOneWidget);
    // Post reply is disabled until there is text.
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Post reply')).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'I disagree');
    await tester.pump();
    expect(find.text('10/280'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Post reply'));
    await settle(tester);

    expect(repo.log.last, 'replyText:r3:I disagree');
    expect(find.text('Reply to @kabir_m'), findsNothing, reason: 'sheet closed');
    expect(find.text('Reply posted. AI stance: FOR'), findsOneWidget);
  });

  testWidgets('the reply sheet counts an emoji as one character', (tester) async {
    useTallScreen(tester);
    await pumpHome(tester, sampleRepo());
    await tester.tap(find.text('Reply').first);
    await settle(tester);
    await tester.tap(find.text('Text'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'ab😀');
    await tester.pump();
    expect(find.text('3/280'), findsOneWidget);
  });

  testWidgets('Upload video reveals Record and Gallery', (tester) async {
    useTallScreen(tester);
    await pumpHome(tester, sampleRepo());
    await tester.tap(find.text('Reply').first);
    await settle(tester);
    expect(find.text('Record'), findsNothing);
    await tester.tap(find.text('Upload video'));
    await settle(tester);
    expect(find.text('Record'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);
  });

  testWidgets('a rejected text reply keeps the sheet open and shows the reason', (tester) async {
    useTallScreen(tester);
    final repo = sampleRepo();
    await pumpHome(tester, repo);
    await tester.tap(find.text('Reply').first);
    await settle(tester);
    await tester.tap(find.text('Text'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    repo.failNext = const ApiException("You can't reply to this post");
    await tester.tap(find.widgetWithText(FilledButton, 'Post reply'));
    await settle(tester);

    expect(find.text("You can't reply to this post"), findsOneWidget);
    expect(find.text('Reply to @kabir_m'), findsOneWidget);
  });

  testWidgets('💬 opens the thread as a tree, and the composer posts into it', (tester) async {
    useTallScreen(tester);
    final repo = sampleRepo();
    await pumpHome(tester, repo);

    await tester.tap(find.widgetWithText(ActionButton, '6').first); // p1: six replies
    await settle(tester);
    expect(find.text('Replies'), findsOneWidget);
    // Only visible in the thread, not in any feed card:
    expect(find.text('Learning your state’s language is basic respect.'), findsOneWidget);
    expect(find.text('Dropout data needs context. Which states and which years?'), findsOneWidget);
    expect(find.text('Reply to @aman_s…'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, ''), 'My take');
    await tester.pump();
    await tester.tap(find.text('Post'));
    await settle(tester);

    expect(repo.log.last, 'replyText:p1:My take');
    expect(find.text('My take'), findsOneWidget, reason: 'thread reloaded with the new reply');
    expect(find.text('Reply posted. AI stance: FOR'), findsOneWidget);
    expect(find.text('Could not post your reply. Try again.'), findsNothing, reason: 'a reply that went through is not reported as a failure');
    expect(tester.takeException(), isNull, reason: 'reloading the thread must not trip a Flutter assertion');
  });

  testWidgets('"in @aman_s’s debate →" opens the root thread', (tester) async {
    useTallScreen(tester);
    await pumpHome(tester, sampleRepo());
    await tester.tap(find.text('in @aman_s’s debate →'));
    await settle(tester);
    expect(find.text('Replies'), findsOneWidget);
    expect(find.textContaining('@aman_s: Should Punjabi'), findsOneWidget);
  });

  testWidgets('tapping a video opens the full-screen viewer and Back closes it', (tester) async {
    useTallScreen(tester);
    await pumpHome(tester, sampleRepo());

    await tester.tap(_mediaOf('p1').first);
    await settle(tester);
    expect(find.byTooltip('Back to feed'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is PostMedia && w.fullscreen), findsOneWidget);

    await tester.tap(find.byTooltip('Back to feed'));
    await settle(tester);
    expect(find.byTooltip('Back to feed'), findsNothing);
  });

  testWidgets('a video with no file does not open a viewer', (tester) async {
    useTallScreen(tester);
    await pumpHome(tester, sampleRepo());
    await tester.tap(_mediaOf('p2').first); // forest_daily: no file
    await settle(tester);
    expect(find.byTooltip('Back to feed'), findsNothing);
  });

  testWidgets('a text reply to a text reply shows the parent as text, labelled', (tester) async {
    useTallScreen(tester);
    await pumpHome(tester, sampleRepo(homeOrder: ['x3']));
    // x3 is aman_s replying to simran.v's text reply r2.
    expect(find.text('PARENT REPLY'), findsOneWidget);
    expect(find.textContaining('Dropout data needs context'), findsOneWidget);
    expect(find.textContaining('Most states that did this'), findsOneWidget);
    expect(find.byType(PostMedia), findsNothing, reason: 'no video anywhere in this card');
    expect(find.text('UNRESOLVED'), findsOneWidget);
    expect(find.byType(BotTag), findsNothing);
  });
}
