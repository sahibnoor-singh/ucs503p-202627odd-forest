// Screens that open ON TOP of Home (the full-screen viewer, the thread sheet) are pushed onto the
// app's Navigator, which sits above anything placed inside MaterialApp's `home:`. So the feed's
// providers must sit above the MaterialApp. The Home tests build their own wrapper and cannot see
// this, so these tests go through the real ForestApp wiring (lib/main.dart).
//
// Regression: after the login refactor, tapping a video on a real phone showed a red
// "Could not find the correct Provider<FeedController> above this PostViewer" screen.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:forest_app/features/thread/thread_sheet.dart';
import 'package:forest_app/main.dart';
import 'package:forest_app/services/api_client.dart';
import 'package:forest_app/services/session.dart';
import 'package:forest_app/ui/forest_icon.dart';
import 'package:forest_app/ui/post_media.dart';

import 'support/harness.dart';

Future<void> _pumpRealApp(WidgetTester tester) async {
  useTallScreen(tester);
  final session = Session.signedIn();
  await tester.pumpWidget(ForestApp(
    repository: sampleRepo(),
    session: session,
    apiClient: ApiClient(
      baseUrl: 'http://test.invalid',
      devUser: '',
      client: MockClient((_) async => http.Response('{"error":"offline"}', 503)),
      tokenProvider: () => session.token,
    ),
  ));
  await settle(tester);
}

void main() {
  testWidgets('tapping a video opens the full-screen viewer without a provider error', (tester) async {
    await _pumpRealApp(tester);

    await tester.tap(find.byWidgetPredicate((w) => w is PostMedia && w.post.id == 'r1' && !w.fullscreen));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.byWidgetPredicate((w) => w is PostMedia && w.fullscreen), findsOneWidget);
  });

  testWidgets('the comment button opens the thread sheet without a provider error', (tester) async {
    await _pumpRealApp(tester);

    await tester.tap(find.byWidgetPredicate((w) => w is ForestIcon && w.name == Icn.comment).first);
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(ThreadSheet), findsOneWidget);
  });
}
