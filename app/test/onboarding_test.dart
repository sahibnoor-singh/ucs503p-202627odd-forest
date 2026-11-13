import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:forest_app/data/fake_feed_repository.dart';
import 'package:forest_app/data/feed_repository.dart';
import 'package:forest_app/features/auth/auth_gate.dart';
import 'package:forest_app/features/onboarding/onboarding_controller.dart';
import 'package:forest_app/features/onboarding/onboarding_repository.dart';
import 'package:forest_app/models/user.dart';
import 'package:forest_app/services/api_client.dart';
import 'package:forest_app/services/session.dart';
import 'package:forest_app/theme/forest_theme.dart';

import 'support/fake_server.dart';

const _topics = [
  {'id': 'politics', 'label': 'Politics'},
  {'id': 'economy', 'label': 'Economy'},
  {'id': 'jobs', 'label': 'Jobs and careers'},
  {'id': 'tech', 'label': 'Technology and AI'},
  {'id': 'sports', 'label': 'Sports'},
];

const _asha = User(id: 'u-asha', username: 'asha', fullName: 'Asha', avatarUrl: null, isBot: false);
const _meera = User(id: 'u-meera', username: 'meera_j', fullName: 'Meera', avatarUrl: null, isBot: true);

FakeServer _server({int min = 3, int max = 4}) => FakeServer()
  ..json('GET /api/onboarding/topics', {'topics': _topics, 'min': min, 'max': max})
  ..json('POST /api/me/onboarding', {'topics': []});

FakeFeedRepository _feed() => FakeFeedRepository.sample()
  ..suggested = [
    const SuggestedUser(user: _asha, followerCount: 3, postCount: 5),
    const SuggestedUser(user: _meera, followerCount: 1, postCount: 1),
  ];

OnboardingController _controller(FakeServer s, FakeFeedRepository feed) => OnboardingController(OnboardingRepository(s.client()), feed);

