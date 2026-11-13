import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:forest_app/data/fake_feed_repository.dart';
import 'package:forest_app/features/home/feed_controller.dart';
import 'package:forest_app/features/today/prompt_screen.dart';
import 'package:forest_app/features/today/today_controller.dart';
import 'package:forest_app/features/today/today_repository.dart';
import 'package:forest_app/models/post.dart';
import 'package:forest_app/services/analytics.dart';
import 'package:forest_app/theme/forest_theme.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

Map<String, dynamic> postJson(String id, {String? title, int replies = 0}) => {
      'id': id,
      'kind': 'VIDEO',
      'parentId': null,
      'rootId': id,
      'depth': 0,
      'title': title,
      'body': null,
      'mediaUrl': null,
      'stance': 'PARENT',
      'status': 'READY',
      'summary': null,
      'createdAt': '2026-10-21T10:00:00.000Z',
      'likeCount': 0,
      'likedByMe': false,
      'replyCount': replies,
      'forCount': 0,
      'againstCount': 0,
    };

Map<String, dynamic> itemJson(String id, String username, {String? title, bool bot = false, int replies = 0, Map<String, dynamic>? extra}) => {
      'type': 'POST',
      'actor': {'id': 'u-$username', 'username': username, 'fullName': username, 'avatarUrl': null, 'isBot': bot},
      'post': {...postJson(id, title: title, replies: replies), ...?extra},
      'parent': null,
      'root': null,
      'createdAt': '2026-10-21T10:00:00.000Z',
    };

const _prompt = {'day': '2026-10-21', 'text': 'Should attendance be compulsory in colleges?', 'topic': 'education', 'answerCount': 0, 'answered': false};

FakeServer server({Map<String, dynamic> prompt = _prompt, List<Map<String, dynamic>> waiting = const [], List<Map<String, dynamic>> answers = const []}) => FakeServer()
  ..json('GET /api/prompts/today', prompt)
  ..json('GET /api/reply-wanted', {'items': waiting})
  ..json('GET /api/prompts/today/answers', {'items': answers})
  ..json('POST /api/events', {'recorded': 1});

TodayController controllerFor(FakeServer s) => TodayController(TodayRepository(s.client()));

