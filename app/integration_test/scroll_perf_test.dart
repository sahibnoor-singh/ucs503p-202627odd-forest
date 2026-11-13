// Scrolls the real app (Home feed, then the Discover feed page) against the real backend and records frame times.
// See test_driver/perf_driver.dart for how to run it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';

import 'package:forest_app/main.dart' as app;

Future<void> settleFor(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds * 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('scroll Home, then swipe through Discover', (tester) async {
    app.main();
    await settleFor(tester, 5);
    // Profile and release builds have no DEV_USER shortcut: sign in as the seeded dev account.
    if (find.text('Log in').evaluate().isNotEmpty) {
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'dev');
      await tester.enterText(fields.at(1), 'dev_123');
      FocusManager.instance.primaryFocus?.unfocus(); // the on-screen keyboard would cover the button
      await settleFor(tester, 1);
      await tester.tap(find.text('Log in'), warnIfMissed: false);
    }
    await settleFor(tester, 12); // load the feed, start the first video

    debugPrint('ON SCREEN: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().take(14).toList()}');
    // the measurement is only worth anything if real posts and a playing video are on screen
    expect(find.text('BOT'), findsWidgets, reason: 'Home did not load posts (is the backend running?)');
    expect(find.byType(VideoPlayer), findsWidgets, reason: 'no video is on screen');

    final home = find.byType(Scrollable).first;
    await binding.traceAction(() async {
      for (var i = 0; i < 8; i++) {
        await tester.fling(home, const Offset(0, -700), 1800);
        await settleFor(tester, 2);
      }
    }, reportKey: 'home_scroll');

    // the second tab of the bottom bar: the Discover grid
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.tapAt(Offset(size.width * 0.375, size.height * 0.935));
    await settleFor(tester, 8);
    expect(find.text('Search posts and people'), findsOneWidget, reason: 'Discover did not show the grid');
    final grid = find.byType(CustomScrollView).first;
    await binding.traceAction(() async {
      for (var i = 0; i < 6; i++) {
        await tester.fling(grid, const Offset(0, -900), 2200);
        await settleFor(tester, 2);
      }
      for (var i = 0; i < 6; i++) {
        await tester.fling(grid, const Offset(0, 900), 2200);
        await settleFor(tester, 2);
      }
    }, reportKey: 'discover_grid');

    // open the first tile: the full-screen feed, and swipe through it
    await tester.tapAt(Offset(size.width * 0.3, size.height * 0.6));
    await settleFor(tester, 8);
    expect(find.byType(VideoPlayer), findsWidgets, reason: 'opening a tile showed no video');
    await binding.traceAction(() async {
      for (var i = 0; i < 6; i++) {
        await tester.flingFrom(Offset(size.width / 2, size.height * 0.6), const Offset(0, -600), 1500);
        await settleFor(tester, 3);
      }
    }, reportKey: 'discover_swipes');
  });
}
