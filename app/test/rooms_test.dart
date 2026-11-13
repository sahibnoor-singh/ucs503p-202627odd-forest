import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:forest_app/data/fake_feed_repository.dart';
import 'package:forest_app/features/growth/growth_tiles.dart';
import 'package:forest_app/features/growth/invite_sheet.dart';
import 'package:forest_app/features/home/feed_controller.dart';
import 'package:forest_app/features/rooms/room_screen.dart';
import 'package:forest_app/features/rooms/rooms_repository.dart';
import 'package:forest_app/features/rooms/rooms_screen.dart';
import 'package:forest_app/services/analytics.dart';
import 'package:forest_app/services/api_client.dart';
import 'package:forest_app/theme/forest_theme.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';
import 'today_test.dart' show itemJson;

Map<String, dynamic> roomJson({
  String id = 'r1',
  String name = 'Debate society',
  String motion = 'This house believes attendance should not be compulsory.',
  String status = 'OPEN',
  String role = 'OWNER',
  String? code = 'ABC234',
  int members = 2,
  int posts = 3,
  int forCount = 2,
  int againstCount = 1,
  int undecided = 0,
  String? endsAt,
}) =>
    {
      'id': id,
      'name': name,
      'motion': motion,
      'description': null,
      'status': status,
      'role': role,
      'code': code,
      'startsAt': null,
      'endsAt': endsAt,
      'owner': {'id': 'u-owner', 'username': 'owner', 'fullName': 'Owner', 'avatarUrl': null, 'isBot': false},
      'memberCount': members,
      'posts': posts,
      'forCount': forCount,
      'againstCount': againstCount,
      'undecided': undecided,
      'createdAt': '2026-10-21T10:00:00.000Z',
    };

FakeServer roomServer({Map<String, dynamic>? room, List<Map<String, dynamic>> posts = const []}) {
  final r = room ?? roomJson();
  return FakeServer()
    ..json('GET /api/rooms/mine', {'rooms': [r]})
    ..json('GET /api/rooms/${r['id']}', {'room': r, 'members': [r['owner']]})
    ..json('GET /api/rooms/${r['id']}/posts', {'items': posts})
    ..json('POST /api/events', {'recorded': 1});
}