void main() {
  group('repository and controller', () {
    test('the question and the waiting list are read from the server', () async {
      final s = server(prompt: {..._prompt, 'answerCount': 4, 'answered': true}, waiting: [itemJson('p1', 'asha', title: 'Nobody has answered me')]);
      final c = controllerFor(s);
      await c.load();
      expect(c.prompt!.text, 'Should attendance be compulsory in colleges?');
      expect(c.prompt!.day, '2026-10-21');
      expect(c.prompt!.answerCount, 4);
      expect(c.prompt!.answered, isTrue);
      expect(c.waiting.single.post.id, 'p1');
      expect(s.last('GET /api/reply-wanted').uri.queryParameters['limit'], '5');
    });

    test('if one call fails the other still shows, and if both fail nothing shows', () async {
      final half = server()..json('GET /api/reply-wanted', {'error': 'down'}, status: 500);
      final a = controllerFor(half);
      await a.load();
      expect(a.prompt, isNotNull);
      expect(a.waiting, isEmpty);

      final none = FakeServer();
      final b = controllerFor(none);
      await b.load();
      expect(b.prompt, isNull);
      expect(b.waiting, isEmpty);
    });

    test('a failed refresh keeps what was already known', () async {
      final s = server(waiting: [itemJson('p1', 'asha')]);
      final c = controllerFor(s);
      await c.load();
      s.json('GET /api/prompts/today', {'error': 'down'}, status: 500);
      s.json('GET /api/reply-wanted', {'error': 'down'}, status: 500);
      await c.load();
      expect(c.prompt, isNotNull);
      expect(c.waiting, hasLength(1));
    });

    test('replying removes that opinion from the list, and answering marks the question and counts it', () async {
      final s = server(waiting: [itemJson('p1', 'asha'), itemJson('p2', 'bala')]);
      final c = controllerFor(s);
      await c.load();
      c.markReplied('p1');
      expect(c.waiting.map((i) => i.post.id), ['p2']);
      c.markAnswered();
      expect(c.prompt!.answered, isTrue);
      expect(c.prompt!.answerCount, 1);
      c.markAnswered();
      expect(c.prompt!.answerCount, 1, reason: 'only once');
    });

    test('posts carry the question day, the room and the room stance when the server sends them', () {
      final post = Post.fromJson({...postJson('p9'), 'promptDay': '2026-10-21', 'room': {'id': 'r1', 'name': 'Debate society'}, 'roomStance': 'AGAINST'});
      expect(post.promptDay, '2026-10-21');
      expect(post.room!.name, 'Debate society');
      expect(post.roomStance, Stance.against);
      final plain = Post.fromJson(postJson('p10'));
      expect(plain.promptDay, isNull);
      expect(plain.room, isNull);
      expect(plain.roomStance, isNull);
      expect(Post.fromJson({...postJson('p11'), 'roomStance': 'SOMETHING_NEW'}).roomStance, isNull, reason: 'an unknown word never crashes the card');
      expect(post.copyWith(likeCount: 3).room!.id, 'r1', reason: 'copying keeps them');
    });
  });

  group('on Home', () {
    testWidgets('the question and what is waiting sit above the feed', (tester) async {
      useTallScreen(tester);
      final s = server(
        prompt: {..._prompt, 'answerCount': 3},
        waiting: [itemJson('w1', 'asha', title: 'Phones in class?'), itemJson('w2', 'meera_j', title: 'Four-day week', bot: true)],
      );
      final today = controllerFor(s)..load();
      await pumpHome(tester, FakeFeedRepository.sample(), today: today);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('today-header')), findsOneWidget);
      expect(find.text('QUESTION OF THE DAY'), findsOneWidget);
      expect(find.byKey(const Key('prompt-text')), findsOneWidget);
      expect(find.text('3 answers · see them'), findsOneWidget);
      expect(find.byKey(const Key('prompt-answer')), findsOneWidget);
      expect(find.text('Waiting for an answer'), findsOneWidget);
      expect(find.text('Phones in class?'), findsOneWidget);
      expect(find.text('Four-day week'), findsOneWidget);
      expect(find.text('BOT'), findsWidgets, reason: 'a bot is still labelled a bot');
      // the feed is still there below
      expect(find.byType(ListView), findsWidgets);
    });

    testWidgets('with no answers yet it says so, and once answered it shows a tick instead of the button', (tester) async {
      useTallScreen(tester);
      final today = controllerFor(server())..load();
      await pumpHome(tester, FakeFeedRepository.sample(), today: today);
      await tester.pumpAndSettle();
      expect(find.text('No answers yet. Be the first.'), findsOneWidget);

      today.markAnswered();
      await tester.pumpAndSettle();
      expect(find.text('You answered'), findsOneWidget);
      expect(find.byKey(const Key('prompt-answer')), findsNothing);
      expect(find.text('1 answer · see them'), findsOneWidget);
    });

    testWidgets('nothing is drawn when the server has no question, and Home still works', (tester) async {
      useTallScreen(tester);
      final today = controllerFor(FakeServer())..load();
      await pumpHome(tester, FakeFeedRepository.sample(), today: today);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('today-header')), findsNothing);
      expect(find.text('QUESTION OF THE DAY'), findsNothing);
    });

    testWidgets('a new account with an empty Home still gets the question above the people to follow', (tester) async {
      useTallScreen(tester);
      final today = controllerFor(server())..load();
      await pumpHome(tester, FakeFeedRepository.sample(homeOrder: const []), today: today);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('prompt-text')), findsOneWidget);
    });

    testWidgets('Answer opens the upload choices titled for the question, and measures the tap', (tester) async {
      useTallScreen(tester);
      final s = server();
      final today = controllerFor(s)..load();
      await pumpHome(tester, FakeFeedRepository.sample(), today: today, analytics: Analytics(s.client()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prompt-answer')));
      await tester.pumpAndSettle();
      expect(find.text('Answer today\'s question'), findsWidgets);
      expect(find.text('Record a video'), findsOneWidget);
      expect(find.text('Choose a video'), findsOneWidget);
      final events = s.seen.where((x) => x.path == '/api/events').expand((x) => (x.json['events'] as List)).map((e) => (e as Map)['name']);
      expect(events, contains('prompt_opened'));
    });

    testWidgets('Reply on a waiting opinion opens the reply sheet and measures the tap', (tester) async {
      useTallScreen(tester);
      final s = server(waiting: [itemJson('w1', 'asha', title: 'Phones in class?')]);
      final today = controllerFor(s)..load();
      await pumpHome(tester, FakeFeedRepository.sample(), today: today, analytics: Analytics(s.client()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('waiting-reply-w1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Video replies are the heart of FOREST'), findsOneWidget, reason: 'the reply sheet opened');
      final events = s.seen.where((x) => x.path == '/api/events').expand((x) => (x.json['events'] as List)).map((e) => (e as Map)['name']);
      expect(events, contains('reply_wanted_opened'));
    });
  });

  group('the question page', () {
    Future<void> openPage(WidgetTester tester, FakeServer s, {TodayController? today}) async {
      useTallScreen(tester);
      final c = today ?? (controllerFor(s)..load());
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<FeedController>(create: (_) => FeedController(FakeFeedRepository.sample())),
        ],
        child: MaterialApp(theme: ForestTheme.dark, home: Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PromptScreen(controller: c))), child: const Text('open'))))),
      ));
      await tester.runAsync(() => c.load());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the question, the answer button, and everyone\'s answers as cards', (tester) async {
      final s = server(answers: [itemJson('a1', 'asha', title: 'Yes, because attendance is a trap'), itemJson('a2', 'bala', title: 'No, it is the only thing that works')]);
      await openPage(tester, s);
      expect(find.byKey(const Key('prompt-screen-text')), findsOneWidget);
      expect(find.byKey(const Key('prompt-screen-answer')), findsOneWidget);
      expect(find.byKey(const ValueKey('answer-a1')), findsOneWidget);
      expect(find.byKey(const ValueKey('answer-a2')), findsOneWidget);
      expect(find.textContaining('attendance is a trap'), findsWidgets);
    });

    testWidgets('an empty day invites the first answer', (tester) async {
      await openPage(tester, server());
      expect(find.textContaining('Nobody has answered yet'), findsOneWidget);
    });

    testWidgets('someone who already answered sees a tick, not the button', (tester) async {
      await openPage(tester, server(prompt: {..._prompt, 'answered': true, 'answerCount': 1}));
      expect(find.text('You answered this one'), findsOneWidget);
      expect(find.byKey(const Key('prompt-screen-answer')), findsNothing);
    });

    testWidgets('a failing answers call says so instead of spinning', (tester) async {
      final s = server()..json('GET /api/prompts/today/answers', {'error': 'The server is busy'}, status: 503);
      await openPage(tester, s);
      expect(find.text('The server is busy'), findsOneWidget);
    });
  });

  group('analytics', () {
    test('events are sent at once, in a batch, and a failure is dropped without a fuss', () async {
      final s = FakeServer()..json('POST /api/events', {'recorded': 2});
      final a = Analytics(s.client());
      a.track('app_open');
      a.track('invite_copied', {'from': 'sheet'});
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final names = s.seen.expand((x) => (x.json['events'] as List)).map((e) => (e as Map)['name']).toList();
      expect(names, ['app_open', 'invite_copied']);
      expect((s.seen.last.json['events'] as List).last, {'name': 'invite_copied', 'props': {'from': 'sheet'}});

      final down = FakeServer()..json('POST /api/events', {'error': 'down'}, status: 500);
      final b = Analytics(down.client());
      b.track('app_open'); // must not throw, now or later
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(down.count('POST /api/events'), 1, reason: 'no retries');
    });
  });
}
