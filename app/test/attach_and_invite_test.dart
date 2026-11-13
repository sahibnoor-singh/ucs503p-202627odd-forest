// What a new opinion can be part of (the day's question, a room), the real share link, and signing up with an invite code.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:forest_app/data/api_feed_repository.dart';
import 'package:forest_app/data/auth_repository.dart';
import 'package:forest_app/data/fake_feed_repository.dart';
import 'package:forest_app/features/auth/signup_controller.dart';
import 'package:forest_app/features/editor/editor_controller.dart';
import 'package:forest_app/features/editor/post_attachment.dart';
import 'package:forest_app/features/editor/recipe.dart';
import 'package:forest_app/features/home/feed_controller.dart';
import 'package:forest_app/services/api_client.dart';
import 'package:forest_app/services/public_links.dart';

import 'support/fake_server.dart';

const _recipe = Recipe(
  mode: EditorMode.text,
  durationSec: 6,
  text: TextSpec(content: 'Should attendance be compulsory?'),
  background: Background.gradient(Color(0xFF0F2027), Color(0xFF2C5364), angle: 180),
);

void main() {
  group('attachments', () {
    test('exactly one of a question day or a room', () {
      expect(const PostAttachment(promptDay: '2026-10-21', label: 'x').roomId, isNull);
      expect(const PostAttachment(roomId: 'r1', label: 'x').promptDay, isNull);
    });

    test('a new opinion carries the question day or the room to the server', () async {
      final repo = FakeFeedRepository.sample(now: DateTime.utc(2026, 10, 10, 12));
      final feed = FeedController(repo, pollInterval: const Duration(milliseconds: 5));
      addTearDown(feed.dispose);
      await feed.compose(recipe: _recipe, title: 'T', attach: const PostAttachment(promptDay: '2026-10-21', label: 'q'));
      await feed.compose(recipe: _recipe, title: 'T', attach: const PostAttachment(roomId: 'r1', label: 'r'));
      await feed.compose(recipe: _recipe, title: 'T');
      expect(repo.composed.map((c) => (c['promptDay'], c['roomId'])), [('2026-10-21', null), (null, 'r1'), (null, null)]);
    });

    test('the editor sends its attachment, but never on a reply', () async {
      final repo = FakeFeedRepository.sample(now: DateTime.utc(2026, 10, 10, 12));
      final feed = FeedController(repo, pollInterval: const Duration(milliseconds: 5));
      addTearDown(feed.dispose);
      await feed.refresh();
      final root = EditorController(mode: EditorMode.text, attach: const PostAttachment(promptDay: '2026-10-21', label: 'Answer today\'s question'));
      addTearDown(root.dispose);
      expect(root.attach!.label, 'Answer today\'s question');

      final parent = feed.items.first.post;
      final reply = EditorController(
        mode: EditorMode.video,
        videoPath: '/tmp/a.mp4',
        videoSeconds: 12,
        parent: parent,
        parentAuthor: feed.items.first.actor,
        attach: const PostAttachment(promptDay: '2026-10-21', label: 'x'),
      );
      addTearDown(reply.dispose);
      expect(await reply.submit(feed), isTrue);
      expect(repo.composed.last['promptDay'], isNull, reason: 'a reply is never an answer to the question');

      final answer = EditorController(
        mode: EditorMode.video,
        videoPath: '/tmp/b.mp4',
        videoSeconds: 12,
        attach: const PostAttachment(promptDay: '2026-10-21', label: 'x'),
      );
      addTearDown(answer.dispose);
      answer.setTitle('My answer');
      expect(await answer.submit(feed), isTrue);
      expect(repo.composed.last['promptDay'], '2026-10-21');
    });

    test('over the wire: promptDay and roomId are form fields, and absent when not given', () async {
      final seen = <String, String>{};
      final api = ApiClient(
        baseUrl: 'http://test.invalid',
        client: MockClient((request) async {
          final text = utf8.decode(request.bodyBytes, allowMalformed: true);
          for (final name in ['promptDay', 'roomId']) {
            final m = RegExp('name="$name"\\r\\n\\r\\n([^\\r]+)').firstMatch(text);
            if (m != null) seen[name] = m.group(1)!;
          }
          return http.Response(
            jsonEncode({
              'type': 'POST',
              'actor': {'id': 'u', 'username': 'u', 'fullName': 'u', 'avatarUrl': null, 'isBot': false},
              'post': {
                'id': 'n1', 'kind': 'VIDEO', 'parentId': null, 'rootId': 'n1', 'depth': 0, 'title': 't', 'body': null, 'mediaUrl': null,
                'stance': 'PARENT', 'status': 'PROCESSING', 'summary': null, 'createdAt': '2026-10-21T10:00:00.000Z', 'likeCount': 0,
                'likedByMe': false, 'replyCount': 0, 'forCount': 0, 'againstCount': 0, 'promptDay': '2026-10-21',
              },
              'parent': null,
              'root': null,
              'createdAt': '2026-10-21T10:00:00.000Z',
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final repo = ApiFeedRepository(api);
      final item = await repo.compose(recipe: _recipe, title: 't', promptDay: '2026-10-21');
      expect(seen, {'promptDay': '2026-10-21'});
      expect(item.post.promptDay, '2026-10-21');
      seen.clear();
      await repo.compose(recipe: _recipe, title: 't', roomId: 'r1');
      expect(seen, {'roomId': 'r1'});
      seen.clear();
      await repo.compose(recipe: _recipe, title: 't');
      expect(seen, isEmpty);
    });
  });

  group('share link', () {
    tearDown(PublicLinks.forget);

    test('is the server\'s public address once it has said it, otherwise the server we talk to', () {
      PublicLinks.forget();
      expect(PublicLinks.known, isFalse);
      expect(PublicLinks.debate('abc'), '${ApiClient.defaultBaseUrl}/p/abc');
      PublicLinks.learn('https://forestapp.in/');
      expect(PublicLinks.known, isTrue);
      expect(PublicLinks.debate('abc'), 'https://forestapp.in/p/abc');
      PublicLinks.learn('  ');
      PublicLinks.learn(null);
      expect(PublicLinks.debate('abc'), 'https://forestapp.in/p/abc', reason: 'blank answers change nothing');
    });

    test('reading the server config teaches it', () async {
      PublicLinks.forget();
      final server = FakeServer()..json('GET /api/auth/config', {'signupChannel': 'email', 'publicBaseUrl': 'https://api.forestapp.in'});
      await AuthRepository(server.client()).config();
      expect(PublicLinks.debate('x1'), 'https://api.forestapp.in/p/x1');
    });
  });

  group('signing up with an invite code', () {
    FakeServer server() => FakeServer()
      ..json('POST /api/auth/email/send', {'sent': true, 'email': 'riya@example.com', 'resendInSec': 30})
      ..json('POST /api/auth/email/verify', {'verified': true, 'signupToken': 'su-e'})
      ..json('GET /api/auth/username-available', {'available': true})
      ..json('POST /api/auth/signup', {
        'token': 'login-1',
        'user': {'id': 'u1', 'username': 'riya_k', 'fullName': 'Riya K', 'avatarUrl': null, 'isBot': false},
      }, status: 201);

    Future<SignupController> toProfile(FakeServer s) async {
      final c = SignupController(AuthRepository(s.client()), usernameDebounce: const Duration(milliseconds: 5));
      await c.sendCode('riya@example.com');
      await c.verifyCode('123456');
      return c;
    }

    test('the code goes with the sign-up, and a blank one is left out', () async {
      final s = server();
      final c = await toProfile(s);
      await c.submit(fullName: 'Riya K', username: 'riya_k', dob: DateTime(2000, 5, 20), password: 'long-enough-pw', inviteCode: ' k7m2qxa ');
      expect(s.last('POST /api/auth/signup').json['inviteCode'], 'k7m2qxa');

      final s2 = server();
      final c2 = await toProfile(s2);
      await c2.submit(fullName: 'Riya K', username: 'riya_k', dob: DateTime(2000, 5, 20), password: 'long-enough-pw', inviteCode: '  ');
      expect(s2.last('POST /api/auth/signup').json.containsKey('inviteCode'), isFalse);
    });

    test('a wrong code is shown under the invite field and keeps the profile form', () async {
      final s = server()..json('POST /api/auth/signup', {'error': 'That invite code is not valid. Check it, or leave it blank', 'field': 'inviteCode'}, status: 400);
      final c = await toProfile(s);
      final result = await c.submit(fullName: 'Riya K', username: 'riya_k', dob: DateTime(2000, 5, 20), password: 'long-enough-pw', inviteCode: 'NOPE123');
      expect(result, isNull);
      expect(c.step, SignupStep.profile);
      expect(c.fieldErrors['inviteCode'], contains('not valid'));
    });
  });
}