Future<void> pumpApp(WidgetTester tester, FakeServer s, Widget home) async {
  useTallScreen(tester);
  final api = s.client();
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      Provider<RoomsRepository>.value(value: RoomsRepository(api)),
      Provider<Analytics>.value(value: Analytics(api)),
      ChangeNotifierProvider<FeedController>(create: (_) => FeedController(FakeFeedRepository.sample())),
    ],
    child: MaterialApp(theme: ForestTheme.dark, home: home),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('repository', () {
    test('rooms are read with their standing, role and code', () async {
      final repo = RoomsRepository(roomServer(room: roomJson(endsAt: '2026-10-25T10:00:00.000Z')).client());
      final rooms = await repo.mine();
      final r = rooms.single;
      expect(r.name, 'Debate society');
      expect(r.status, RoomStatus.open);
      expect(r.isOwner, isTrue);
      expect(r.code, 'ABC234');
      expect(r.forCount, 2);
      expect(r.againstCount, 1);
      expect(r.endsAt!.toUtc(), DateTime.utc(2026, 10, 25, 10));
      expect(r.canPost, isTrue);
    });

    test('statuses: upcoming and closed cannot be posted into', () async {
      for (final (word, status, canPost) in [('UPCOMING', RoomStatus.upcoming, false), ('CLOSED', RoomStatus.closed, false), ('OPEN', RoomStatus.open, true)]) {
        final repo = RoomsRepository(roomServer(room: roomJson(status: word)).client());
        final r = (await repo.mine()).single;
        expect(r.status, status);
        expect(r.canPost, canPost);
      }
    });

    test('create sends only what was given, join sends the code, detail has members, leave and close call the server', () async {
      final s = roomServer()
        ..json('POST /api/rooms', {'room': roomJson(id: 'r2')}, status: 201)
        ..json('POST /api/rooms/join', {'room': roomJson(id: 'r3', role: 'MEMBER')})
        ..json('POST /api/rooms/r1/leave', {'left': true})
        ..json('POST /api/rooms/r1/close', {'room': roomJson(status: 'CLOSED')});
      final repo = RoomsRepository(s.client());
      final made = await repo.create(name: 'A', motion: 'This house believes things.', endsAt: DateTime.utc(2026, 10, 30, 12));
      expect(made.id, 'r2');
      expect(s.last('POST /api/rooms').json, {'name': 'A', 'motion': 'This house believes things.', 'endsAt': '2026-10-30T12:00:00.000Z'});
      await repo.create(name: 'B', motion: 'This house believes other things.', description: '  ');
      expect(s.last('POST /api/rooms').json.containsKey('description'), isFalse);
      expect((await repo.join('ABC234')).isOwner, isFalse);
      expect(s.last('POST /api/rooms/join').json, {'code': 'ABC234'});
      final d = await repo.detail('r1');
      expect(d.members.single.username, 'owner');
      await repo.leave('r1');
      expect((await repo.close('r1')).status, RoomStatus.closed);
    });
  });

  group('the rooms page', () {
    testWidgets('lists my rooms with their status, and opens one', (tester) async {
      final s = roomServer();
      await pumpApp(tester, s, const RoomsScreen());
      expect(find.text('Debate society'), findsOneWidget);
      expect(find.text('OPEN'), findsOneWidget);
      expect(find.textContaining('2 members · 3 opinions'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('room-r1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('room-motion-text')), findsOneWidget);
    });

    testWidgets('an empty list explains itself and offers both ways in', (tester) async {
      final s = roomServer()..json('GET /api/rooms/mine', {'rooms': []});
      await pumpApp(tester, s, const RoomsScreen());
      expect(find.text('You are not in any room yet.'), findsOneWidget);
      expect(find.byKey(const Key('rooms-create')), findsOneWidget);
      expect(find.byKey(const Key('rooms-join')), findsOneWidget);
    });

    testWidgets('joining with a code opens the room; a wrong code says why and stays on the list', (tester) async {
      final s = roomServer(room: roomJson(id: 'r9', role: 'MEMBER'))
        ..json('GET /api/rooms/mine', {'rooms': []})
        ..json('POST /api/rooms/join', {'error': 'No room has that code. Check it and try again', 'field': 'code'}, status: 404);
      await pumpApp(tester, s, const RoomsScreen());
      await tester.tap(find.byKey(const Key('rooms-join')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('join-code')), 'zzzzzz');
      await tester.tap(find.byKey(const Key('join-confirm')));
      await tester.pumpAndSettle();
      expect(s.last('POST /api/rooms/join').json, {'code': 'zzzzzz'});
      expect(find.text('No room has that code. Check it and try again'), findsOneWidget);
      expect(find.byKey(const Key('room-motion-text')), findsNothing);

      s.json('POST /api/rooms/join', {'room': roomJson(id: 'r9', role: 'MEMBER')});
      await tester.tap(find.byKey(const Key('rooms-join')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('join-code')), 'ABC234');
      await tester.tap(find.byKey(const Key('join-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('room-motion-text')), findsOneWidget);
    });

    testWidgets('starting a room sends the name, motion and an end three days away, then opens it', (tester) async {
      final s = roomServer()
        ..json('GET /api/rooms/mine', {'rooms': []})
        ..json('POST /api/rooms', {'room': roomJson()}, status: 201);
      await pumpApp(tester, s, const RoomsScreen());
      await tester.tap(find.byKey(const Key('rooms-create')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('room-name')), 'Debate society');
      await tester.enterText(find.byKey(const Key('room-motion')), 'This house believes attendance should not be compulsory.');
      await tester.tap(find.text('Create room'));
      await tester.pumpAndSettle();
      final body = s.last('POST /api/rooms').json;
      expect(body['name'], 'Debate society');
      expect(body['motion'], 'This house believes attendance should not be compulsory.');
      final ends = DateTime.parse(body['endsAt'] as String);
      expect(ends.difference(DateTime.now().toUtc()).inHours, inInclusiveRange(70, 72));
      expect(find.byKey(const Key('room-motion-text')), findsOneWidget, reason: 'the new room opens');
    });

    testWidgets('the server\'s reason appears under the field it is about, and No end sends no end', (tester) async {
      final s = roomServer()
        ..json('GET /api/rooms/mine', {'rooms': []})
        ..json('POST /api/rooms', {'error': 'Write the motion as one statement (10 to 200 characters)', 'field': 'motion'}, status: 400);
      await pumpApp(tester, s, const RoomsScreen());
      await tester.tap(find.byKey(const Key('rooms-create')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('room-name')), 'X');
      await tester.enterText(find.byKey(const Key('room-motion')), 'short');
      await tester.tap(find.byKey(const Key('room-days-none')));
      await tester.pump();
      await tester.tap(find.text('Create room'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Write the motion as one statement'), findsOneWidget);
      expect(s.last('POST /api/rooms').json.containsKey('endsAt'), isFalse);
      expect(find.text('Start a room'), findsOneWidget, reason: 'still on the form');
    });
  });

  group('one room', () {
    testWidgets('shows the motion, the code, where the room stands, and the button to argue', (tester) async {
      final s = roomServer(room: roomJson(forCount: 3, againstCount: 1, undecided: 2), posts: [itemJson('rp1', 'asha', title: 'My case')]);
      await pumpApp(tester, s, const RoomScreen(roomId: 'r1'));
      expect(find.text('This house believes attendance should not be compulsory.'), findsOneWidget);
      expect(find.byKey(const Key('room-code')), findsOneWidget);
      expect(find.text('ABC234'), findsOneWidget);
      expect(find.text('3 FOR'), findsOneWidget);
      expect(find.text('1 AGAINST'), findsOneWidget);
      expect(find.text('2 undecided'), findsOneWidget);
      expect(find.byKey(const Key('room-post')), findsOneWidget);
      expect(find.byKey(const ValueKey('room-post-rp1')), findsOneWidget);
      final forWidth = tester.getSize(find.byKey(const Key('standing-for'))).width;
      final againstWidth = tester.getSize(find.byKey(const Key('standing-against'))).width;
      expect(forWidth / againstWidth, closeTo(3, 0.1), reason: 'the bar is split 3 to 1');
      final s2 = s.seen.where((x) => x.path == '/api/events');
      expect(s2.expand((x) => (x.json['events'] as List)).map((e) => (e as Map)['name']), contains('room_opened'));
    });

    testWidgets('copying the code puts it on the clipboard', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await pumpApp(tester, roomServer(), const RoomScreen(roomId: 'r1'));
      await tester.tap(find.byKey(const Key('room-copy-code')));
      await tester.pump();
      expect(copied, 'ABC234');
    });

    testWidgets('a closed or not-yet-started room cannot be posted into, and says so', (tester) async {
      await pumpApp(tester, roomServer(room: roomJson(status: 'CLOSED')), const RoomScreen(roomId: 'r1'));
      expect(find.byKey(const Key('room-post')), findsNothing);
      expect(find.textContaining('closed'), findsWidgets);
    });

    testWidgets('an empty room says nobody has posted, and no decided opinions says so instead of an empty bar', (tester) async {
      await pumpApp(tester, roomServer(room: roomJson(forCount: 0, againstCount: 0, posts: 0)), const RoomScreen(roomId: 'r1'));
      expect(find.text('Nobody has posted in this room yet.'), findsOneWidget);
      expect(find.text('No opinions yet.'), findsOneWidget);
      expect(find.byKey(const Key('standing-for')), findsNothing);
    });

    testWidgets('the owner can close the room after confirming; a member can leave', (tester) async {
      final s = roomServer()..json('POST /api/rooms/r1/close', {'room': roomJson(status: 'CLOSED')});
      await pumpApp(tester, s, const RoomScreen(roomId: 'r1'));
      await tester.tap(find.byKey(const Key('room-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Leave room'), findsNothing, reason: 'the owner cannot leave');
      await tester.tap(find.text('Close room'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('room-confirm')));
      await tester.pumpAndSettle();
      expect(s.count('POST /api/rooms/r1/close'), 1);

      final m = roomServer(room: roomJson(role: 'MEMBER'))..json('POST /api/rooms/r1/leave', {'left': true});
      await pumpApp(tester, m, const RoomsScreen());
      await tester.tap(find.byKey(const ValueKey('room-r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('room-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Close room'), findsNothing);
      await tester.tap(find.text('Leave room'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('room-confirm')));
      await tester.pumpAndSettle();
      expect(m.count('POST /api/rooms/r1/leave'), 1);
      expect(find.byKey(const Key('room-motion-text')), findsNothing, reason: 'back on the list');
    });

    testWidgets('a room that cannot be loaded shows the reason', (tester) async {
      final s = FakeServer()
        ..json('GET /api/rooms/r1', {'error': 'Room not found'}, status: 404)
        ..json('GET /api/rooms/r1/posts', {'error': 'Room not found'}, status: 404);
      await pumpApp(tester, s, const RoomScreen(roomId: 'r1'));
      expect(find.text('Room not found'), findsOneWidget);
    });
  });

  group('invite friends', () {
    testWidgets('shows the code, copies the link with a line of words, and measures it', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final s = FakeServer()
        ..json('GET /api/me/invite', {'code': 'K7M2QXA', 'link': 'https://forestapp.in/invite/K7M2QXA', 'invitedCount': 2})
        ..json('POST /api/events', {'recorded': 1});
      await pumpApp(tester, s, const Scaffold(body: GrowthTiles()));
      await tester.tap(find.byKey(const Key('open-invite')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('invite-code')), findsOneWidget);
      expect(find.text('K7M2QXA'), findsOneWidget);
      expect(find.text('2 friends have joined with your code.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('invite-copy-link')));
      await tester.pump();
      expect(copied, contains('https://forestapp.in/invite/K7M2QXA'));
      await tester.tap(find.byKey(const Key('invite-copy-code')));
      await tester.pump();
      expect(copied, 'K7M2QXA');
      await tester.pumpAndSettle();
      final names = s.seen.where((x) => x.path == '/api/events').expand((x) => (x.json['events'] as List)).map((e) => (e as Map)['name']);
      expect(names.where((n) => n == 'invite_copied').length, 2);
    });

    testWidgets('no friends yet reads properly', (tester) async {
      final a = FakeServer()..json('GET /api/me/invite', {'code': 'K7M2QXA', 'link': 'https://x/invite/K7M2QXA', 'invitedCount': 0});
      await pumpApp(tester, a, const Scaffold(body: GrowthTiles()));
      await tester.tap(find.byKey(const Key('open-invite')));
      await tester.pumpAndSettle();
      expect(find.text('Nobody has joined with your code yet.'), findsOneWidget);
    });

    testWidgets('a failing server reads properly', (tester) async {
      final b = FakeServer()..json('GET /api/me/invite', {'error': 'The server is busy'}, status: 503);
      await pumpApp(tester, b, const Scaffold(body: GrowthTiles()));
      await tester.tap(find.byKey(const Key('open-invite')));
      await tester.pumpAndSettle();
      expect(find.text('The server is busy'), findsOneWidget);
    });

    testWidgets('the Account rows open the rooms page', (tester) async {
      final s = roomServer()..json('GET /api/rooms/mine', {'rooms': []});
      await pumpApp(tester, s, const Scaffold(body: GrowthTiles()));
      await tester.tap(find.byKey(const Key('open-rooms')));
      await tester.pumpAndSettle();
      expect(find.text('Debate rooms'), findsWidgets);
      expect(find.byKey(const Key('rooms-create')), findsOneWidget);
    });

    test('invite info parses', () {
      final i = InviteInfo.fromJson({'code': 'ABC', 'link': 'l', 'invitedCount': 5});
      expect((i.code, i.link, i.invitedCount), ('ABC', 'l', 5));
    });
  });
}
