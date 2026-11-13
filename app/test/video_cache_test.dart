// VideoCache: the session cache of loaded videos (real temp folder, mock HTTP).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:forest_app/services/video_cache.dart';

Future<({VideoCache cache, Directory dir, List<String> requests})> _make({
  int maxBytes = 300 * 1024 * 1024,
  Map<String, List<int>> bodies = const {},
  Map<String, int> statuses = const {},
}) async {
  final dir = Directory.systemTemp.createTempSync('forest_cache_test_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  final requests = <String>[];
  final client = MockClient((request) async {
    requests.add(request.url.toString());
    final status = statuses[request.url.toString()] ?? 200;
    return http.Response.bytes(bodies[request.url.toString()] ?? List.filled(10, 1), status);
  });
  final cache = VideoCache(directory: Directory('${dir.path}/c'), client: client, maxBytes: maxBytes);
  await cache.reset();
  return (cache: cache, dir: dir, requests: requests);
}

void main() {
  test('the file name is a short stable hash and keeps a sensible extension', () {
    final a = VideoCache.keyFor('http://x/uploads/a.mp4');
    expect(a, hasLength(16));
    expect(a, matches(RegExp(r'^[0-9a-f]{16}$')), reason: 'hex only: no minus sign from a signed 64-bit value');
    for (var i = 0; i < 200; i++) {
      expect(VideoCache.keyFor('http://x/$i.mp4'), matches(RegExp(r'^[0-9a-f]{16}$')));
    }
    expect(a, VideoCache.keyFor('http://x/uploads/a.mp4'));
    expect(a, isNot(VideoCache.keyFor('http://x/uploads/b.mp4')));
  });

  test('a download is saved, found afterwards, and not fetched again', () async {
    final t = await _make(bodies: {'http://x/a.webm': [1, 2, 3, 4, 5]});
    expect(t.cache.cachedFile('http://x/a.webm'), isNull);

    final file = await t.cache.prefetch('http://x/a.webm');
    expect(file, isNotNull);
    expect(file!.path, endsWith('.webm'));
    expect(file.readAsBytesSync(), [1, 2, 3, 4, 5]);
    expect(t.cache.cachedFile('http://x/a.webm')?.path, file.path);

    await t.cache.prefetch('http://x/a.webm');
    expect(t.requests, ['http://x/a.webm'], reason: 'second use comes from disk');
  });

  test('two callers asking for the same video share one download', () async {
    final t = await _make();
    final both = await Future.wait([t.cache.prefetch('http://x/a.mp4'), t.cache.prefetch('http://x/a.mp4')]);
    expect(both[0]!.path, both[1]!.path);
    expect(t.requests, hasLength(1));
  });

  test('a failed download returns null and leaves no half file behind', () async {
    final t = await _make(statuses: {'http://x/gone.mp4': 404});
    expect(await t.cache.prefetch('http://x/gone.mp4'), isNull);
    expect(t.cache.cachedFile('http://x/gone.mp4'), isNull);
    final leftovers = Directory('${t.dir.path}/c').listSync();
    expect(leftovers, isEmpty);
  });

  test('every app start begins with an empty cache (the cache lives one session)', () async {
    final t = await _make();
    await t.cache.prefetch('http://x/a.mp4');
    expect(Directory('${t.dir.path}/c').listSync(), hasLength(1));

    // A new VideoCache over the same folder = the next launch.
    final nextLaunch = VideoCache(directory: Directory('${t.dir.path}/c'), client: MockClient((_) async => http.Response('', 404)));
    await nextLaunch.reset();
    expect(Directory('${t.dir.path}/c').listSync(), isEmpty);
    expect(nextLaunch.cachedFile('http://x/a.mp4'), isNull);
  });

  test('over the size limit the least recently used video goes first', () async {
    final t = await _make(maxBytes: 100, bodies: {
      'http://x/a.mp4': List.filled(60, 1),
      'http://x/b.mp4': List.filled(60, 2),
      'http://x/c.mp4': List.filled(60, 3),
    });
    await t.cache.prefetch('http://x/a.mp4');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await t.cache.prefetch('http://x/b.mp4'); // 120 > 100: a (older) is deleted
    expect(t.cache.cachedFile('http://x/a.mp4'), isNull);
    expect(t.cache.cachedFile('http://x/b.mp4'), isNotNull);

    await Future<void>.delayed(const Duration(milliseconds: 40));
    t.cache.cachedFile('http://x/b.mp4'); // using b makes it the most recent
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await t.cache.prefetch('http://x/c.mp4');
    expect(t.cache.cachedFile('http://x/c.mp4'), isNotNull);
    expect(t.cache.cachedFile('http://x/b.mp4'), isNull, reason: 'b was older than the new c');
  });
}
