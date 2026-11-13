// "@riya followed you from this reel": the list, the bell on Home, and what opening them does.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:forest_app/features/notifications/notifications_controller.dart';
import 'package:forest_app/features/notifications/notifications_repository.dart';
import 'package:forest_app/features/notifications/notifications_screen.dart';
import 'package:forest_app/theme/forest_theme.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

Map<String, dynamic> _n(String id, {bool read = false, bool withPost = true}) => {
      'id': id,
      'kind': 'follow',
      'text': withPost ? '@riya followed you from this reel' : '@riya followed you',
      'createdAt': '2026-10-10T12:00:00.000Z',
      'read': read,
      'actor': {'id': 'u-riya', 'username': 'riya', 'fullName': 'Riya K', 'avatarUrl': null, 'isBot': false},
      'post': withPost ? {'id': 'p1', 'title': 'Ban phones', 'coverUrl': '/uploads/c.jpg'} : null,
    };

FakeServer _server({int unread = 1, List<Map<String, dynamic>>? items}) => FakeServer()
  ..json('GET /api/notifications', {'unread': unread, 'notifications': items ?? [_n('n1')]})
  ..json('POST /api/notifications/read', {'unread': 0});

void main() {
  test('the repository reads the list, the unread count and the reel a follow came from', () async {
    final r = await NotificationsRepository(_server().client()).load();
    expect(r.unread, 1);
    expect(r.items.single.text, '@riya followed you from this reel');
    expect(r.items.single.actor.username, 'riya');
    expect(r.items.single.postId, 'p1');
    expect(r.items.single.coverUrl, '/uploads/c.jpg');
    final plain = await NotificationsRepository(_server(items: [_n('n2', withPost: false)]).client()).load();
    expect(plain.items.single.postId, isNull);
  });

  test('opening the list shows it, then marks everything read once', () async {
    final s = _server(unread: 2);
    final c = NotificationsController(NotificationsRepository(s.client()), every: const Duration(hours: 1));
    addTearDown(c.dispose);
    await c.open();
    expect(c.items.length, 1);
    expect(c.unread, 0);
    expect(s.last('POST /api/notifications/read'), isNotNull);
    final again = _server(unread: 0);
    final c2 = NotificationsController(NotificationsRepository(again.client()), every: const Duration(hours: 1));
    addTearDown(c2.dispose);
    await c2.open();
    expect(() => again.last('POST /api/notifications/read'), throwsA(anything), reason: 'nothing unread, nothing to mark');
  });

  test('a failed load keeps the old numbers and says so on open', () async {
    final c = NotificationsController(NotificationsRepository(FakeServer().client()), every: const Duration(hours: 1));
    addTearDown(c.dispose);
    await c.refreshCount();
    expect(c.unread, 0);
    await c.open();
    expect(c.error, isNotNull);
  });

  testWidgets('the screen shows each line with the picture of the reel on the right and a dot while it is new', (tester) async {
    final s = _server();
    final c = NotificationsController(NotificationsRepository(s.client()), every: const Duration(hours: 1));
    addTearDown(c.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<NotificationsController>.value(
      value: c,
      child: MaterialApp(theme: ForestTheme.light, home: const NotificationsScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('@riya followed you from this reel'), findsOneWidget);
    expect(find.byKey(const Key('notification-cover')), findsOneWidget);
    expect(find.byKey(const Key('unread-dot')), findsOneWidget);
    expect(c.unread, 0, reason: 'opening marks them read');
  });

  testWidgets('an empty list says so; a failing one offers Try again', (tester) async {
    final empty = NotificationsController(NotificationsRepository(_server(unread: 0, items: []).client()), every: const Duration(hours: 1));
    addTearDown(empty.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<NotificationsController>.value(value: empty, child: MaterialApp(theme: ForestTheme.light, home: const NotificationsScreen())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Nothing yet'), findsOneWidget);

    final broken = NotificationsController(NotificationsRepository(FakeServer().client()), every: const Duration(hours: 1));
    addTearDown(broken.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<NotificationsController>.value(key: UniqueKey(), value: broken, child: MaterialApp(theme: ForestTheme.light, home: const NotificationsScreen())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('Home has a bell with the number of new notifications, and it opens the list', (tester) async {
    useTallScreen(tester);
    final s = _server(unread: 3);
    final c = NotificationsController(NotificationsRepository(s.client()), every: const Duration(hours: 1));
    addTearDown(c.dispose);
    await pumpHome(tester, sampleRepo(), notifications: c);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('open-notifications')), findsOneWidget);
    expect(find.byKey(const Key('notifications-badge')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('notifications-badge')), matching: find.text('3')), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-notifications')));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('@riya followed you from this reel'), findsOneWidget);
  });
}
