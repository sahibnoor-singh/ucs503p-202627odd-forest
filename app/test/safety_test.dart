// Report and block, everywhere a person can meet someone they need protection from: the reels, the messages, the search card, and the
// list that undoes a block. Plus the legal text at sign-up and in Account, and what happens when something unexpected breaks.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:forest_app/features/discover/discover_screen.dart';
import 'package:forest_app/features/discover/discover_search_controller.dart';
import 'package:forest_app/features/discover/open_profile.dart';
import 'package:forest_app/features/discover/search_repository.dart';
import 'package:forest_app/features/legal/legal_screens.dart';
import 'package:forest_app/features/messages/chat_screen.dart';
import 'package:forest_app/features/messages/messages_repository.dart';
import 'package:forest_app/features/messages/unread_controller.dart';
import 'package:forest_app/features/reels/reels_feed.dart';
import 'package:forest_app/features/reels/reels_repository.dart';
import 'package:forest_app/features/safety/blocked_accounts_screen.dart';
import 'package:forest_app/features/safety/safety_actions.dart';
import 'package:forest_app/features/safety/safety_repository.dart';
import 'package:forest_app/models/user.dart';
import 'package:forest_app/models/video.dart';
import 'package:forest_app/services/app_errors.dart';

import 'support/fake_server.dart';

