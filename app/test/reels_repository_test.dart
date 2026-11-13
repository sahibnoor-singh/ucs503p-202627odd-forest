import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:forest_app/features/reels/reels_repository.dart';
import 'package:forest_app/models/video.dart';
import 'package:forest_app/services/api_client.dart';

import 'support/fake_server.dart';

Map<String, dynamic> _video(String id, {String stance = 'PARENT', String? parent}) => {
      'id': id, 'title': 'Title $id', 'caption': 'Title $id', 'filename': '$id.mp4', 'status': 'ready',
      'role': parent == null ? 'PARENT' : 'CHILD', 'parentVideoId': parent, 'stance': stance, 'credibility': 70,
      'durationS': 0, 'userId': 'aman', 'userName': 'aman', 'createdAt': '2026-10-10T10:00:00.000Z',
      'likeCount': 2, 'replyCount': 1, 'forCount': 1, 'againstCount': 0, 'viewerSide': null, 'liked': false,
      'transcript': {'overallSummary': 'sum'},
    };

void main() {
  test('talks to the app server, never to a hard-coded site, and sends the login', () async {
    final server = FakeServer()..json('GET /api/videos/feed', {'videos': [_video('a')], 'nextCursor': null});
    final repo = ReelsRepository(server.client(token: () => 'tok'));
    await repo.getFeed();
    final seen = server.last('GET /api/videos/feed');
    expect(seen.uri.host, 'test.invalid');
    expect(seen.headers['Authorization'], 'Bearer tok');
    expect(seen.uri.queryParameters, {'limit': '10'});
  });

  test('feed: parses videos, passes the cursor back, skips unreadable rows', () async {
    final server = FakeServer()
      ..json('GET /api/videos/feed', {
        'videos': [_video('a'), {'id': 5, 'nonsense': true}, _video('b')],
        'nextCursor': 'next-1',
      });
    final repo = ReelsRepository(server.client());
    final page = await repo.getFeed(cursor: 'prev-1', limit: 3);
    expect(page.videos.map((v) => v.id), ['a', 'b']);
    expect(page.nextCursor, 'next-1');
    expect(server.last('GET /api/videos/feed').uri.queryParameters, {'limit': '3', 'cursor': 'prev-1'});
    expect(page.videos.first.summary, 'sum');
  });

  test('NO pretend content: a down or failing server is an error, never demo videos', () async {
    final server = FakeServer()
      ..json('GET /api/videos/feed', {'error': 'Internal server error'}, status: 500)
      ..json('GET /api/videos/x/tree', {'error': 'Not found'}, status: 404);
    final repo = ReelsRepository(server.client());
    await expectLater(repo.getFeed(), throwsA(isA<ApiException>()));
    await expectLater(repo.getTree('x'), throwsA(isA<ApiException>()));
    await expectLater(repo.getReplies('x'), throwsA(isA<ApiException>()));
  });

  test('replies, strongest reply and tree use the documented paths and sides', () async {
    final server = FakeServer()
      ..json('GET /api/videos/r1/replies', [_video('c1', stance: 'FOR', parent: 'r1')])
      ..json('GET /api/videos/r1/strongest-reply', {'reply': _video('c1', stance: 'FOR', parent: 'r1')})
      ..json('GET /api/videos/r2/strongest-reply', {'reply': null})
      ..json('GET /api/videos/r1/tree', [_video('r1'), _video('c1', parent: 'r1')]);
    final repo = ReelsRepository(server.client());
    expect((await repo.getReplies('r1', side: 'for')).single.id, 'c1');
    expect(server.last('GET /api/videos/r1/replies').uri.queryParameters, {'side': 'FOR'});
    expect((await repo.getStrongestReply('r1', 'for'))!.id, 'c1');
    expect(await repo.getStrongestReply('r2', 'against'), isNull);
    expect((await repo.getTree('r1')).length, 2);
  });

  test('ids are url-encoded so one cannot reach another path', () async {
    final server = FakeServer()..json('GET /api/videos/a%2F..%2Fb', {'error': 'no'}, status: 404);
    final repo = ReelsRepository(server.client());
    await expectLater(repo.getVideo('a/../b'), throwsA(isA<ApiException>()));
    expect(server.seen.single.uri.toString(), contains('a%2F..%2Fb'));
  });

  test('like and unlike return the server count and propagate failures', () async {
    final server = FakeServer()
      ..json('PUT /api/videos/v/like', {'liked': true, 'likeCount': 4})
      ..json('DELETE /api/videos/v/like', {'liked': false, 'likeCount': 3})
      ..json('PUT /api/videos/gone/like', {'error': 'Video not found'}, status: 404);
    final repo = ReelsRepository(server.client());
    expect(await repo.setLike('v'), 4);
    expect(await repo.deleteLike('v'), 3);
    await expectLater(repo.setLike('gone'), throwsA(isA<ApiException>()));
  });

  test('opinion: sends the side and returns the best reply from that side', () async {
    final server = FakeServer()
      ..json('PUT /api/videos/v/opinion', {'side': 'AGAINST', 'strongestReply': _video('c', stance: 'AGAINST', parent: 'v')})
      ..json('DELETE /api/videos/v/opinion', {'ok': true});
    final repo = ReelsRepository(server.client());
    final r = await repo.setOpinion('v', 'AGAINST');
    expect(server.last('PUT /api/videos/v/opinion').json, {'side': 'AGAINST'});
    expect(r.strongestReply!.id, 'c');
    await repo.deleteOpinion('v');
    expect(server.count('DELETE /api/videos/v/opinion'), 1);
  });

  test('interaction pings are best effort: they send only what is set and never throw', () async {
    final server = FakeServer()..json('POST /api/videos/v/interactions', {'error': 'Sign in required'}, status: 401);
    final repo = ReelsRepository(server.client());
    await repo.recordInteraction(videoId: 'v', watchDurationMs: 3000, completed: false);
    expect(server.last('POST /api/videos/v/interactions').json, {'watchDurationMs': 3000, 'completed': false});
    await repo.recordView('v', 100, true); // still no exception
    expect(server.count('POST /api/videos/v/interactions'), 2);
  });

  test('reset profile reports whether it worked; report throws when it was not saved', () async {
    final server = FakeServer()
      ..json('POST /api/videos/profile/reset', {'ok': true})
      ..json('POST /api/videos/v/report', {'error': "You can't report your own post"}, status: 400);
    final repo = ReelsRepository(server.client());
    expect(await repo.resetUserProfile(), isTrue);
    await expectLater(
      repo.reportVideo('v', 'OTHER'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains("can't report"))),
    );
    expect(await ReelsRepository(FakeServer().client()).resetUserProfile(), isFalse);
  });

  test('video url: served by the same server, file name encoded, absolute links untouched', () {
    final repo = ReelsRepository(FakeServer().client());
    Video v(String f) => Video.fromJson({'id': '1', 'filename': f, 'stance': 'PARENT'});
    expect(repo.videoUrl(v('a b.mp4')), 'http://test.invalid/uploads/a%20b.mp4');
    expect(repo.videoUrl(v('https://cdn.example/x.mp4')), 'https://cdn.example/x.mp4');
  });

  test('upload: posts to /api/posts as a reply with the right fields and maps the answer', () async {
    final server = FakeServer()
      ..on('POST /api/posts', (s) => http.Response(
            '{"type":"VIDEO_REPLY","actor":{"username":"me_dev"},"post":{"id":"p1","status":"PROCESSING","parentId":"root1","stance":"UNRESOLVED","mediaUrl":"/uploads/clip.mp4","createdAt":"t"}}',
            201,
            headers: {'content-type': 'application/json'},
          ));
    final dir = Directory.systemTemp.createTempSync('upload-test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/clip.mp4')..writeAsBytesSync([1, 2, 3]);

    final video = await ReelsRepository(server.client()).uploadVideo(file, title: 'ignored for replies', parentVideoId: 'root1');
    final sent = server.last('POST /api/posts');
    expect(sent.headers['content-type'], startsWith('multipart/form-data'));
    expect(sent.body, contains('name="kind"'));
    expect(sent.body, contains('VIDEO'));
    expect(sent.body, contains('name="parentId"'));
    expect(sent.body, isNot(contains('ignored for replies'))); // replies carry no title
    expect(video.id, 'p1');
    expect(video.status, 'processing');
    expect(video.role, 'CHILD');
    expect(video.filename, 'clip.mp4');
    expect(video.userName, 'me_dev');
  });
}
