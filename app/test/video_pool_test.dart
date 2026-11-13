// VideoPool: players stay ready and are shared, with fake players (no platform).

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:forest_app/services/video_cache.dart';
import 'package:forest_app/services/video_pool.dart';

class FakePlayer extends Fake implements VideoPlayerController {
  FakePlayer(this.url, this.file);

  final String url;
  final File? file;
  VideoPlayerValue _value = const VideoPlayerValue(duration: Duration(seconds: 5));
  bool disposed = false;
  bool looping = false;
  double volume = -1;
  int plays = 0;
  int pauses = 0;
  bool failInit = false;
  Completer<void>? gate;

  @override
  VideoPlayerValue get value => _value;

  @override
  Future<void> initialize() async {
    await gate?.future;
    if (failInit) throw Exception('cannot open $url');
    _value = _value.copyWith(isInitialized: true);
  }

  @override
  Future<void> setLooping(bool looping) async => this.looping = looping;

  @override
  Future<void> setVolume(double volume) async => this.volume = volume;

  @override
  Future<void> play() async {
    plays++;
    _value = _value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    pauses++;
    _value = _value.copyWith(isPlaying: false);
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class RecordingCache extends VideoCache {
  RecordingCache() : super(directory: Directory.systemTemp);

  final Map<String, File> cached = {};
  final List<String> prefetched = [];

  @override
  Future<void> reset() async {}

  @override
  File? cachedFile(String url) => cached[url];

  @override
  Future<File?> prefetch(String url) async {
    prefetched.add(url);
    return cached[url];
  }
}

({VideoPool pool, RecordingCache cache, List<FakePlayer> made}) _make({
  int capacity = 5,
  void Function(FakePlayer)? configure,
}) {
  final cache = RecordingCache();
  final made = <FakePlayer>[];
  final pool = VideoPool(cache, capacity: capacity, factory: (url, file) {
    final p = FakePlayer(url, file);
    configure?.call(p);
    made.add(p);
    return p;
  });
  addTearDown(pool.dispose);
  return (pool: pool, cache: cache, made: made);
}

void main() {
  test('a new video streams at once and is saved for next time only once it plays', () async {
    final t = _make();
    final player = await t.pool.acquire('http://x/a.mp4', 'h1');
    expect(player, isNotNull);
    expect((player! as FakePlayer).file, isNull, reason: 'not cached yet: stream, do not wait for a download');
    expect(t.cache.prefetched, isEmpty, reason: 'merely being close to the screen does not download it a second time');
    t.pool.setPlaying('http://x/a.mp4', 'h1', true);
    expect(t.cache.prefetched, ['http://x/a.mp4'], reason: 'download for next time');
    expect(player.value.isInitialized, isTrue);
    expect((player as FakePlayer).looping, isTrue);
    expect(player.volume, 0, reason: 'starts muted');
  });

  test('a video seen before opens from its cached file', () async {
    final t = _make();
    final file = File('${Directory.systemTemp.path}/cached.mp4');
    t.cache.cached['http://x/a.mp4'] = file;
    final player = await t.pool.acquire('http://x/a.mp4', 'h1') as FakePlayer;
    expect(player.file?.path, file.path);
    expect(t.cache.prefetched, isEmpty);
  });

  test('the same video in two places is one shared player', () async {
    final t = _make();
    final a = await t.pool.acquire('http://x/a.mp4', 'card');
    final b = await t.pool.acquire('http://x/a.mp4', 'viewer');
    expect(identical(a, b), isTrue);
    expect(t.made, hasLength(1));
    expect(identical(t.pool.peek('http://x/a.mp4'), a), isTrue);
  });

  test('letting go keeps the player (with its last frame) ready for scrolling back', () async {
    final t = _make();
    final first = await t.pool.acquire('http://x/a.mp4', 'card');
    t.pool.release('http://x/a.mp4', 'card');
    expect((first! as FakePlayer).disposed, isFalse);

    // Scroll back: the ready player is available immediately, no new one is built.
    expect(identical(t.pool.peek('http://x/a.mp4'), first), isTrue);
    final again = await t.pool.acquire('http://x/a.mp4', 'card');
    expect(identical(again, first), isTrue);
    expect(t.made, hasLength(1));
  });

  test('over capacity the least recently used idle player is disposed', () async {
    final t = _make(capacity: 2);
    for (final id in ['a', 'b', 'c']) {
      await t.pool.acquire('http://x/$id.mp4', id);
      t.pool.release('http://x/$id.mp4', id);
    }
    final byUrl = {for (final p in t.made) p.url: p};
    expect(byUrl['http://x/a.mp4']!.disposed, isTrue, reason: 'oldest idle goes');
    expect(byUrl['http://x/b.mp4']!.disposed, isFalse);
    expect(byUrl['http://x/c.mp4']!.disposed, isFalse);
    expect(t.pool.has('http://x/a.mp4'), isFalse);
    expect(t.pool.size, 2);
  });

  test('a player somebody is holding is never taken away', () async {
    final t = _make(capacity: 2);
    for (final id in ['a', 'b', 'c']) {
      await t.pool.acquire('http://x/$id.mp4', id); // all three held
    }
    expect(t.pool.size, 3, reason: 'nothing is idle, so nothing can be evicted');
    expect(t.made.any((p) => p.disposed), isFalse);

    t.pool.release('http://x/a.mp4', 'a'); // now a is idle and over capacity
    expect(t.made.firstWhere((p) => p.url == 'http://x/a.mp4').disposed, isTrue);
  });

  test('a player plays while any holder wants it, and pauses when none do', () async {
    final t = _make();
    const url = 'http://x/a.mp4';
    final p = await t.pool.acquire(url, 'card') as FakePlayer;
    await t.pool.acquire(url, 'viewer');

    t.pool.setPlaying(url, 'card', true);
    expect(p.value.isPlaying, isTrue);
    t.pool.setPlaying(url, 'viewer', true);
    t.pool.setPlaying(url, 'card', false); // the viewer still wants it
    expect(p.value.isPlaying, isTrue);
    expect(p.pauses, 0);
    t.pool.setPlaying(url, 'viewer', false);
    expect(p.value.isPlaying, isFalse);
    expect(p.plays, 1, reason: 'no redundant play calls');
  });

  test('wanting to play before the video is ready starts it once it is', () async {
    final gate = Completer<void>();
    final t = _make(configure: (p) => p.gate = gate);
    const url = 'http://x/a.mp4';
    final pending = t.pool.acquire(url, 'card');
    t.pool.setPlaying(url, 'card', true);
    expect(t.pool.peek(url), isNull);
    gate.complete();
    final p = await pending as FakePlayer;
    expect(p.value.isPlaying, isTrue);
  });

  test('one mute switch for every player, old and new', () async {
    final t = _make();
    final a = await t.pool.acquire('http://x/a.mp4', 'h') as FakePlayer;
    t.pool.setMuted(false);
    expect(a.volume, 1);
    final b = await t.pool.acquire('http://x/b.mp4', 'h') as FakePlayer;
    expect(b.volume, 1, reason: 'a player created after unmuting starts with sound');
    t.pool.setMuted(true);
    expect([a.volume, b.volume], [0, 0]);
  });

  test('a video that cannot be opened gives null, is forgotten, and can be retried', () async {
    var attempts = 0;
    final t = _make(configure: (p) => p.failInit = ++attempts == 1);
    const url = 'http://x/a.mp4';
    expect(await t.pool.acquire(url, 'card'), isNull);
    expect(t.made.single.disposed, isTrue, reason: 'the broken player is cleaned up');
    expect(t.pool.has(url), isFalse);

    final retry = await t.pool.acquire(url, 'card');
    expect(retry, isNotNull);
    expect(t.made, hasLength(2));
  });

  test('letting go of a video that is still loading keeps it for later', () async {
    final gate = Completer<void>();
    final t = _make(configure: (p) => p.gate = gate);
    const url = 'http://x/a.mp4';
    final pending = t.pool.acquire(url, 'card');
    t.pool.release(url, 'card'); // scrolled away before it finished
    gate.complete();
    final p = await pending as FakePlayer;
    expect(p.disposed, isFalse);
    expect(identical(t.pool.peek(url), p), isTrue);
  });

  test('disposing the pool disposes every player', () async {
    final t = _make();
    await t.pool.acquire('http://x/a.mp4', 'h');
    await t.pool.acquire('http://x/b.mp4', 'h');
    t.pool.dispose();
    expect(t.made.every((p) => p.disposed), isTrue);
  });
}
