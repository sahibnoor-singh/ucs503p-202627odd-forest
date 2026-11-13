import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:forest_app/data/fake_feed_repository.dart';
import 'package:forest_app/data/feed_repository.dart';
import 'package:forest_app/features/messages/messages_repository.dart';
import 'package:forest_app/features/messages/unread_controller.dart';
import 'package:forest_app/features/notifications/notifications_controller.dart';
import 'package:forest_app/features/safety/safety_repository.dart';
import 'package:forest_app/features/share/share_repository.dart';
import 'package:forest_app/features/home/feed_controller.dart';
import 'package:forest_app/features/rooms/rooms_repository.dart';
import 'package:forest_app/features/today/today_controller.dart';
import 'package:forest_app/services/analytics.dart';
import 'package:forest_app/screens/home_feed_screen.dart';
import 'package:forest_app/services/video_cache.dart';
import 'package:forest_app/services/video_pool.dart';
import 'package:forest_app/theme/forest_theme.dart';

import 'fake_server.dart';

/// A cache that never touches disk or network (tests have neither).
class NoVideoCache extends VideoCache {
  NoVideoCache() : super(directory: Directory.systemTemp);

  @override
  Future<void> reset() async {}

  @override
  File? cachedFile(String url) => null;

  @override
  Future<File?> prefetch(String url) async => null;
}

/// Phone-sized, very tall, so the lazy feed list builds every card.
void useTallScreen(WidgetTester tester, {double logicalHeight = 6000}) {
  tester.view.physicalSize = Size(432 * 2.5, logicalHeight * 2.5);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
}

/// Home tab on [repo], wrapped the way main.dart wraps the app.
Future<FeedController> pumpHome(
  WidgetTester tester,
  FeedRepository repo, {
  ThemeData? theme,
  Duration pollInterval = const Duration(milliseconds: 50),
  DateTime Function()? clock,
  int pageSize = 20,
  ShareRepository? shareRepository,
  MessagesRepository? messagesRepository,
  TodayController? today,
  Analytics? analytics,
  RoomsRepository? rooms,
  NotificationsController? notifications,
}) async {
  final messages = messagesRepository ?? MessagesRepository(FakeServer().client());
  late FeedController controller;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<FeedRepository>.value(value: repo),
        Provider<ShareRepository>.value(value: shareRepository ?? ShareRepository(FakeServer().client())),
        Provider<MessagesRepository>.value(value: messages),
        Provider<SafetyRepository>.value(value: SafetyRepository(FakeServer().client())),
        if (today != null) ChangeNotifierProvider<TodayController>.value(value: today),
        if (analytics != null) Provider<Analytics>.value(value: analytics),
        if (rooms != null) Provider<RoomsRepository>.value(value: rooms),
        if (notifications != null) ChangeNotifierProvider<NotificationsController>.value(value: notifications),
        ChangeNotifierProvider<BlocklistController>(create: (_) => BlocklistController()),
        ChangeNotifierProvider<UnreadController>(create: (_) => UnreadController(messages)),
        Provider<VideoPool>(
          create: (_) => VideoPool(NoVideoCache()),
          dispose: (_, pool) => pool.dispose(),
        ),
        ChangeNotifierProvider<FeedController>(
          create: (_) => controller = FeedController(repo, pollInterval: pollInterval, clock: clock, pageSize: pageSize),
        ),
      ],
      child: MaterialApp(
        theme: theme ?? ForestTheme.dark,
        home: DefaultTabNavigator(goTo: (_) {}, child: const HomeFeedScreen()),
      ),
    ),
  );
  await settle(tester);
  return controller;
}

/// Lets futures, post-frame callbacks and short animations finish without
/// waiting for endless ones (spinners).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

FakeFeedRepository sampleRepo({List<String>? homeOrder}) =>
    FakeFeedRepository.sample(now: DateTime.utc(2026, 10, 10, 12), homeOrder: homeOrder);
