// Sending a video to a friend: the repository, the paper-plane sheet in Home and the reels, and the "Sent to you" row in Discover.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:forest_app/features/reels/reel_overlay.dart';
import 'package:forest_app/features/share/share_repository.dart';
import 'package:forest_app/models/video.dart';
import 'package:forest_app/ui/forest_icon.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

http.Response _reply(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> _user(String name, {bool bot = false}) =>
    {'id': 'id-$name', 'username': name, 'fullName': 'Full $name', 'avatarUrl': null, 'isBot': bot};

Map<String, dynamic> _video(String id, {String? title}) => {
      'id': id, 'title': title ?? 'Title $id', 'caption': title ?? 'Title $id', 'filename': '$id.mp4', 'coverUrl': null, 'status': 'ready',
      'role': 'PARENT', 'parentVideoId': null, 'stance': 'PARENT', 'credibility': 50, 'durationS': 0, 'userId': 'aman', 'userName': 'aman',
      'isBot': false, 'createdAt': '2026-10-10T10:00:00.000Z', 'likeCount': 0, 'replyCount': 0, 'forCount': 0, 'againstCount': 0,
      'viewerSide': null, 'liked': false, 'transcript': null,
    };

Finder _icon(String name) => find.byWidgetPredicate((w) => w is ForestIcon && w.name == name);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('repository', () {
    test('friends, and a send with a skipped person', () async {
      final server = FakeServer()
        ..json('GET /api/users/friends', {'users': [_user('riya'), _user('zed')]})
        ..on('POST /api/posts/p1/share', (s) => _reply({'sent': ['id-riya'], 'skipped': [{'userId': 'id-zed', 'reason': 'NOT_FRIENDS'}]}));
      final repo = ShareRepository(server.client());
      expect((await repo.friends()).map((u) => u.username), ['riya', 'zed']);

      final result = await repo.send('p1', ['id-riya', 'id-zed']);
      expect(result.sent, ['id-riya']);
      expect(result.skipped, {'id-zed': 'NOT_FRIENDS'});
      expect(server.last('POST /api/posts/p1/share').json, {'recipientIds': ['id-riya', 'id-zed']});
    });
  });

  group('the paper-plane in Home', () {
    testWidgets('opens a sheet with Copy link and your friends; Send marks them Sent', (tester) async {
      useTallScreen(tester);
      final server = FakeServer()
        ..json('GET /api/users/friends', {'users': [_user('riya'), _user('zed')]})
        ..on('POST /api/posts/r1/share', (s) => _reply({'sent': s.json['recipientIds'], 'skipped': []}));
      await pumpHome(tester, sampleRepo(homeOrder: ['r1']), shareRepository: ShareRepository(server.client()));
      await tester.tap(_icon(Icn.send).at(1));
      await settle(tester);

      expect(find.text('Copy link'), findsOneWidget);
      expect(find.text('Send to a friend'), findsOneWidget);
      expect(find.text('riya'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('send-id-riya')));
      await settle(tester);
      expect(server.last('POST /api/posts/r1/share').json, {'recipientIds': ['id-riya']});
      expect(find.text('Sent'), findsOneWidget);
      expect(find.text('Send'), findsOneWidget, reason: 'zed has not been sent anything');
    });

    testWidgets('a video that has no file cannot be sent, only linked', (tester) async {
      useTallScreen(tester);
      final server = FakeServer();
      await pumpHome(tester, sampleRepo(), shareRepository: ShareRepository(server.client())); // the first card is r3, which has no file
      await tester.tap(_icon(Icn.send).at(1));
      await settle(tester);
      expect(find.text('Copy link'), findsOneWidget);
      expect(find.textContaining('Only videos can be sent'), findsOneWidget);
      expect(server.count('GET /api/users/friends'), 0, reason: 'no point loading friends');
    });

    testWidgets('a refusal says why in words, and the button works again', (tester) async {
      useTallScreen(tester);
      final server = FakeServer()
        ..json('GET /api/users/friends', {'users': [_user('riya')]})
        ..on('POST /api/posts/r1/share', (_) => _reply({'sent': [], 'skipped': [{'userId': 'id-riya', 'reason': 'NOT_FRIENDS'}]}));
      await pumpHome(tester, sampleRepo(homeOrder: ['r1']), shareRepository: ShareRepository(server.client()));
      await tester.tap(_icon(Icn.send).at(1));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('send-id-riya')));
      await settle(tester);
      expect(find.textContaining('follow you back'), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
    });

    testWidgets('a server error and a daily limit show the server\'s own message', (tester) async {
      useTallScreen(tester);
      final server = FakeServer()
        ..json('GET /api/users/friends', {'users': [_user('riya')]})
        ..on('POST /api/posts/r1/share', (_) => _reply({'error': 'You can send at most 50 videos a day. Try again tomorrow.'}, status: 429));
      await pumpHome(tester, sampleRepo(homeOrder: ['r1']), shareRepository: ShareRepository(server.client()));
      await tester.tap(_icon(Icn.send).at(1));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('send-id-riya')));
      await settle(tester);
      expect(find.textContaining('at most 50 videos a day'), findsOneWidget);
    });

    testWidgets('with no friends it says how to get some, and Copy link still works', (tester) async {
      useTallScreen(tester);
      final server = FakeServer()..json('GET /api/users/friends', {'users': []});
      await pumpHome(tester, sampleRepo(homeOrder: ['r1']), shareRepository: ShareRepository(server.client()));
      await tester.tap(_icon(Icn.send).at(1));
      await settle(tester);
      expect(find.textContaining('follow you back'), findsOneWidget);
      expect(find.text('Copy link'), findsOneWidget);
    });

    testWidgets('a friend list that cannot load can be retried', (tester) async {
      useTallScreen(tester);
      var up = false;
      final server = FakeServer()
        ..on('GET /api/users/friends', (_) => up ? _reply({'users': [_user('riya')]}) : _reply({'error': 'Friends are unavailable'}, status: 503));
      await pumpHome(tester, sampleRepo(homeOrder: ['r1']), shareRepository: ShareRepository(server.client()));
      await tester.tap(_icon(Icn.send).at(1));
      await settle(tester);
      expect(find.text('Friends are unavailable'), findsOneWidget);
      up = true;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('riya'), findsOneWidget);
    });
  });

  group('the paper-plane in the reels', () {
    testWidgets('the rail has a Send button when the feed handles it, and none otherwise', (tester) async {
      var taps = 0;
      Widget overlay({VoidCallback? onShare}) {
        final video = Video.fromJson(_video('a'));
        return MaterialApp(
          home: Scaffold(
            body: ReelOverlay(
              video: video,
              rootVideo: video,
              muteNotifier: ValueNotifier(false),
              onToggleMute: () {},
              onLike: () {},
              onOpenTree: () {},
              onOpenReplySheet: () {},
              onMoreOptions: () {},
              onShare: onShare,
            ),
          ),
        );
      }

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(overlay());
      expect(find.byIcon(Icons.send_outlined), findsNothing);
      await tester.pumpWidget(overlay(onShare: () => taps++));
      await tester.tap(find.byIcon(Icons.send_outlined));
      expect(taps, 1);
    });
  });

  group('why Discover picked a video', () {
    Widget overlay(Video video) => MaterialApp(
          home: Scaffold(
            body: ReelOverlay(
              video: video,
              rootVideo: video,
              muteNotifier: ValueNotifier(false),
              onToggleMute: () {},
              onLike: () {},
              onOpenTree: () {},
              onOpenReplySheet: () {},
              onMoreOptions: () {},
            ),
          ),
        );

    testWidgets('a friend pick names the friend, exploration says so, and own picks say nothing', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(overlay(Video.fromJson({..._video('a'), 'why': {'kind': 'friend', 'by': 'riya'}})));
      expect(find.text("Picked by @riya's taste"), findsOneWidget);
      await tester.pumpWidget(overlay(Video.fromJson({..._video('b'), 'why': {'kind': 'explore'}})));
      expect(find.text('Something different from your usual'), findsOneWidget);
      await tester.pumpWidget(overlay(Video.fromJson(_video('c'))));
      expect(find.textContaining('Picked by'), findsNothing);
      expect(find.textContaining('Something different'), findsNothing);
    });

    test('it survives copyWith (a like must not erase it) and odd shapes are ignored', () {
      final v = Video.fromJson({..._video('a'), 'why': {'kind': 'friend', 'by': 'riya'}});
      expect(v.copyWith(isLiked: true).pickedBy, 'riya');
      expect(Video.fromJson({..._video('a'), 'why': 'friend'}).pickedBy, isNull);
      expect(Video.fromJson({..._video('a'), 'why': {'kind': 'friend'}}).pickedBy, isNull);
    });
  });
}