http.Response _reply(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> _user(String name, {bool bot = false}) =>
    {'id': 'id-$name', 'username': name, 'fullName': 'Full $name', 'avatarUrl': null, 'isBot': bot};

Map<String, dynamic> _video(String id, {String? author = 'id-aman', String user = 'aman'}) => {
      'id': id, 'title': 'Title $id', 'caption': 'Title $id', 'filename': '$id.mp4', 'coverUrl': null, 'status': 'ready', 'role': 'PARENT',
      'parentVideoId': null, 'stance': 'PARENT', 'credibility': 50, 'durationS': 0, 'userId': user, 'userName': user, 'authorId': author,
      'isBot': false, 'createdAt': '2026-10-10T10:00:00.000Z', 'likeCount': 0, 'replyCount': 0, 'forCount': 0, 'againstCount': 0,
      'viewerSide': null, 'liked': false, 'transcript': null,
    };

/// A button that runs [action] with the providers a real screen has.
Future<(FakeServer, BlocklistController)> _host(WidgetTester tester, Future<void> Function(BuildContext) action, {FakeServer? server}) async {
  final s = server ?? FakeServer();
  final blocklist = BlocklistController();
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<SafetyRepository>.value(value: SafetyRepository(s.client())),
      ChangeNotifierProvider<BlocklistController>.value(value: blocklist),
    ],
    child: MaterialApp(home: Scaffold(body: Builder(builder: (context) => TextButton(onPressed: () => action(context), child: const Text('go'))))),
  ));
  return (s, blocklist);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('report', () {
    testWidgets('asks why, sends the reason, and says it was received', (tester) async {
      final (server, _) = await _host(tester, (c) => reportPostFlow(c, postId: 'p1'), server: FakeServer()..json('POST /api/posts/p1/report', {'reported': true}));
      await tester.tap(find.text('go'));
      await _settle(tester);
      expect(find.text('Why are you reporting this?'), findsOneWidget);
      for (final w in ['MISINFORMATION', 'HARASSMENT', 'SPAM', 'VIOLENCE', 'OTHER']) {
        expect(find.byKey(ValueKey('report-$w')), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('report-HARASSMENT')));
      await _settle(tester);
      expect(server.last('POST /api/posts/p1/report').json, {'reason': 'HARASSMENT'});
      expect(find.text('Reported. We will review it.'), findsOneWidget);
    });

    testWidgets('closing the sheet reports nothing', (tester) async {
      final (server, _) = await _host(tester, (c) => reportPostFlow(c, postId: 'p1'));
      await tester.tap(find.text('go'));
      await _settle(tester);
      await tester.tapAt(const Offset(200, 40)); // the scrim
      await _settle(tester);
      expect(server.count('POST /api/posts/p1/report'), 0);
    });

    testWidgets('a refusal says why, for example your own post', (tester) async {
      final (_, _) = await _host(tester, (c) => reportPostFlow(c, postId: 'p1'),
          server: FakeServer()..on('POST /api/posts/p1/report', (_) => _reply({'error': "You can't report your own post"}, status: 400)));
      await tester.tap(find.text('go'));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('report-SPAM')));
      await _settle(tester);
      expect(find.text("You can't report your own post"), findsOneWidget);
    });
  });

  group('block', () {
    testWidgets('asks first; Cancel changes nothing', (tester) async {
      final (server, blocklist) = await _host(tester, (c) => blockPersonFlow(c, userId: 'id-aman', username: 'aman'));
      await tester.tap(find.text('go'));
      await _settle(tester);
      expect(find.text('Block @aman?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(server.count('POST /api/users/id-aman/block'), 0);
      expect(blocklist.isBlocked('id-aman'), isFalse);
    });

    testWidgets('Block tells the server, hides them for the session, and Undo takes it back', (tester) async {
      final (server, blocklist) = await _host(tester, (c) => blockPersonFlow(c, userId: 'id-aman', username: 'aman'),
          server: FakeServer()..json('POST /api/users/id-aman/block', {'blocked': true})..json('DELETE /api/users/id-aman/block', {'blocked': false}));
      await tester.tap(find.text('go'));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('confirm-block')));
      await _settle(tester);
      expect(server.count('POST /api/users/id-aman/block'), 1);
      expect(blocklist.isBlocked('id-aman'), isTrue);
      expect(find.text('Blocked @aman'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await _settle(tester);
      expect(server.count('DELETE /api/users/id-aman/block'), 1);
      expect(blocklist.isBlocked('id-aman'), isFalse);
    });

    testWidgets('a block the server refuses says why and hides nobody', (tester) async {
      final (_, blocklist) = await _host(tester, (c) => blockPersonFlow(c, userId: 'id-aman', username: 'aman'),
          server: FakeServer()..on('POST /api/users/id-aman/block', (_) => _reply({'error': "You can't do that to yourself"}, status: 400)));
      await tester.tap(find.text('go'));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('confirm-block')));
      await _settle(tester);
      expect(find.text("You can't do that to yourself"), findsOneWidget);
      expect(blocklist.isBlocked('id-aman'), isFalse);
    });
  });

  group('blocked accounts', () {
    Future<(FakeServer, BlocklistController)> pump(WidgetTester tester, {List<Map<String, dynamic>>? users, bool fail = false}) async {
      final server = FakeServer()
        ..on('GET /api/me/blocks', (_) => fail ? _reply({'error': 'Server is down'}, status: 503) : _reply({'users': users ?? []}))
        ..json('DELETE /api/users/id-aman/block', {'blocked': false});
      final blocklist = BlocklistController()..add('id-aman');
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [Provider<SafetyRepository>.value(value: SafetyRepository(server.client())), ChangeNotifierProvider<BlocklistController>.value(value: blocklist)],
        child: const MaterialApp(home: BlockedAccountsScreen()),
      ));
      await _settle(tester);
      return (server, blocklist);
    }

    testWidgets('lists who is blocked; Unblock takes them off the list and tells the server', (tester) async {
      final (server, blocklist) = await pump(tester, users: [_user('aman'), _user('riya')]);
      expect(find.text('aman'), findsOneWidget);
      expect(find.text('riya'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('unblock-id-aman')));
      await _settle(tester);
      expect(server.count('DELETE /api/users/id-aman/block'), 1);
      expect(find.text('aman'), findsNothing);
      expect(find.text('riya'), findsOneWidget);
      expect(blocklist.isBlocked('id-aman'), isFalse);
      expect(find.textContaining('Unblocked @aman'), findsOneWidget);
    });

    testWidgets('an empty list explains what blocking does', (tester) async {
      await pump(tester, users: []);
      expect(find.textContaining('You have not blocked anyone'), findsOneWidget);
    });

    testWidgets('a server that is down shows why and can be retried', (tester) async {
      await pump(tester, fail: true);
      expect(find.text('Server is down'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('in the messages', () {
    late FakeServer server;

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      server = FakeServer()
        ..json('GET /api/messages/with/id-riya', {
          'with': _user('riya'),
          'hasMore': false,
          'messages': [
            {'id': 'm1', 'fromMe': false, 'video': _video('v1'), 'createdAt': DateTime.now().toUtc().toIso8601String(), 'reactions': {'mine': null, 'theirs': null}},
            {'id': 'm2', 'fromMe': true, 'video': _video('v2'), 'createdAt': DateTime.now().toUtc().toIso8601String(), 'reactions': {'mine': null, 'theirs': null}},
          ],
        })
        ..json('POST /api/messages/with/id-riya/read', {'ok': true})
        ..json('GET /api/messages/unread', {'unread': 0})
        ..json('POST /api/posts/v1/report', {'reported': true})
        ..json('POST /api/users/id-riya/block', {'blocked': true});
      final repo = MessagesRepository(server.client());
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<UnreadController>(create: (_) => UnreadController(repo)),
          Provider<SafetyRepository>.value(value: SafetyRepository(server.client())),
          ChangeNotifierProvider<BlocklistController>(create: (_) => BlocklistController()),
        ],
        child: MaterialApp(home: Builder(builder: (context) => TextButton(onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => ChatScreen(person: User.fromJson(_user('riya')), repository: repo, pollEvery: const Duration(minutes: 5)))), child: const Text('open')))),
      ));
      await tester.tap(find.text('open'));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('only a video somebody else sent has a menu; mine does not', (tester) async {
      await pump(tester);
      expect(find.byKey(const ValueKey('video-more')), findsOneWidget);
    });

    testWidgets('Report this video asks why and reports that video', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('video-more')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('report-video')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('report-VIOLENCE')));
      await _settle(tester);
      expect(server.last('POST /api/posts/v1/report').json, {'reason': 'VIOLENCE'});
    });

    testWidgets('Block from the video menu blocks the person and leaves the conversation', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('video-more')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('block-person')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('confirm-block')));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(server.count('POST /api/users/id-riya/block'), 1);
      expect(find.byType(ChatScreen), findsNothing, reason: 'back to where we came from');
    });

    testWidgets('Block from the top menu does the same', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('chat-menu')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('menu-block')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('confirm-block')));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(server.count('POST /api/users/id-riya/block'), 1);
      expect(find.byType(ChatScreen), findsNothing);
    });
  });

  group('in the reels', () {
    Future<FakeServer> pump(WidgetTester tester, {String? author = 'id-aman'}) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final server = FakeServer()
        ..json('GET /api/videos/a/tree', [_video('a', author: author)])
        ..json('GET /api/videos/a/replies', [])
        ..json('POST /api/posts/a/report', {'reported': true})
        ..json('POST /api/users/id-aman/block', {'blocked': true});
      var closed = false;
      await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<SafetyRepository>.value(value: SafetyRepository(server.client())),
          ChangeNotifierProvider<BlocklistController>(create: (_) => BlocklistController()),
        ],
        child: MaterialApp(home: Scaffold(body: ReelsFeed(repository: ReelsRepository(server.client()), initialDebateRoots: [Video.fromJson(_video('a', author: author))], onClose: () => closed = true))),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      addTearDown(() => expect(closed, isA<bool>()));
      return server;
    }

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }

    testWidgets('the menu offers Report video and Block @name for someone else\'s video', (tester) async {
      await pump(tester);
      await openMenu(tester);
      expect(find.text('Report video'), findsOneWidget);
      expect(find.byKey(const Key('reel-block')), findsOneWidget);
      expect(find.text('Block @aman'), findsOneWidget);
    });

    testWidgets('no Block when the server did not say who made it', (tester) async {
      await pump(tester, author: null);
      await openMenu(tester);
      expect(find.text('Report video'), findsOneWidget);
      expect(find.byKey(const Key('reel-block')), findsNothing);
    });

    testWidgets('Report video asks for a reason instead of sending "other"', (tester) async {
      final server = await pump(tester);
      await openMenu(tester);
      await tester.tap(find.text('Report video'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byKey(const ValueKey('report-MISINFORMATION')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(server.last('POST /api/posts/a/report').json, {'reason': 'MISINFORMATION'});
    });

    testWidgets('Block confirms, tells the server and closes the feed', (tester) async {
      final server = await pump(tester);
      await openMenu(tester);
      await tester.tap(find.byKey(const Key('reel-block')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byKey(const Key('confirm-block')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(server.count('POST /api/users/id-aman/block'), 1);
    });
  });

  group('in Discover', () {
    testWidgets('someone blocked during the session disappears from the grid at once', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final server = FakeServer()
        ..json('GET /api/videos/feed', {
          'videos': [for (var i = 0; i < 6; i++) _video('g$i', author: i == 2 ? 'id-bad' : 'id-ok$i', user: i == 2 ? 'bad' : 'ok$i')],
          'nextCursor': null,
        });
      final blocklist = BlocklistController();
      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider<BlocklistController>.value(value: blocklist)],
        child: MaterialApp(home: DiscoverScreen(repository: ReelsRepository(server.client()), searchRepository: SearchRepository(server.client()), setFollowing: (_, _) async {})),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Title g2'), findsOneWidget);
      blocklist.add('id-bad');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Title g2'), findsNothing);
      expect(find.text('Title g1'), findsOneWidget);
    });

    testWidgets('the search profile card has Block; blocking removes the person from the results', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final server = FakeServer()
        ..json('GET /api/search', {'accounts': [{'user': _user('sam'), 'followerCount': 1, 'postCount': 1, 'followedByMe': false, 'isMe': false}], 'posts': [], 'nextCursor': null})
        ..json('POST /api/users/id-sam/block', {'blocked': true});
      final search = DiscoverSearchController(SearchRepository(server.client()), setFollowing: (_, _) async {}, pause: const Duration(milliseconds: 5));
      await tester.runAsync(() async {
        search.setQuery('sam');
        await Future<void>.delayed(const Duration(milliseconds: 80)); // real time: the search waits for typing to pause
      });
      expect(search.accounts, hasLength(1));
      await tester.pumpWidget(MultiProvider(
        providers: [Provider<SafetyRepository>.value(value: SafetyRepository(server.client())), ChangeNotifierProvider<BlocklistController>(create: (_) => BlocklistController())],
        child: MaterialApp(home: Scaffold(body: Builder(builder: (context) => TextButton(onPressed: () => openProfile(context, search.accounts.single, search), child: const Text('go'))))),
      ));
      await tester.tap(find.text('go'));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('profile-block')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('confirm-block')));
      await _settle(tester);
      expect(server.count('POST /api/users/id-sam/block'), 1);
      expect(search.accounts, isEmpty);
    });
  });

  group('legal text', () {
    testWidgets('the consent line names both documents and each link opens its document', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Padding(padding: EdgeInsets.all(16), child: LegalConsentText()))));
      final text = tester.widget<Text>(find.byKey(const Key('legal-consent')));
      final span = text.textSpan! as TextSpan;
      final links = <String>[];
      for (final child in span.children!) {
        if (child is TextSpan && child.recognizer != null) links.add(child.text!);
      }
      expect(links, ['Terms of use', 'Privacy notice']);
      expect(span.toPlainText(), contains('18 or older'));
    });

    testWidgets('the terms and the privacy notice read in full without a server, and the contact appears when there is one', (tester) async {
      tester.view.physicalSize = const Size(400, 5000); // tall enough that the whole document is built
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: LegalScreen(key: UniqueKey(), doc: LegalDoc.terms, api: FakeServer().client()))); // no route: 404, ignored
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Terms of use'), findsOneWidget);
      expect(find.text('Who can use FOREST'), findsOneWidget);
      expect(find.text('Automatic labels can be wrong'), findsOneWidget);
      expect(find.textContaining('grievance contact'), findsOneWidget);

      final server = FakeServer()..json('GET /api/legal/contact', {'name': 'A. Officer', 'email': 'officer@example.test'});
      await tester.pumpWidget(MaterialApp(home: LegalScreen(key: UniqueKey(), doc: LegalDoc.privacy, api: server.client())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Privacy notice'), findsOneWidget);
      expect(find.text('What we collect'), findsOneWidget);
      expect(find.textContaining('Gemini'), findsWidgets, reason: 'it says who receives the audio');
      expect(find.textContaining('A. Officer · officer@example.test'), findsOneWidget);
    });
  });

  group('when something unexpected breaks', () {
    test('error handling is installed, and an uncaught error is logged and swallowed', () {
      final before = FlutterError.onError;
      addTearDown(() => FlutterError.onError = before);
      installErrorHandling();
      expect(FlutterError.onError, isNot(same(before)));
      reportError(StateError('boom'), StackTrace.current); // must not throw
    });

    testWidgets('the replacement for a broken widget is a plain message, not a red screen', (tester) async {
      await tester.pumpWidget(const FriendlyError());
      expect(find.textContaining('Something went wrong here'), findsOneWidget);
    });

    testWidgets('a build with no server address says so', (tester) async {
      await tester.pumpWidget(const MisconfiguredApp());
      expect(find.textContaining('API_BASE_URL'), findsOneWidget);
    });
  });

  test('Video reads the author id, and a server that does not send one leaves it empty', () {
    expect(Video.fromJson(_video('a')).authorId, 'id-aman');
    expect(Video.fromJson(_video('a', author: null)).authorId, isNull);
    expect(Video.fromJson(_video('a')).copyWith(isLiked: true).authorId, 'id-aman');
  });
}
