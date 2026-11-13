// ReelController: one player per slot, no leaks, honest failures. Fake players, no platform.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:forest_app/features/reels/reel_controller.dart';

class FakePlayer extends Fake implements VideoPlayerController {
  FakePlayer(this.uri);
  final Uri uri;
  VideoPlayerValue _value = const VideoPlayerValue(duration: Duration(seconds: 5));
  bool disposed = false;
  int plays = 0;
  bool failInit = false;
  Completer<void>? gate;

  @override
  VideoPlayerValue get value => _value;
  @override
  Future<void> initialize() async {
    await gate?.future;
    if (failInit) throw Exception('cannot open $uri');
    _value = _value.copyWith(isInitialized: true);
  }

  @override
  Future<void> setLooping(bool looping) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> seekTo(Duration position) async {}
  @override
  Future<void> play() async {
    plays++;
    _value = _value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async => _value = _value.copyWith(isPlaying: false);
  @override
  Future<void> dispose() async => disposed = true;
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

({ReelController controller, List<FakePlayer> made}) _make({bool Function(Uri)? failing, Completer<void>? gate}) {
  final made = <FakePlayer>[];
  final controller = ReelController(
    muteNotifier: ValueNotifier(false),
    playerFactory: (uri) {
      final p = FakePlayer(uri);
      if (failing != null && failing(uri)) p.failInit = true;
      if (gate != null) p.gate = gate;
      made.add(p);
      return p;
    },
  );
  return (controller: controller, made: made);
}

void main() {
  pauseResumeTests();
  insertSlotTests();
  test('a video that cannot be loaded throws, is removed, and can be tried again', () async {
    var broken = true;
    final made = <FakePlayer>[];
    final c = ReelController(
      muteNotifier: ValueNotifier(false),
      playerFactory: (u) => FakePlayer(u)..failInit = broken..let(made.add),
    );
    await expectLater(c.prime(0, 'http://x/a.mp4'), throwsA(isA<Exception>()));
    expect(c.controllerFor(0), isNull, reason: 'a dead player must not stay in the slot');
    expect(made.single.disposed, isTrue);

    broken = false; // network is back
    await c.prime(0, 'http://x/a.mp4');
    expect(made.length, 2, reason: 'prime tried again instead of returning early on the dead entry');
    expect(c.controllerFor(0)!.value.isInitialized, isTrue);
    c.dispose();
  });

  test('prime only plays the current page; neighbours wait', () async {
    final m = _make();
    await m.controller.prime(0, 'http://x/a.mp4');
    await m.controller.prime(1, 'http://x/b.mp4');
    expect(m.made[0].plays, 1);
    expect(m.made[1].plays, 0);
    m.controller.dispose();
  });

  test('priming the same slot twice makes one player', () async {
    final gate = Completer<void>();
    final m = _make(gate: gate);
    final a = m.controller.prime(0, 'http://x/a.mp4');
    final b = m.controller.prime(0, 'http://x/a.mp4');
    gate.complete();
    await Future.wait([a, b]);
    expect(m.made.length, 1);
    m.controller.dispose();
  });

  test('replaceAndPlay while a prime is loading: exactly one player survives and the other is disposed', () async {
    final gate = Completer<void>();
    final m = _make(gate: gate);
    final slow = m.controller.prime(0, 'http://x/old.mp4');
    final swap = m.controller.replaceAndPlay(0, 'http://x/new.mp4');
    gate.complete();
    await Future.wait([slow, swap]);
    final alive = m.made.where((p) => !p.disposed).toList();
    expect(alive.length, 1, reason: 'a leaked player would keep playing sound');
    expect(alive.single.uri.path, '/new.mp4');
    expect(m.controller.controllerFor(0), same(alive.single));
    expect(alive.single.plays, 1);
    m.controller.dispose();
  });

  test('replacing a loaded video disposes the old player at once', () async {
    final m = _make();
    await m.controller.prime(0, 'http://x/a.mp4');
    final first = m.made.single;
    await m.controller.replaceAndPlay(0, 'http://x/b.mp4');
    expect(first.disposed, isTrue);
    expect(m.controller.controllerFor(0)!.value.isPlaying, isTrue);
    m.controller.dispose();
  });

  test('replaceAndPlay that fails throws and leaves the slot empty for a retry', () async {
    final m = _make(failing: (u) => u.path == '/bad.mp4');
    await m.controller.prime(0, 'http://x/ok.mp4');
    await expectLater(m.controller.replaceAndPlay(0, 'http://x/bad.mp4'), throwsA(isA<Exception>()));
    expect(m.controller.controllerFor(0), isNull);
    m.controller.dispose();
  });

  test('a player that finishes loading after its page was purged is disposed, not leaked', () async {
    final gate = Completer<void>();
    final m = _make(gate: gate);
    final loading = m.controller.prime(5, 'http://x/far.mp4');
    m.controller.activatePage(0); // slot 5 is outside the window and is dropped while loading
    gate.complete();
    await loading;
    expect(m.made.single.disposed, isTrue);
    expect(m.controller.controllerFor(5), isNull);
    m.controller.dispose();
  });

  test('reset drops every player (a refreshed list must not reuse the old list\'s players)', () async {
    final m = _make();
    await m.controller.prime(0, 'http://x/a.mp4');
    await m.controller.prime(1, 'http://x/b.mp4');
    m.controller.savePosition('a', const Duration(seconds: 3));
    m.controller.reset();
    expect(m.made.every((p) => p.disposed), isTrue);
    expect(m.controller.controllerFor(0), isNull);
    expect(m.controller.getSavedPosition('a'), isNull);
    await m.controller.prime(0, 'http://x/new.mp4'); // the slot is free again
    expect(m.made.last.uri.path, '/new.mp4');
    m.controller.dispose();
  });

  test('dispose releases everything and later calls do nothing', () async {
    final m = _make();
    await m.controller.prime(0, 'http://x/a.mp4');
    m.controller.dispose();
    expect(m.made.single.disposed, isTrue);
    await m.controller.prime(1, 'http://x/b.mp4');
    expect(m.made.length, 1);
  });
}

extension _Let<T> on T {
  void let(void Function(T) f) => f(this);
}

void pauseResumeTests() {
  test('pauseCurrent reports whether it was playing, and resumeCurrent plays it again', () async {
    final r = _make();
    await r.controller.prime(0, 'a');
    r.controller.activatePage(0);
    final p = r.made.first;
    expect(p.value.isPlaying, isTrue);
    expect(r.controller.pauseCurrent(), isTrue);
    expect(p.value.isPlaying, isFalse);
    expect(r.controller.pauseCurrent(), isFalse, reason: 'already paused: nothing to resume later');
    r.controller.resumeCurrent();
    expect(p.value.isPlaying, isTrue);
    r.controller.dispose();
  });
}

void insertSlotTests() {
  test('insertSlot moves the players from that slot on one slot down, with their pages, and makes the moved page current', () async {
    final r = _make();
    final c = r.controller;
    await c.prime(0, 'a');
    await c.prime(1, 'b');
    await c.prime(2, 'c');
    c.activatePage(1);
    final b = c.controllerFor(1);
    expect(c.currentController, same(b));

    c.insertSlot(1, newCurrent: 2); // a page was put in above b: b is now page 2
    expect(c.controllerFor(0), same(r.made[0]), reason: 'pages above the new one do not move');
    expect(c.controllerFor(1), isNull, reason: 'the new page has no player yet');
    expect(c.controllerFor(2), same(r.made[1]));
    expect(c.controllerFor(3), same(r.made[2]));
    expect(c.currentIndex, 2);
    expect(c.currentController, same(b), reason: 'the player on screen is still the same one');
    expect(r.made.any((p) => p.disposed), isFalse, reason: 'nothing is thrown away when the list shifts');
    c.dispose();
  });

  test('insertSlot does not wake listeners, so none sees new page numbers against old ones', () async {
    final r = _make();
    await r.controller.prime(0, 'a');
    var calls = 0;
    r.controller.addListener(() => calls++);
    r.controller.insertSlot(0, newCurrent: 1);
    expect(calls, 0);
    r.controller.dispose();
  });
}