void main() {
  group('controller', () {
    test('loads the topics; none are ticked to begin with', () async {
      final c = _controller(_server(), _feed());
      await c.loadTopics();
      expect(c.offer!.topics.length, 5);
      expect(c.selected, isEmpty);
      expect(c.canContinue, isFalse);
      expect(c.step, OnboardingStep.topics);
    });

    test('a failed topics call can be retried', () async {
      final s = FakeServer(); // nothing registered: 404
      final c = _controller(s, _feed());
      await c.loadTopics();
      expect(c.offer, isNull);
      expect(c.topicsError, isNotNull);
      s.json('GET /api/onboarding/topics', {'topics': _topics, 'min': 3, 'max': 4});
      await c.loadTopics();
      expect(c.offer, isNotNull);
      expect(c.topicsError, isNull);
    });

    test('continue needs the minimum, and no more than the maximum can be ticked', () async {
      final c = _controller(_server(), _feed());
      await c.loadTopics();
      c.toggle('politics');
      c.toggle('economy');
      expect(c.canContinue, isFalse);
      c.toggle('jobs');
      expect(c.canContinue, isTrue);
      c.toggle('tech');
      c.toggle('sports'); // a fifth: refused, the maximum is 4
      expect(c.selected, {'politics', 'economy', 'jobs', 'tech'});
      c.toggle('economy'); // unticking works
      expect(c.selected.length, 3);
    });

    test('continuing saves the chosen ids in list order and moves to the people page', () async {
      final s = _server();
      final c = _controller(s, _feed());
      await c.loadTopics();
      c.toggle('tech');
      c.toggle('politics');
      c.toggle('jobs');
      await c.continueWithTopics();
      expect(s.last('POST /api/me/onboarding').json, {'topics': ['politics', 'jobs', 'tech']});
      expect(c.step, OnboardingStep.people);
      expect(c.people!.map((p) => p.user.username), ['asha', 'meera_j']);
      expect(c.saveError, isNull);
    });

    test('skip saves an empty list and still shows the people', () async {
      final s = _server();
      final c = _controller(s, _feed());
      await c.loadTopics();
      await c.skip();
      expect(s.last('POST /api/me/onboarding').json, {'topics': []});
      expect(c.step, OnboardingStep.people);
      expect(c.people, isNotEmpty);
    });

    test('a failed save never traps the person: they move on and are told the topics were not saved', () async {
      final s = _server()..json('POST /api/me/onboarding', {'error': 'down'}, status: 500);
      final c = _controller(s, _feed());
      await c.loadTopics();
      for (final id in ['politics', 'economy', 'jobs']) {
        c.toggle(id);
      }
      await c.continueWithTopics();
      expect(c.step, OnboardingStep.people);
      expect(c.saveError, contains('could not be saved'));
    });

    test('no suggestions (or a failing call) leaves an empty list, not a stuck spinner', () async {
      final feed = _feed()..failSuggestions = const ApiException('down');
      final c = _controller(_server(), feed);
      await c.loadTopics();
      await c.skip();
      expect(c.people, isEmpty);
      expect(c.loadingPeople, isFalse);
    });

    test('follow is shown at once and undone when the server refuses', () async {
      final feed = _feed();
      final c = _controller(_server(), feed);
      await c.loadTopics();
      await c.skip();
      await c.toggleFollow(_asha);
      expect(c.followed, {'u-asha'});
      expect(feed.log, contains('follow:u-asha'));
      await c.toggleFollow(_asha);
      expect(c.followed, isEmpty);
      expect(feed.log, contains('unfollow:u-asha'));

      feed.failNext = const ApiException('Could not follow right now');
      await c.toggleFollow(_meera);
      expect(c.followed, isEmpty, reason: 'the optimistic follow was rolled back');
      expect(c.followError, 'Could not follow right now');
    });
  });

  group('session', () {
    test('a new account is flagged, the flag survives a restart, and finishing clears it for good', () async {
      final store = MemoryTokenStore();
      final first = Session(store: store);
      await first.restore();
      await first.signIn(token: 'tok', user: _asha, newAccount: true);
      expect(first.needsOnboarding, isTrue);

      final restarted = Session(store: store); // the app was closed in the middle
      await restarted.restore();
      expect(restarted.needsOnboarding, isTrue);

      await restarted.finishOnboarding();
      expect(restarted.needsOnboarding, isFalse);
      final later = Session(store: store);
      await later.restore();
      expect(later.needsOnboarding, isFalse);
    });

    test('a normal login is never sent through it, and logging out forgets a pending flag', () async {
      final store = MemoryTokenStore();
      final s = Session(store: store);
      await s.restore();
      await s.signIn(token: 'tok', user: _asha);
      expect(s.needsOnboarding, isFalse);

      await s.signIn(token: 'tok2', user: _asha, newAccount: true);
      await s.signOut();
      expect(s.needsOnboarding, isFalse);
      await s.signIn(token: 'tok3', user: _meera); // someone else logging in on the same phone
      expect(s.needsOnboarding, isFalse);
      final again = Session(store: store);
      await again.restore();
      expect(again.needsOnboarding, isFalse);
    });
  });

  group('screens', () {
    Future<(Session, FakeServer, FakeFeedRepository)> boot(WidgetTester tester, {bool needs = true, FakeServer? server}) async {
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = server ?? _server();
      final feed = _feed();
      final session = Session.signedIn(user: _asha, needsOnboarding: needs);
      final api = s.client(token: () => session.token);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<Session>.value(value: session),
          Provider<ApiClient>.value(value: api),
          Provider<OnboardingRepository>.value(value: OnboardingRepository(api)),
          Provider<FeedRepository>.value(value: feed),
        ],
        child: MaterialApp(theme: ForestTheme.light, home: const AuthGate(app: Scaffold(body: Center(child: Text('THE APP'))))),
      ));
      await tester.pumpAndSettle();
      return (session, s, feed);
    }

    testWidgets('someone who already has an account goes straight to the app', (tester) async {
      await boot(tester, needs: false);
      expect(find.text('THE APP'), findsOneWidget);
      expect(find.byKey(const Key('onboarding-topics')), findsNothing);
    });

    testWidgets('topics, then people, then the app; the chosen topics and follows are sent', (tester) async {
      final (session, server, feed) = await boot(tester);
      expect(find.text('THE APP'), findsNothing);
      expect(find.text('What should we show you?'), findsOneWidget);
      expect(find.byKey(const Key('onboarding-count')), findsOneWidget);
      expect(find.text('0 of 3 chosen'), findsOneWidget);

      // Continue is off until three are chosen
      expect(tester.widget<FilledButton>(find.byKey(const Key('onboarding-continue'))).onPressed, isNull);
      for (final id in ['politics', 'jobs', 'tech']) {
        await tester.tap(find.byKey(Key('topic-$id')));
        await tester.pump();
      }
      expect(find.text('3 chosen'), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding-continue')));
      await tester.pumpAndSettle();
      expect(server.last('POST /api/me/onboarding').json, {'topics': ['politics', 'jobs', 'tech']});

      expect(find.text('Follow a few people'), findsOneWidget);
      expect(find.text('asha'), findsOneWidget);
      expect(find.text('BOT'), findsOneWidget, reason: 'bots stay labelled');
      expect(find.text('Skip for now'), findsOneWidget);
      await tester.tap(find.byKey(const Key('follow-u-asha')));
      await tester.pumpAndSettle();
      expect(feed.log, contains('follow:u-asha'));
      expect(find.text('Done, following 1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('onboarding-done')));
      await tester.pumpAndSettle();
      // the guide: three ideas, one at a time, then the app
      for (var i = 0; i < 3; i++) {
        expect(find.byKey(Key('onboarding-guide-$i')), findsOneWidget);
        expect(find.text('${i + 1} of 3'), findsOneWidget);
        expect(session.needsOnboarding, isTrue, reason: 'still in onboarding until the last idea');
        await tester.tap(find.byKey(const Key('guide-next')));
        await tester.pumpAndSettle();
      }
      expect(session.needsOnboarding, isFalse);
      expect(find.text('THE APP'), findsOneWidget);
    });

    testWidgets('the guide can be skipped at any idea', (tester) async {
      final (session, _, _) = await boot(tester);
      await tester.tap(find.byKey(const Key('onboarding-skip')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboarding-done')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('guide-next')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('onboarding-guide-1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('guide-skip')));
      await tester.pumpAndSettle();
      expect(session.needsOnboarding, isFalse);
      expect(find.text('THE APP'), findsOneWidget);
    });

    testWidgets('skipping everything still ends in the app', (tester) async {
      final (session, server, _) = await boot(tester);
      await tester.tap(find.byKey(const Key('onboarding-skip')));
      await tester.pumpAndSettle();
      expect(server.last('POST /api/me/onboarding').json, {'topics': []});
      await tester.tap(find.byKey(const Key('onboarding-done')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('guide-skip')));
      await tester.pumpAndSettle();
      expect(session.needsOnboarding, isFalse);
      expect(find.text('THE APP'), findsOneWidget);
    });

    testWidgets('topics that fail to load can be retried, and skipping works meanwhile', (tester) async {
      final server = FakeServer()..json('POST /api/me/onboarding', {'topics': []});
      await boot(tester, server: server);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byKey(const Key('onboarding-skip')), findsOneWidget);
      server.json('GET /api/onboarding/topics', {'topics': _topics, 'min': 3, 'max': 4});
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('topic-politics')), findsOneWidget);
    });
  });
}
