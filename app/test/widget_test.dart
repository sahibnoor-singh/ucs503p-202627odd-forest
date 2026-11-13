// Smoke tests for the app shell: signed-out people get the login screen, signed-in
// people get 4 screens behind one swipe-navigated PageView (see lib/main.dart).
// No real network: the API client is given a canned answer.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:forest_app/data/fake_feed_repository.dart';
import 'package:forest_app/main.dart';
import 'package:forest_app/services/api_client.dart';
import 'package:forest_app/services/session.dart';
import 'package:forest_app/ui/forest_nav_bar.dart';

ApiClient _offlineApi(Session session) => ApiClient(
      baseUrl: 'http://test.invalid',
      devUser: '',
      client: MockClient((_) async => http.Response('{"error":"offline"}', 503)),
      tokenProvider: () => session.token,
    );

void main() {
  testWidgets('signed in: root shell renders all 4 nav destinations', (tester) async {
    final session = Session.signedIn();
    await tester.pumpWidget(ForestApp(
      repository: FakeFeedRepository.sample(),
      session: session,
      apiClient: _offlineApi(session),
    ));
    await tester.pump();

    final navBar = find.byType(ForestNavBar);
    expect(navBar, findsOneWidget);
    for (final label in ['Home', 'Discover', 'Upload', 'Account']) {
      expect(find.descendant(of: navBar, matching: find.text(label)), findsOneWidget);
    }
    expect(find.byKey(const Key('login-identifier')), findsNothing);
  });

  testWidgets('signed out: the login screen is shown instead of the app', (tester) async {
    final session = Session(store: MemoryTokenStore());
    await session.restore();
    await tester.pumpWidget(ForestApp(
      repository: FakeFeedRepository.sample(),
      session: session,
      apiClient: _offlineApi(session),
    ));
    await tester.pump();

    expect(find.byKey(const Key('login-identifier')), findsOneWidget);
    expect(find.byType(ForestNavBar), findsNothing);
  });
}
