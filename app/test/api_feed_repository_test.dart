// ApiFeedRepository against a mock HTTP client: right URLs, right headers,
// real server fixtures in, typed models and ApiExceptions out.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:forest_app/data/api_feed_repository.dart';
import 'package:forest_app/data/feed_repository.dart';
import 'package:forest_app/models/feed_item.dart';
import 'package:forest_app/services/api_client.dart';

String _fixtureText(String name) => File('test/fixtures/$name').readAsStringSync();

http.Response _json(Object body, [int status = 200]) => http.Response(
      body is String ? body : jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

({ApiFeedRepository repo, List<http.Request> seen}) _setup(
  http.Response Function(http.Request) handler,
) {
  final seen = <http.Request>[];
  final client = MockClient((request) async {
    seen.add(request);
    return handler(request);
  });
  final api = ApiClient(baseUrl: 'http://api.test', devUser: 'me_dev', client: client);
  return (repo: ApiFeedRepository(api), seen: seen);
}

void main() {
  test('home: sends the dev header, limit and cursor, and parses the real response', () async {
    final t = _setup((_) => _json(_fixtureText('home_seed.json')));
    final page = await t.repo.home(cursor: 'abc', limit: 5);

    expect(t.seen.single.method, 'GET');
    expect(t.seen.single.url.path, '/api/home');
    expect(t.seen.single.url.queryParameters, {'limit': '5', 'cursor': 'abc'});
    expect(t.seen.single.headers['X-Dev-User'], 'me_dev');
    expect(page.items, hasLength(6));
    expect(page.nextCursor, isNull);
  });

  test('home: a malformed item is skipped, the rest still show', () async {
    final good = (jsonDecode(_fixtureText('home_seed.json')) as Map<String, dynamic>)['items'] as List;
    final t = _setup((_) => _json({
          'items': [good.first, {'type': 'NOT_A_REAL_TYPE'}],
          'nextCursor': 'next',
        }));
    final page = await t.repo.home();
    expect(page.items, hasLength(1));
    expect(page.nextCursor, 'next');
  });

  test('a 401 becomes an ApiException carrying the server message', () async {
    final t = _setup((_) => _json({'error': 'Sign in required'}, 401));
    await expectLater(
      t.repo.home(),
      throwsA(isA<ApiException>()
          .having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)
          .having((e) => e.message, 'message', 'Sign in required')),
    );
  });

  test('a network failure becomes a readable ApiException', () async {
    final api = ApiClient(
      baseUrl: 'http://api.test',
      devUser: 'me_dev',
      client: MockClient((_) async => throw http.ClientException('boom')),
    );
    await expectLater(
      ApiFeedRepository(api).home(),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains("Can't reach"))),
    );
  });

  test('like uses POST, unlike uses DELETE, and both parse the answer', () async {
    final t = _setup((r) => _json({'liked': r.method == 'POST', 'likeCount': 4}));
    final liked = await t.repo.setLiked('p1', true);
    final unliked = await t.repo.setLiked('p1', false);
    expect(t.seen.map((r) => '${r.method} ${r.url.path}'),
        ['POST /api/posts/p1/like', 'DELETE /api/posts/p1/like']);
    expect(liked.liked, isTrue);
    expect(unliked.liked, isFalse);
  });

  test('suggested users: GET with a limit, shaped like the server answers', () async {
    final t = _setup((_) => _json({
          'users': [
            {
              'user': {'id': 'u1', 'username': 'kabir_m', 'fullName': 'Kabir Mehta', 'avatarUrl': null, 'isBot': true},
              'followerCount': 3,
              'postCount': 12,
            },
            {'broken': true},
          ],
        }));
    final people = await t.repo.suggestedUsers(limit: 7);

    expect(t.seen.single.method, 'GET');
    expect(t.seen.single.url.path, '/api/users/suggested');
    expect(t.seen.single.url.queryParameters, {'limit': '7'});
    expect(people, hasLength(1), reason: 'a malformed row is skipped, not fatal');
    expect(people.single.user.username, 'kabir_m');
    expect(people.single.user.isBot, isTrue);
    expect(people.single.followerCount, 3);
    expect(people.single.postCount, 12);
  });

  test('retry: POST /api/posts/:id/retry returns the item, and a 410 keeps its message', () async {
    final t = _setup((r) => r.url.path.contains('gone')
        ? _json({'error': 'The video file is gone. Upload it again.'}, 410)
        : _json(_fixtureText('post_detail_seed.json')));
    final item = await t.repo.retryPost('p1');
    expect(t.seen.single.method, 'POST');
    expect(t.seen.single.url.path, '/api/posts/p1/retry');
    expect(item.post.id, isNotEmpty);

    await expectLater(
      t.repo.retryPost('gone'),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 410)
          .having((e) => e.message, 'message', 'The video file is gone. Upload it again.')),
    );
  });

  test('report sends the wire reason; block and follow use the user id', () async {
    final t = _setup((r) => _json({'ok': true}, r.url.path.endsWith('/report') ? 201 : 200));
    await t.repo.report('p1', ReportReason.misinformation);
    await t.repo.setBlocked('u9', true);
    await t.repo.setBlocked('u9', false);
    await t.repo.setFollowing('u9', true);

    expect(jsonDecode(t.seen[0].body), {'reason': 'MISINFORMATION'});
    expect(t.seen.map((r) => '${r.method} ${r.url.path}').skip(1), [
      'POST /api/users/u9/block',
      'DELETE /api/users/u9/block',
      'POST /api/users/u9/follow',
    ]);
  });

  test('text reply is multipart with kind, parentId and body', () async {
    final t = _setup((_) => _json(_fixtureText('post_detail_seed.json'), 201));
    final item = await t.repo.replyText(parentId: 'p1', body: 'I disagree');
    final body = t.seen.single.body;
    expect(t.seen.single.method, 'POST');
    expect(t.seen.single.headers['content-type'], startsWith('multipart/form-data'));
    expect(body, contains('name="kind"'));
    expect(body, contains('TEXT'));
    expect(body, contains('name="parentId"'));
    expect(body, contains('I disagree'));
    expect(item, isA<FeedItem>());
  });

  test('mediaUrl resolves relative paths against the base URL', () {
    final t = _setup((_) => _json({}));
    expect(t.repo.mediaUrl('/uploads/a.mp4'), 'http://api.test/uploads/a.mp4');
    expect(t.repo.mediaUrl('https://cdn.test/a.mp4'), 'https://cdn.test/a.mp4');
  });
}
