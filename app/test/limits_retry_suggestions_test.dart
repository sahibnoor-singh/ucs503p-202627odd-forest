// docs/APP_INTEGRATION_TODO.md steps 1 and 2: the server's 429/503 answers,
// Retry for a FAILED video, and the suggested people on an empty Home.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:forest_app/data/fake_feed_repository.dart';
import 'package:forest_app/features/home/feed_controller.dart';
import 'package:forest_app/models/post.dart';
import 'package:forest_app/services/api_client.dart';
import 'package:forest_app/ui/chips.dart';
import 'package:forest_app/ui/post_media.dart';
import 'package:forest_app/theme/forest_theme.dart';

import 'support/harness.dart';

Future<ApiException> _failure(http.Response Function() answer) async {
  final api = ApiClient(
    baseUrl: 'http://x',
    devUser: '',
    client: MockClient((_) async => answer()),
  );
  try {
    await api.getJson('/api/home');
  } on ApiException catch (e) {
    return e;
  }
  throw StateError('expected an ApiException');
}

/// Toast messages the controller says, in order.
List<String> _listen(FeedController c) {
  final said = <String>[];
  c.toasts.listen((t) => said.add(t.message));
  return said;
}

void main() {
  group('429 and 503 (docs/api.md "Limits")', () {
    test('the server\'s own message is kept and retryAfterSec is read from the body', () async {
      final e = await _failure(() => http.Response(
            '{"error":"Slow down: 15 new posts a minute.","retryAfterSec":12}',
            429,
            headers: {'content-type': 'application/json'},
          ));
      expect(e.message, 'Slow down: 15 new posts a minute.');
      expect(e.isRateLimited, isTrue);
      expect(e.shouldBackOff, isTrue);
      expect(e.retryAfterSec, 12);
      expect(e.backOff(), const Duration(seconds: 12));
    });

    test('Retry-After header is used when the body has no number', () async {
      final e = await _failure(
          () => http.Response('{"error":"Too many attempts."}', 429, headers: {'retry-after': '30'}));
      expect(e.retryAfterSec, 30);
    });

    test('a 503 means busy, and a body-less answer still gets a readable message', () async {
      final e = await _failure(() => http.Response('', 503));
      expect(e.isBusy, isTrue);
      expect(e.shouldBackOff, isTrue);
      expect(e.message, contains('busy'));
      expect(e.retryAfterSec, isNull);
      expect(e.backOff(), const Duration(seconds: 15), reason: 'default when the server gave no number');
    });

    test('the wait is never zero and never longer than a minute', () {
      expect(const ApiException('x', statusCode: 429, retryAfterSec: 0).backOff(), const Duration(seconds: 1));
      expect(const ApiException('x', statusCode: 429, retryAfterSec: 900).backOff(), const Duration(minutes: 1));
    });

    test('other errors do not ask to back off', () async {
      final e = await _failure(() => http.Response('{"error":"Nope"}', 404));
      expect(e.shouldBackOff, isFalse);
      expect(e.message, 'Nope');
    });

    testWidgets('a 429 on refresh shows the server\'s words and the app then leaves it alone',
        (tester) async {
      useTallScreen(tester);
      var now = DateTime.utc(2026, 10, 11, 12);
      final repo = sampleRepo();
      repo.failNext = const ApiException('Too many requests. Wait 30 seconds.',
          statusCode: 429, retryAfterSec: 30);
      final c = await pumpHome(tester, repo, clock: () => now);
      final said = _listen(c);

      expect(c.coolDownSeconds, 30);
      expect(c.error, 'Too many requests. Wait 30 seconds.');

      // Pulling again during the wait does not touch the server.
      repo.failNext = const ApiException('should not be asked');
      await c.refresh();
      expect(repo.failNext, isNotNull, reason: 'the second request was never sent');
      await tester.pump();
      expect(said.single, contains('slow down'));

      // After the wait it asks again (and gets the queued failure).
      now = now.add(const Duration(seconds: 31));
      expect(c.coolDownSeconds, 0);
      await c.refresh();
      expect(repo.failNext, isNull);
    });

    testWidgets('scrolling does not hammer the server after a failed next page', (tester) async {
      useTallScreen(tester);
      var now = DateTime.utc(2026, 10, 11, 12);
      final repo = sampleRepo(homeOrder: ['p1', 'r1', 'r2', 'r3', 'p2']);
      final c = await pumpHome(tester, repo, clock: () => now, pageSize: 2);
      expect(c.hasMore, isTrue);

      repo.failNext = const ApiException('Busy.', statusCode: 503);
      await c.loadMore();
      expect(c.hasMore, isTrue);

      repo.failNext = const ApiException('must not be requested');
      for (var i = 0; i < 5; i++) {
        await c.loadMore(); // what the scroll listener does on every scroll event
      }
      expect(repo.failNext, isNotNull, reason: 'blocked while the 503 cool-down runs');

      now = now.add(const Duration(seconds: 20));
      await c.loadMore();
      expect(repo.failNext, isNull, reason: 'asked again once the wait was over');
    });

    testWidgets('video polling slows down when the server says wait, and says so once',
        (tester) async {
      useTallScreen(tester);
      final repo = sampleRepo()..pollsUntilReady = 2;
      final c = await pumpHome(tester, repo);
      final said = _listen(c);
      final parent = (await repo.post('r3')).post;
      repo.postReads = 0;

      await c.replyVideo(parent, 'clip.mp4');
      repo.failNext = const ApiException('Busy.', statusCode: 429, retryAfterSec: 5);
      await tester.pump(const Duration(milliseconds: 60)); // first poll: refused
      await tester.pump();
      expect(repo.postReads, 1);

      await tester.pump(const Duration(seconds: 3));
      expect(repo.postReads, 1, reason: 'still inside the 5 s the server asked for');

      await tester.pump(const Duration(seconds: 3));
      expect(repo.postReads, greaterThan(1), reason: 'polling carried on afterwards');
      expect(said.where((m) => m == 'Busy.'), hasLength(1));
    });
  });

  group('Retry for a FAILED video', () {
    Future<(FeedController, FakeFeedRepository, List<ToastEvent>, Post)> failedReply(
        WidgetTester tester) async {
      useTallScreen(tester);
      final repo = sampleRepo();
      final c = await pumpHome(tester, repo);
      final events = <ToastEvent>[];
      c.toasts.listen(events.add);
      final parent = (await repo.post('r3')).post;
      repo.failNextAnalysis = true;
      final item = await c.replyVideo(parent, 'clip.mp4');
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      return (c, repo, events, item.post);
    }

    testWidgets('a failed analysis offers Retry, and Retry re-runs it without uploading again',
        (tester) async {
      final (c, repo, events, post) = await failedReply(tester);
      expect(c.resolve(post).status, PostStatus.failed);
      final failed = events.lastWhere((e) => e.message.contains('could not be processed'));
      expect(failed.actionLabel, 'Retry');

      failed.onAction!();
      await tester.pump();
      expect(repo.log.where((l) => l.startsWith('replyVideo')), hasLength(1), reason: 'no second upload');
      expect(repo.log, contains('retry:${post.id}'));
      expect(c.resolve(post).status, PostStatus.processing);

      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      expect(c.resolve(post).status, PostStatus.ready);
      expect(events.last.message, contains('ready'));
    });

    testWidgets('a retry the server answers with 410 tells the person to record again',
        (tester) async {
      final (c, repo, events, post) = await failedReply(tester);
      repo.goneFiles.add(post.id);
      await c.retryVideo(post);
      await tester.pump();
      expect(events.last.message, contains('file is gone'));
      expect(events.last.message, contains('Record it again'));
      expect(c.resolve(post).status, PostStatus.failed, reason: 'nothing changed');
    });

    testWidgets('tapping Retry twice sends one request', (tester) async {
      final (c, repo, _, post) = await failedReply(tester);
      final first = c.retryVideo(post);
      final second = c.retryVideo(post);
      await Future.wait([first, second]);
      expect(repo.log.where((l) => l == 'retry:${post.id}'), hasLength(1));
    });

    testWidgets('the failed media box has a Retry button, only when a retry is possible',
        (tester) async {
      final post = Post.fromJson({
        'id': 'v1',
        'kind': 'VIDEO',
        'parentId': null,
        'rootId': 'v1',
        'depth': 0,
        'title': null,
        'body': null,
        'mediaUrl': '/uploads/v1.mp4',
        'stance': 'PARENT',
        'status': 'FAILED',
        'summary': null,
        'createdAt': '2026-10-11T12:00:00Z',
        'likeCount': 0,
        'likedByMe': false,
        'replyCount': 0,
        'forCount': 0,
        'againstCount': 0,
      });
      var retried = 0;
      Widget media({VoidCallback? onRetry}) => MaterialApp(
            theme: ForestTheme.dark,
            home: Scaffold(
              body: PostMedia(
                post: post,
                mediaUrl: null,
                muted: true,
                onToggleMute: () {},
                onRetry: onRetry,
              ),
            ),
          );

      await tester.pumpWidget(media());
      expect(find.text('Processing failed'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);

      await tester.pumpWidget(media(onRetry: () => retried++));
      await tester.tap(find.text('Retry'));
      expect(retried, 1);
    });
  });

  group('suggested people on an empty Home', () {
    testWidgets('a new account sees people to follow, with BOT labels, instead of a dead end',
        (tester) async {
      useTallScreen(tester);
      final repo = sampleRepo(homeOrder: []);
      await pumpHome(tester, repo);
      await settle(tester);

      expect(find.text('Follow people to fill your Home'), findsOneWidget);
      expect(find.text('Nothing here yet'), findsNothing);
      expect(repo.log, contains('suggested'));
      expect(find.text('aman_s'), findsOneWidget);
      expect(find.text('Aman Singh'), findsOneWidget);
      expect(find.byKey(const ValueKey('follow-u1')), findsOneWidget);

      // forest_daily is a bot: it is labelled here too (CLAUDE.md hard rule).
      final row = find.byKey(const ValueKey('suggested-u7'));
      expect(find.descendant(of: row, matching: find.byType(BotTag)), findsOneWidget);
      final human = find.byKey(const ValueKey('suggested-u1'));
      expect(find.descendant(of: human, matching: find.byType(BotTag)), findsNothing);
    });

    testWidgets('Follow shows Following at once, tells the server, and Show my feed appears',
        (tester) async {
      useTallScreen(tester);
      final repo = sampleRepo(homeOrder: []);
      await pumpHome(tester, repo);
      await settle(tester);
      expect(find.byKey(const ValueKey('show-my-feed')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('follow-u1')));
      await tester.pump();
      expect(find.descendant(of: find.byKey(const ValueKey('follow-u1')), matching: find.text('Following')),
          findsOneWidget);
      await settle(tester);
      expect(repo.log, contains('follow:u1'));
      expect(find.byKey(const ValueKey('show-my-feed')), findsOneWidget);

      // Tapping Following again unfollows.
      await tester.tap(find.byKey(const ValueKey('follow-u1')));
      await settle(tester);
      expect(repo.log, contains('unfollow:u1'));
      expect(find.byKey(const ValueKey('show-my-feed')), findsNothing);
    });

    testWidgets('Show my feed loads Home again, which now has the followed person\'s posts',
        (tester) async {
      useTallScreen(tester);
      final repo = sampleRepo(homeOrder: []);
      final c = await pumpHome(tester, repo);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('follow-u1')));
      await settle(tester);

      final readsBefore = repo.homeReads;
      await tester.tap(find.byKey(const ValueKey('show-my-feed')));
      await settle(tester);
      expect(repo.homeReads, readsBefore + 1);
      expect(c.loading, isFalse);
    });

    testWidgets('a Follow the server refuses is undone and says why', (tester) async {
      useTallScreen(tester);
      final repo = sampleRepo(homeOrder: []);
      await pumpHome(tester, repo);
      await settle(tester);

      repo.failNext = const ApiException('You are following people too fast.', statusCode: 429, retryAfterSec: 10);
      await tester.tap(find.byKey(const ValueKey('follow-u1')));
      await settle(tester);
      expect(find.descendant(of: find.byKey(const ValueKey('follow-u1')), matching: find.text('Follow')),
          findsOneWidget);
      expect(find.text('You are following people too fast.'), findsOneWidget);
      expect(find.byKey(const ValueKey('show-my-feed')), findsNothing);
    });

    testWidgets('if the suggestions cannot be loaded there is the server\'s message and a Retry',
        (tester) async {
      useTallScreen(tester);
      var now = DateTime.utc(2026, 10, 11, 12);
      final repo = sampleRepo(homeOrder: [])
        ..failSuggestions = const ApiException('Busy. Try again soon.', statusCode: 503);
      await pumpHome(tester, repo, clock: () => now);
      await settle(tester);
      expect(find.text('Busy. Try again soon.'), findsOneWidget);
      expect(find.text('Go to Discover'), findsOneWidget, reason: 'never a dead end');

      // Retry inside the server's wait does not ask it again.
      repo.failSuggestions = null;
      final asked = repo.log.where((l) => l == 'suggested').length;
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(repo.log.where((l) => l == 'suggested').length, asked);
      expect(find.textContaining('slow down'), findsOneWidget);

      now = now.add(const Duration(seconds: 20));
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(find.byKey(const ValueKey('follow-u1')), findsOneWidget);
    });

    testWidgets('nobody to suggest still leaves a way forward', (tester) async {
      useTallScreen(tester);
      final repo = sampleRepo(homeOrder: [])..suggested = const [];
      await pumpHome(tester, repo);
      await settle(tester);
      expect(find.textContaining('Nobody to suggest yet'), findsOneWidget);
      expect(find.text('Go to Discover'), findsOneWidget);
    });

    testWidgets('a Home with posts does not ask for suggestions', (tester) async {
      useTallScreen(tester);
      final repo = sampleRepo();
      await pumpHome(tester, repo);
      await settle(tester);
      expect(repo.log, isNot(contains('suggested')));
      expect(find.text('Follow people to fill your Home'), findsNothing);
    });
  });
}
