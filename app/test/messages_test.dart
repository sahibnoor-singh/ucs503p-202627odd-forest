// Direct messages in the app: the plane on Home, the inbox (unread marks, people to follow when it is empty), and a conversation (the
// videos that were sent, emoji reactions, polling). There is no text.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:forest_app/data/fake_feed_repository.dart';
import 'package:forest_app/features/messages/chat_screen.dart';
import 'package:forest_app/features/messages/messages_repository.dart';
import 'package:forest_app/features/messages/messages_screen.dart';
import 'package:forest_app/features/messages/unread_controller.dart';
import 'package:forest_app/features/reels/reels_feed.dart';
import 'package:forest_app/features/reels/reels_repository.dart';
import 'package:forest_app/models/user.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

http.Response _reply(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> _user(String name, {bool bot = false}) =>
    {'id': 'id-$name', 'username': name, 'fullName': 'Full $name', 'avatarUrl': null, 'isBot': bot};

User _person(String name) => User.fromJson(_user(name));

Map<String, dynamic> _video(String id, {String? title}) => {
      'id': id, 'title': title ?? 'Title $id', 'caption': title ?? 'Title $id', 'filename': '$id.mp4', 'coverUrl': null, 'status': 'ready',
      'role': 'PARENT', 'parentVideoId': null, 'stance': 'PARENT', 'credibility': 50, 'durationS': 0, 'userId': 'aman', 'userName': 'aman',
      'isBot': false, 'createdAt': '2026-10-10T10:00:00.000Z', 'likeCount': 0, 'replyCount': 0, 'forCount': 0, 'againstCount': 0,
      'viewerSide': null, 'liked': false, 'transcript': null,
    };

Map<String, dynamic> _conv(String name, {int unread = 0, String preview = 'Sent you a video', bool fromMe = false}) => {
      'id': 'c-$name', 'with': _user(name), 'unread': unread,
      'last': {'kind': 'VIDEO', 'fromMe': fromMe, 'preview': preview, 'createdAt': DateTime.now().toUtc().toIso8601String()},
    };

Map<String, dynamic> _msg(String id, {Map<String, dynamic>? video, bool fromMe = false, bool gone = false, String? mine, String? theirs, String? at}) => {
      'id': id, 'fromMe': fromMe, 'video': gone ? null : (video ?? _video('v-$id')),
      'createdAt': at ?? DateTime.now().toUtc().toIso8601String(), 'reactions': {'mine': mine, 'theirs': theirs},
    };

Map<String, dynamic> _thread(List<Map<String, dynamic>> messages, {String who = 'riya', bool hasMore = false}) =>
    {'with': _user(who), 'messages': messages, 'hasMore': hasMore};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('repository', () {
    test('reads the inbox and a thread, reacts and un-reacts, and has no way to send text', () async {
      final server = FakeServer()
        ..json('GET /api/messages/conversations', {'conversations': [_conv('riya', unread: 2), {'id': 'broken'}], 'unreadTotal': 1})
        ..json('GET /api/messages/with/id-riya', _thread([_msg('m1'), _msg('m2', mine: '🔥', theirs: '😂')]))
        ..on('PUT /api/messages/m1/reaction', (s) => _reply({'reactions': {'mine': s.json['emoji'], 'theirs': null}}))
        ..json('DELETE /api/messages/m1/reaction', {'reactions': {'mine': null, 'theirs': null}})
        ..json('GET /api/messages/unread', {'unread': 3});
      final repo = MessagesRepository(server.client());

      final inbox = await repo.conversations();
      expect(inbox.map((c) => c.person.username), ['riya'], reason: 'the unreadable row is skipped');
      expect(inbox.single.unread, 2);
      expect(inbox.single.read().unread, 0);

      final page = await repo.thread('id-riya');
      expect(page.messages.map((m) => m.video!.id), ['v-m1', 'v-m2']);
      expect(page.messages[1].reactions.mine, '🔥');
      expect(page.messages[1].reactions.theirs, '😂');
      expect(server.last('GET /api/messages/with/id-riya').uri.queryParameters, {'limit': '40'});
      await repo.thread('id-riya', before: 'm1');
      expect(server.last('GET /api/messages/with/id-riya').uri.queryParameters['before'], 'm1');

      expect((await repo.react('m1', '❤️')).mine, '❤️');
      expect((await repo.unreact('m1')).isEmpty, isTrue);
      expect(await repo.unread(), 3);
    });

    test('a video that is no longer available arrives without a video; markRead and markOpened never throw', () async {
      final server = FakeServer()..json('GET /api/messages/with/id-riya', _thread([_msg('m1', gone: true)]));
      final repo = MessagesRepository(server.client());
      expect((await repo.thread('id-riya')).messages.single.video, isNull);
      await repo.markRead('id-riya'); // 404: swallowed
      await repo.markOpened('m1');
    });
  });

  group('the unread number', () {
    test('asks now and then, keeps the old number when asking fails, and can be set by the inbox', () async {
      var n = 2;
      var fail = false;
      final server = FakeServer()..on('GET /api/messages/unread', (_) => fail ? _reply({'error': 'x'}, status: 500) : _reply({'unread': n}));
      final c = UnreadController(MessagesRepository(server.client()), every: const Duration(milliseconds: 30));
      c.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.count, 2);
      n = 5;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(c.count, 5, reason: 'polling picked up the change');
      fail = true;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(c.count, 5);
      c.set(1);
      expect(c.count, 1);
      c.stop();
      final asked = server.count('GET /api/messages/unread');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(server.count('GET /api/messages/unread'), asked, reason: 'stopped means stopped');
      c.dispose();
    });
  });

  group('Home', () {
    testWidgets('has the paper-plane at the top right with the number of conversations that have something new', (tester) async {
      useTallScreen(tester);
      final server = FakeServer()..json('GET /api/messages/unread', {'unread': 3});
      await pumpHome(tester, sampleRepo(), messagesRepository: MessagesRepository(server.client()));
      expect(find.byKey(const Key('open-messages')), findsOneWidget);
      expect(find.byKey(const Key('messages-badge')), findsOneWidget);
      expect(find.text('3'), findsWidgets);
      final plane = tester.getTopRight(find.byKey(const Key('open-messages')));
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(plane.dx, greaterThan(screen.width - 60), reason: 'the right-hand corner');
      expect(plane.dy, lessThan(80), reason: 'at the top');
    });

    testWidgets('no badge when nothing is new', (tester) async {
      useTallScreen(tester);
      await pumpHome(tester, sampleRepo(), messagesRepository: MessagesRepository((FakeServer()..json('GET /api/messages/unread', {'unread': 0})).client()));
      expect(find.byKey(const Key('messages-badge')), findsNothing);
    });

    testWidgets('"9+" for a lot', (tester) async {
      useTallScreen(tester);
      await pumpHome(tester, sampleRepo(), messagesRepository: MessagesRepository((FakeServer()..json('GET /api/messages/unread', {'unread': 14})).client()));
      expect(find.text('9+'), findsOneWidget);
    });

    testWidgets('tapping it brings the messages page in from the right', (tester) async {
      useTallScreen(tester);
      final server = FakeServer()
        ..json('GET /api/messages/unread', {'unread': 0})
        ..json('GET /api/messages/conversations', {'conversations': [_conv('riya')], 'unreadTotal': 0});
      await pumpHome(tester, sampleRepo(), messagesRepository: MessagesRepository(server.client()));
      await tester.tap(find.byKey(const Key('open-messages')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final mid = tester.getTopLeft(find.byType(MessagesScreen));
      expect(mid.dx, greaterThan(50), reason: 'part way across, coming from the right');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getTopLeft(find.byType(MessagesScreen)).dx, 0);
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('riya'), findsOneWidget);
    });
  });

  group('the inbox', () {
    late FakeServer server;

    Future<void> pump(WidgetTester tester, {List<Map<String, dynamic>>? conversations, Size size = const Size(400, 800), VoidCallback? onDiscover}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      server = FakeServer()
        ..json('GET /api/messages/conversations', {'conversations': conversations ?? [], 'unreadTotal': (conversations ?? []).where((c) => (c['unread'] as int) > 0).length})
        ..json('GET /api/messages/with/id-riya', _thread([_msg('m1')]))
        ..json('GET /api/messages/unread', {'unread': 0});
      final messages = MessagesRepository(server.client());
      await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<MessagesRepository>.value(value: messages),
          ChangeNotifierProvider<UnreadController>(create: (_) => UnreadController(messages)),
          Provider<ReelsRepository>.value(value: ReelsRepository(server.client())),
        ],
        child: MaterialApp(home: MessagesScreen(repository: messages, feed: FakeFeedRepository.sample(now: DateTime.utc(2026, 10, 10)), onDiscover: onDiscover, pollEvery: const Duration(milliseconds: 200))),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
    }

    testWidgets('conversations newest first, the ones with something new marked and bold, the rest plain', (tester) async {
      await pump(tester, conversations: [_conv('riya', unread: 2, preview: 'Reacted 🔥 to your video'), _conv('zed', preview: 'You sent a video', fromMe: true)]);
      expect(find.byKey(const ValueKey('unread-c-riya')), findsOneWidget);
      expect(find.byKey(const ValueKey('unread-c-zed')), findsNothing);
      expect(tester.widget<Text>(find.textContaining('Reacted 🔥')).style!.fontWeight, FontWeight.w700);
      expect(tester.widget<Text>(find.textContaining('You sent a video')).style!.fontWeight, FontWeight.w400);
      expect(tester.getTopLeft(find.text('riya')).dy, lessThan(tester.getTopLeft(find.text('zed')).dy));
    });

    testWidgets('there is no way to start a conversation by hand: no new-message button', (tester) async {
      await pump(tester, conversations: [_conv('riya')]);
      expect(find.byKey(const Key('new-message')), findsNothing);
      expect(find.byTooltip('New message'), findsNothing);
    });

    testWidgets('opening a conversation shows its videos; coming back refreshes the inbox', (tester) async {
      await pump(tester, conversations: [_conv('riya', unread: 1)]);
      final before = server.count('GET /api/messages/conversations');
      await tester.tap(find.text('riya'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('video-card')), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ChatScreen), findsNothing);
      expect(server.count('GET /api/messages/conversations'), greaterThan(before));
    });

    testWidgets('with no conversations it explains itself and suggests people to follow', (tester) async {
      var wentToDiscover = false;
      await pump(tester, onDiscover: () => wentToDiscover = true);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('No messages yet'), findsOneWidget);
      expect(find.textContaining('paper-plane'), findsOneWidget);
      expect(find.text('People to follow'), findsOneWidget);
      expect(find.text('Follow'), findsWidgets);
      await tester.tap(find.byKey(const Key('go-discover')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(wentToDiscover, isTrue);
    });

    testWidgets('a server that cannot be reached shows why, with Try again', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var up = false;
      final s = FakeServer()
        ..on('GET /api/messages/conversations', (_) => up ? _reply({'conversations': [_conv('riya')], 'unreadTotal': 0}) : _reply({'error': 'Messages are down'}, status: 503));
      final repo = MessagesRepository(s.client());
      await tester.pumpWidget(MultiProvider(
        providers: [Provider<MessagesRepository>.value(value: repo), ChangeNotifierProvider<UnreadController>(create: (_) => UnreadController(repo))],
        child: MaterialApp(home: MessagesScreen(repository: repo, pollEvery: const Duration(minutes: 5))),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Messages are down'), findsOneWidget);
      up = true;
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('riya'), findsOneWidget);
    });

    testWidgets('something new arriving while the page is open shows up on its own', (tester) async {
      await pump(tester, conversations: [_conv('riya')]);
      expect(find.text('zed'), findsNothing);
      server.json('GET /api/messages/conversations', {'conversations': [_conv('zed', unread: 1), _conv('riya')], 'unreadTotal': 1});
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('zed'), findsOneWidget);
      expect(find.byKey(const ValueKey('unread-c-zed')), findsOneWidget);
    });

    testWidgets('fits a very narrow phone', (tester) async {
      await pump(tester, conversations: [_conv('riya', unread: 1, preview: 'Reacted 🔥 to your video and then some more words that will not fit on one line')], size: const Size(320, 640));
      expect(tester.takeException(), isNull);
    });
  });

  group('a conversation', () {
    late FakeServer server;
    String? reactionOfThem;

    Future<void> pump(WidgetTester tester, {List<Map<String, dynamic>>? messages, Size size = const Size(400, 800), Duration poll = const Duration(milliseconds: 200), bool hasMore = false, List<Map<String, dynamic>>? older}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      reactionOfThem = null;
      server = FakeServer()
        ..on('GET /api/messages/with/id-riya', (s) => _reply(older != null && s.uri.queryParameters.containsKey('before') ? _thread(older) : _thread(messages ?? [], hasMore: hasMore)))
        ..json('POST /api/messages/with/id-riya/read', {'ok': true})
        ..json('GET /api/messages/unread', {'unread': 0})
        ..on('PUT /api/messages/m1/reaction', (s) => _reply({'reactions': {'mine': s.json['emoji'], 'theirs': reactionOfThem}}))
        ..on('DELETE /api/messages/m1/reaction', (_) => _reply({'reactions': {'mine': null, 'theirs': reactionOfThem}}))
        ..json('POST /api/messages/mv/open', {'ok': true})
        ..json('GET /api/videos/v1/tree', [_video('v1')]);
      final repo = MessagesRepository(server.client());
      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider<UnreadController>(create: (_) => UnreadController(repo))],
        child: MaterialApp(home: ChatScreen(person: _person('riya'), repository: repo, reels: ReelsRepository(server.client()), pollEvery: poll)),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
    }

    testWidgets('has nothing to type into: no text box, no send button', (tester) async {
      await pump(tester, messages: [_msg('m1')]);
      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip('Send'), findsNothing);
    });

    testWidgets('shows the videos you were sent on the left and the ones you sent on the right, and marks the conversation read', (tester) async {
      await pump(tester, messages: [_msg('m1'), _msg('m2', fromMe: true)]);
      final width = tester.view.physicalSize.width;
      Finder card(String id) => find.descendant(of: find.byKey(ValueKey('msg-$id')), matching: find.byKey(const ValueKey('video-card')));
      expect(tester.getCenter(card('m1')).dx, lessThan(width / 2), reason: 'sent to me: on the left');
      expect(tester.getCenter(card('m2')).dx, greaterThan(width / 2), reason: 'sent by me: on the right');
      expect(server.count('POST /api/messages/with/id-riya/read'), 1);
    });

    testWidgets('a video shows as a card with its title and who posted it; tapping it opens it and tells the server', (tester) async {
      await pump(tester, messages: [_msg('mv', video: _video('v1', title: 'Phones in class'))]);
      expect(find.text('Phones in class'), findsOneWidget);
      expect(find.text('@aman'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('video-card')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(server.count('POST /api/messages/mv/open'), 1);
      final feed = tester.widget<ReelsFeed>(find.byType(ReelsFeed));
      expect(feed.initialDebateRoots!.single.id, 'v1');
    });

    testWidgets('a video that I sent opens without telling the server it was "opened"', (tester) async {
      await pump(tester, messages: [_msg('mv', video: _video('v1'), fromMe: true)]);
      await tester.tap(find.byKey(const ValueKey('video-card')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(server.count('POST /api/messages/mv/open'), 0);
    });

    testWidgets('a video that is gone says so instead of breaking the conversation', (tester) async {
      await pump(tester, messages: [_msg('mv', gone: true), _msg('m2')]);
      expect(find.textContaining('not available any more'), findsOneWidget);
      expect(find.byKey(const ValueKey('video-card')), findsOneWidget, reason: 'the other video is still there');
    });

    testWidgets('the smiley under a video opens the six emojis; a choice is told to the server and shown; it can be removed', (tester) async {
      await pump(tester, messages: [_msg('m1')], poll: const Duration(minutes: 5));
      expect(find.byKey(const ValueKey('reactions')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('add-reaction')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      for (final e in messageReactions) {
        expect(find.byKey(ValueKey('react-$e')), findsOneWidget);
      }
      expect(find.byKey(const Key('remove-reaction')), findsNothing, reason: 'nothing of mine to remove yet');
      await tester.tap(find.byKey(const ValueKey('react-🔥')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(server.last('PUT /api/messages/m1/reaction').json, {'emoji': '🔥'});
      expect(find.text('🔥'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('add-reaction')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('remove-reaction')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(server.count('DELETE /api/messages/m1/reaction'), 1);
      expect(find.byKey(const ValueKey('reactions')), findsNothing);
    });

    testWidgets('press and hold on the video opens the same emoji bar, and the other person\'s reaction shows beside mine', (tester) async {
      await pump(tester, messages: [_msg('m1', theirs: '😂')], poll: const Duration(minutes: 5));
      reactionOfThem = '😂';
      expect(find.text('😂'), findsOneWidget);
      await tester.longPress(find.byKey(const ValueKey('video-card')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('react-😮')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(server.last('PUT /api/messages/m1/reaction').json, {'emoji': '😮'});
      expect(find.text('😮 😂'), findsOneWidget, reason: 'mine and theirs');
    });

    testWidgets('a reaction the server refuses is taken back', (tester) async {
      await pump(tester, messages: [_msg('m1')], poll: const Duration(minutes: 5));
      server.on('PUT /api/messages/m1/reaction', (_) => _reply({'error': 'That reaction is not available'}, status: 400));
      await tester.tap(find.byKey(const ValueKey('add-reaction')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('react-👍')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('reactions')), findsNothing);
      expect(find.text('That reaction is not available'), findsOneWidget);
    });

    testWidgets('new videos from the other person appear on their own and are marked read', (tester) async {
      await pump(tester, messages: [_msg('m1')]);
      final reads = server.count('POST /api/messages/with/id-riya/read');
      server.json('GET /api/messages/with/id-riya', _thread([_msg('m1'), _msg('m2')]));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byKey(const ValueKey('video-card')), findsNWidgets(2));
      expect(server.count('POST /api/messages/with/id-riya/read'), greaterThan(reads));
    });

    testWidgets('an empty conversation says how to send one; a conversation that cannot load can be retried', (tester) async {
      await pump(tester);
      expect(find.textContaining('No videos yet'), findsOneWidget);

      tester.view.physicalSize = const Size(400, 800);
      var up = false;
      final s = FakeServer()..on('GET /api/messages/with/id-riya', (_) => up ? _reply(_thread([_msg('m1')])) : _reply({'error': 'Chat is down'}, status: 503))..json('POST /api/messages/with/id-riya/read', {'ok': true});
      final repo = MessagesRepository(s.client());
      await tester.pumpWidget(MaterialApp(home: ChatScreen(person: _person('riya'), repository: repo, pollEvery: const Duration(minutes: 5))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Chat is down'), findsOneWidget);
      up = true;
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byKey(const ValueKey('video-card')), findsOneWidget);
    });

    testWidgets('older videos load when you scroll up, without repeating', (tester) async {
      final base = DateTime.utc(2026, 10, 10, 10);
      final latest = [for (var i = 20; i < 40; i++) _msg('m$i', video: _video('v$i', title: 'video $i'), at: base.add(Duration(hours: i)).toIso8601String())];
      final older = [for (var i = 0; i < 20; i++) _msg('m$i', video: _video('v$i', title: 'video $i'), at: base.add(Duration(hours: i)).toIso8601String())];
      await pump(tester, messages: latest, hasMore: true, older: older, poll: const Duration(minutes: 5));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 3; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, 4000));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 100));
      expect(server.last('GET /api/messages/with/id-riya').uri.queryParameters['before'], 'm20');
    });

    testWidgets('fits a very narrow phone with a reaction on each side', (tester) async {
      await pump(tester, messages: [_msg('m1', theirs: '😂'), _msg('m2', fromMe: true, mine: '🔥', theirs: '❤️')], size: const Size(320, 640));
      expect(tester.takeException(), isNull);
    });

    testWidgets('choosing a reaction does not leave a keyboard or any focus behind', (tester) async {
      await pump(tester, messages: [_msg('m1')], poll: const Duration(minutes: 5));
      await tester.tap(find.byKey(const ValueKey('add-reaction')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('react-🔥')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(EditableText), findsNothing);
    });
  });
}
