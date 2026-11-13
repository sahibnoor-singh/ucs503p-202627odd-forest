// Small phones and big system text: the first-run pages must still fit and stay usable (no overflow stripes, buttons reachable).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:forest_app/data/fake_feed_repository.dart';
import 'package:forest_app/data/feed_repository.dart';
import 'package:forest_app/features/auth/auth_gate.dart';
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
  {'id': 'startups', 'label': 'Startups and business'},
  {'id': 'farming', 'label': 'Farming and villages'},
];
const _asha = User(id: 'u-asha', username: 'asha', fullName: 'Asha', avatarUrl: null, isBot: false);

void main() {
  for (final (label, size, scale) in [
    ('a small phone', Size(320, 568), 1.0),
    ('a normal phone with the biggest system text', Size(360, 740), 2.0),
  ]) {
    testWidgets('first-run pages on $label: nothing overflows and every step can be finished', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final server = FakeServer()
        ..json('GET /api/onboarding/topics', {'topics': _topics, 'min': 3, 'max': 8})
        ..json('POST /api/me/onboarding', {'topics': []});
      final session = Session.signedIn(user: _asha, needsOnboarding: true);
      final api = server.client(token: () => session.token);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<Session>.value(value: session),
          Provider<ApiClient>.value(value: api),
          Provider<OnboardingRepository>.value(value: OnboardingRepository(api)),
          Provider<FeedRepository>.value(value: FakeFeedRepository.sample()),
        ],
        child: MaterialApp(
          theme: ForestTheme.light,
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
          home: const AuthGate(app: Scaffold(body: Center(child: Text('THE APP')))),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'topics page');

      for (final id in ['politics', 'economy', 'jobs']) {
        await tester.ensureVisible(find.byKey(Key('topic-$id')));
        await tester.tap(find.byKey(Key('topic-$id')));
        await tester.pump();
      }
      await tester.ensureVisible(find.byKey(const Key('onboarding-continue')));
      await tester.tap(find.byKey(const Key('onboarding-continue')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'people page');

      await tester.ensureVisible(find.byKey(const Key('onboarding-done')));
      await tester.tap(find.byKey(const Key('onboarding-done')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        expect(find.byKey(Key('onboarding-guide-$i')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'guide page ${i + 1}');
        // the button must be on screen without scrolling
        final box = tester.getRect(find.byKey(const Key('guide-next')));
        expect(box.bottom, lessThanOrEqualTo(size.height), reason: 'Next/Start is cut off on guide page ${i + 1}');
        await tester.tap(find.byKey(const Key('guide-next')));
        await tester.pumpAndSettle();
      }
      expect(find.text('THE APP'), findsOneWidget);
    });
  }
}
