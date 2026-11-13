// Discover search: waiting for typing to pause, one set of results per tab, stale answers dropped, paging, following from a result,
// recent searches, and what the screen does with it all.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:forest_app/features/discover/discover_screen.dart';
import 'package:forest_app/features/discover/discover_search_controller.dart';
import 'package:forest_app/features/discover/recent_searches.dart';
import 'package:forest_app/features/discover/search_repository.dart';
import 'package:forest_app/features/reels/reels_feed.dart';
import 'package:forest_app/features/reels/reels_repository.dart';
import 'package:forest_app/services/api_client.dart';
import 'package:forest_app/ui/chips.dart';

import 'support/fake_server.dart';

http.Response _reply(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> _video(String id, {String? parent, bool bot = false, String stance = 'PARENT', String? title}) => {
      'id': id, 'title': title ?? 'Title $id', 'caption': title ?? 'Title $id', 'filename': '$id.mp4', 'coverUrl': null, 'status': 'ready',
      'role': parent == null ? 'PARENT' : 'CHILD', 'parentVideoId': parent, 'stance': stance, 'credibility': 50, 'durationS': 0,
      'userId': 'aman', 'userName': 'aman', 'isBot': bot, 'createdAt': '2026-10-10T10:00:00.000Z', 'likeCount': 0, 'replyCount': 0,
      'forCount': 0, 'againstCount': 0, 'viewerSide': null, 'liked': false, 'transcript': null,
    };

Map<String, dynamic> _account(String name, {bool followed = false, bool bot = false, bool me = false, int followers = 3}) => {
      'user': {'id': 'id-$name', 'username': name, 'fullName': 'Full $name', 'avatarUrl': null, 'isBot': bot},
      'followerCount': followers, 'postCount': 2, 'followedByMe': followed, 'isMe': me,
    };

List<String> _titles(DiscoverSearchController c) => c.posts.map((v) => v.id).toList();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('controller', () {
    DiscoverSearchController make(FakeServer server, {List<Future<void>>? follows, Duration pause = const Duration(milliseconds: 20)}) =>
        DiscoverSearchController(
          SearchRepository(server.client()),
          setFollowing: (id, f) async => follows?.add(Future.value()),
          pause: pause,
        );

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 80));

    test('asks nothing for fewer than two letters, and one question when typing pauses', () async {
      final server = FakeServer()..json('GET /api/search', {'accounts': [], 'posts': [_video('a')], 'nextCursor': null});
      final c = make(server);
      c.setQuery('p');
      await settle();
      expect(server.count('GET /api/search'), 0);
      expect(c.hasQuery, isFalse);

      for (final typed in ['ph', 'pho', 'phon', 'phone', 'phones']) {
        c.setQuery(typed);
      }
      expect(c.loading, isTrue, reason: 'the spinner shows during the pause, not "nothing found"');
      await settle();
      expect(server.count('GET /api/search'), 1);
      expect(server.last('GET /api/search').uri.queryParameters, {'q': 'phones', 'type': 'all', 'limit': '20'});
      expect(_titles(c), ['a']);
      expect(c.loading, isFalse);
    });

    test('extra spaces are tidied away before asking', () async {
      final server = FakeServer()..json('GET /api/search', {'accounts': [], 'posts': [], 'nextCursor': null});
      final c = make(server);
      c.setQuery('  ban    phones  ');
      await settle();
      expect(server.last('GET /api/search').uri.queryParameters['q'], 'ban phones');
      expect(c.query, 'ban phones');
    });

    test('an answer for words that were typed over is dropped', () async {
      final gates = <String, Completer<http.Response>>{};
      final client = MockClient((request) {
        final q = request.url.queryParameters['q']!;
        return (gates[q] = Completer<http.Response>()).future;
      });
      final c = DiscoverSearchController(
        SearchRepository(ApiClient(baseUrl: 'http://t.invalid', devUser: '', client: client)),
        setFollowing: (_, _) async {},
        pause: const Duration(milliseconds: 5),
      );
      c.setQuery('first');
      await settle();
      c.setQuery('second');
      await settle();
      gates['second']!.complete(_reply({'accounts': [], 'posts': [_video('second')], 'nextCursor': null}));
      await settle();
      gates['first']!.complete(_reply({'accounts': [], 'posts': [_video('first')], 'nextCursor': null}));
      await settle();
      expect(_titles(c), ['second']);
    });

    test('each tab keeps its own results and pages: Accounts asks for accounts, Posts for posts, then more from the cursor', () async {
      final server = FakeServer()
        ..on('GET /api/search', (s) {
          final type = s.uri.queryParameters['type'];
          final cursor = s.uri.queryParameters['cursor'];
          if (type == 'accounts') return _reply({'accounts': [_account('sam'), _account('samir')], 'posts': [], 'nextCursor': null});
          if (type == 'posts') {
            return _reply(cursor == null
                ? {'accounts': [], 'posts': [_video('p1'), _video('p2')], 'nextCursor': 'c1'}
                : {'accounts': [], 'posts': [_video('p2'), _video('p3')], 'nextCursor': null}); // p2 again: dropped
          }
          return _reply({'accounts': [_account('sam')], 'posts': [_video('p1')], 'nextCursor': null});
        });
      final c = make(server);
      c.setQuery('sam');
      await settle();
      expect(c.accounts.map((a) => a.user.username), ['sam']);

      c.setType(SearchType.accounts);
      await settle();
      expect(c.accounts.map((a) => a.user.username), ['sam', 'samir']);

      c.setType(SearchType.posts);
      await settle();
      expect(_titles(c), ['p1', 'p2']);
      expect(c.hasMore, isTrue);
      await c.loadMore();
      expect(_titles(c), ['p1', 'p2', 'p3'], reason: 'no repeats');
      expect(c.hasMore, isFalse);
      expect(server.last('GET /api/search').uri.queryParameters['cursor'], 'c1');

      final before = server.count('GET /api/search');
      c.setType(SearchType.all);
      await settle();
      expect(server.count('GET /api/search'), before, reason: 'a tab that was already loaded is not asked for again');
      expect(c.accounts, hasLength(1));
    });

    test('new words clear every tab; a failure says why and can be retried; a failed next page keeps the posts', () async {
      var down = false;
      final server = FakeServer()
        ..on('GET /api/search', (s) {
          if (down && s.uri.queryParameters['cursor'] == null) return _reply({'error': 'Search is busy'}, status: 503);
          if (s.uri.queryParameters['cursor'] != null) return _reply({'error': 'x'}, status: 500);
          return _reply({'accounts': [], 'posts': [_video('p1')], 'nextCursor': 'c1'});
        });
      final c = make(server);
      c.setQuery('tea');
      await settle();
      await c.loadMore();
      expect(c.moreFailed, isTrue);
      expect(_titles(c), ['p1']);

      down = true;
      c.setQuery('coffee');
      expect(_titles(c), isEmpty, reason: 'the old words\' results are gone at once');
      await settle();
      expect(c.error, 'Search is busy');
      down = false;
      await c.retry();
      expect(c.error, isNull);
      expect(_titles(c), ['p1']);
    });

    test('following from a result shows at once everywhere, and is undone if the server says no', () async {
      final server = FakeServer()..json('GET /api/search', {'accounts': [_account('sam', followers: 3)], 'posts': [], 'nextCursor': null});
      var refuse = false;
      final c = DiscoverSearchController(
        SearchRepository(server.client()),
        setFollowing: (id, following) async {
          if (refuse) throw const ApiException('Not now');
        },
        pause: const Duration(milliseconds: 5),
      );
      c.setQuery('sam');
      await settle();
      final hit = c.accounts.single;

      expect(await c.toggleFollow(hit), isNull);
      expect(c.accounts.single.followedByMe, isTrue);
      expect(c.accounts.single.followerCount, 4);
      expect(c.accountById('id-sam')!.followedByMe, isTrue);

      refuse = true;
      expect(await c.toggleFollow(c.accounts.single), 'Not now');
      expect(c.accounts.single.followedByMe, isTrue, reason: 'unfollowing was refused: still following');
      expect(c.accounts.single.followerCount, 4);
    });

    test('recent searches: kept when a search is submitted or opened, newest first, no repeats, removable', () async {
      final server = FakeServer()..json('GET /api/search', {'accounts': [], 'posts': [], 'nextCursor': null});
      final c = make(server);
      for (final q in ['tea', 'coffee', 'Tea']) {
        c.setQuery(q);
        c.submit();
        await settle();
      }
      expect(c.recent, ['Tea', 'coffee'], reason: 'tea and Tea are one search');
      expect(await RecentSearches().load(), ['Tea', 'coffee'], reason: 'it is kept on the phone');

      c.setQuery('x');
      c.submit();
      expect(c.recent, ['Tea', 'coffee'], reason: 'one letter is not a search');

      await c.removeRecent('coffee');
      expect(c.recent, ['Tea']);
      await c.clearRecents();
      expect(c.recent, isEmpty);
    });

    test('only the last eight searches are kept', () async {
      final r = RecentSearches();
      for (var i = 0; i < 12; i++) {
        await r.add('search $i');
      }
      final kept = await r.load();
      expect(kept, hasLength(8));
      expect(kept.first, 'search 11');
    });
  });

  group('screen', () {
    late FakeServer server;

    FakeServer baseServer() => FakeServer()
      ..json('GET /api/videos/feed', {'videos': [for (var i = 0; i < 6; i++) _video('g$i')], 'nextCursor': null})
      ..on('GET /api/search', (s) {
        final q = s.uri.queryParameters['q']!;
        if (q == 'nothing') return _reply({'q': q, 'accounts': [], 'posts': [], 'nextCursor': null});
        return _reply({
          'q': q,
          'accounts': [_account('sam_bot', bot: true), _account('samir', followed: true)],
          'posts': [_video('root1', title: 'Phones in class'), _video('reply1', parent: 'root1', stance: 'FOR', title: 'A reply about phones')],
          'nextCursor': null,
        });
      })
      ..json('GET /api/videos/reply1/tree', [_video('root1', title: 'Phones in class'), _video('reply1', parent: 'root1', stance: 'FOR')])
      ..json('GET /api/videos/root1/tree', [_video('root1', title: 'Phones in class')]);

    Future<List<String>> pump(WidgetTester tester, {Size size = const Size(400, 800), List<String>? follows}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      server = baseServer();
      final followed = follows ?? <String>[];
      await tester.pumpWidget(MaterialApp(
        home: DiscoverScreen(
          repository: ReelsRepository(server.client()),
          searchRepository: SearchRepository(server.client()),
          setFollowing: (id, f) async => followed.add('${f ? 'follow' : 'unfollow'}:$id'),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      return followed;
    }

    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('the grid has a search box above it; using the box swaps the grid for hints, and Cancel brings the grid back', (tester) async {
      await pump(tester);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Title g1'), findsOneWidget);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.textContaining('Search for posts, debates and people'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Title g1'), findsOneWidget, reason: 'the grid is back');
    });

    testWidgets('typing shows accounts and posts with BOT labels; the tabs narrow it down', (tester) async {
      await pump(tester);
      await type(tester, 'phones');
      expect(find.text('Accounts'), findsWidgets);
      expect(find.text('sam_bot'), findsOneWidget);
      expect(find.byType(BotTag), findsOneWidget, reason: 'the automated account is labelled in results too');
      expect(find.text('Phones in class'), findsOneWidget);
      expect(find.text('Following'), findsOneWidget, reason: 'samir is already followed');

      await tester.tap(find.byKey(const ValueKey('search-tab-posts')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('sam_bot'), findsNothing);
      expect(find.text('Phones in class'), findsOneWidget);
      expect(server.last('GET /api/search').uri.queryParameters['type'], 'posts');
    });

    testWidgets('no matches says so with the words that were searched', (tester) async {
      await pump(tester);
      await type(tester, 'nothing');
      expect(find.textContaining('Nothing found for “nothing”'), findsOneWidget);
    });

    testWidgets('Follow on a result asks the server and the button changes', (tester) async {
      final calls = await pump(tester);
      await type(tester, 'sam');
      await tester.tap(find.byKey(const ValueKey('follow-id-sam_bot')));
      await tester.pump();
      expect(calls, ['follow:id-sam_bot']);
      expect(find.text('Following'), findsNWidgets(2));
    });

    testWidgets('tapping an opening video plays it on its own, with a back arrow', (tester) async {
      await pump(tester);
      await type(tester, 'phones');
      await tester.tap(find.text('Phones in class'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final feed = tester.widget<ReelsFeed>(find.byType(ReelsFeed));
      expect(feed.initialDebateRoots!.map((v) => v.id), ['root1']);
      expect(feed.startOn, isNull);
      expect(feed.onClose, isNotNull);
      expect(await RecentSearches().load(), ['phones'], reason: 'opening a result remembers the search');
    });

    testWidgets('tapping a reply opens its debate on that reply', (tester) async {
      await pump(tester);
      await type(tester, 'phones');
      await tester.tap(find.text('A reply about phones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final feed = tester.widget<ReelsFeed>(find.byType(ReelsFeed));
      expect(feed.initialDebateRoots!.map((v) => v.id), ['root1'], reason: 'the debate starts at its opening video');
      expect(feed.startOn!.id, 'reply1', reason: 'but opens on the reply that was found');
    });

    testWidgets('the system back button leaves the search before it leaves the app', (tester) async {
      await pump(tester);
      await type(tester, 'phones');
      expect(find.text('Cancel'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Title g1'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    });

    testWidgets('a recent search can be tapped to run it again', (tester) async {
      SharedPreferences.setMockInitialValues({'discover_recent_searches': ['phones', 'tea']});
      await pump(tester);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Recent'), findsOneWidget);
      await tester.tap(find.text('tea'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(server.last('GET /api/search').uri.queryParameters['q'], 'tea');
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'tea');
    });

    testWidgets('results fit a narrow phone without overflow', (tester) async {
      await pump(tester, size: const Size(320, 640));
      await type(tester, 'phones');
      expect(tester.takeException(), isNull);
      expect(find.text('Phones in class'), findsOneWidget);
    });
  });
}
