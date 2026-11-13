import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:video_player/video_player.dart';

import 'video_cache.dart';

/// Builds the player for [url]; [file] is the cached copy when there is one.
typedef PlayerFactory = VideoPlayerController Function(String url, File? file);

/// Our players never need to own the phone's audio focus: only one plays at a time, and a second player asking for
/// focus would make Android pause the first one mid-sentence (the "audio breaks" bug).
final _options = VideoPlayerOptions(mixWithOthers: true);

VideoPlayerController _defaultFactory(String url, File? file) =>
    file != null ? VideoPlayerController.file(file, videoPlayerOptions: _options)
        : VideoPlayerController.networkUrl(Uri.parse(url), videoPlayerOptions: _options);

/// Keeps the last few video players alive and ready, keyed by URL, so that a
/// reel you scrolled past shows its last frame instead of going black, a reel
/// just below the screen has already loaded by the time you reach it, and the
/// same reel in another place (the full-screen viewer, a quoted copy) starts at
/// once from the same player. Videos load through [VideoCache], so a reel seen
/// once in this session also opens from disk.
///
/// Widgets *acquire* a URL while they might be seen, say whether they want it
/// *playing*, and *release* it when they are far away; the pool disposes the
/// least recently used players nobody holds once it has more than [capacity].
class VideoPool {
  VideoPool(
    this.cache, {
    this.capacity = 3,
    PlayerFactory? factory,
  }) : _factory = factory ?? _defaultFactory;

  final VideoCache cache;
  final int capacity;
  final PlayerFactory _factory;

  // Insertion order = least recently used first.
  final LinkedHashMap<String, _Entry> _entries = LinkedHashMap();
  bool _muted = true;
  bool _disposed = false;

  int get size => _entries.length;
  bool has(String url) => _entries.containsKey(url);

  /// The ready player for [url], if the pool already has one.
  VideoPlayerController? peek(String url) => _entries[url]?.controller;

  /// Holds [url] for [holder]. Completes with the ready player, or null when
  /// the video cannot be loaded.
  Future<VideoPlayerController?> acquire(String url, Object holder) {
    final entry = _entries.remove(url) ?? _Entry(url);
    _entries[url] = entry; // most recently used
    entry.holders.add(holder);
    entry.ready ??= _open(entry);
    _evict();
    return entry.ready!;
  }

  Future<VideoPlayerController?> _open(_Entry entry) async {
    // A video seen before opens from disk. A new one starts streaming at once
    // (waiting for a whole download would leave a black frame for seconds). It is
    // saved for next time only once it actually plays (see setPlaying): a video that
    // is merely close to the screen and scrolled past would otherwise be downloaded
    // twice at once (streamed and saved) for nothing.
    final file = cache.cachedFile(entry.url);
    final controller = _factory(entry.url, file);
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0 : 1);
    } on Object {
      await controller.dispose();
      // Forget it, so the next acquire tries again.
      if (identical(_entries[entry.url], entry)) _entries.remove(entry.url);
      return null;
    }
    if (_disposed) {
      await controller.dispose();
      return null;
    }
    entry.controller = controller;
    _applyPlayback(entry);
    return controller;
  }

  /// Says whether [holder] wants [url] playing. It plays while any holder does.
  void setPlaying(String url, Object holder, bool playing) {
    final entry = _entries[url];
    if (entry == null) return;
    final changed = playing ? entry.players.add(holder) : entry.players.remove(holder);
    if (!changed) return;
    if (playing) {
      if (cache.cachedFile(url) == null) unawaited(cache.prefetch(url)); // saved for next time, now that it is being watched
      _entries.remove(url);
      _entries[url] = entry;
    }
    _applyPlayback(entry);
  }

  /// [holder] no longer needs [url] soon. The player stays in the pool.
  void release(String url, Object holder) {
    final entry = _entries[url];
    if (entry == null) return;
    entry.holders.remove(holder);
    entry.players.remove(holder);
    _applyPlayback(entry);
    _evict();
  }

  /// One mute switch for every video.
  void setMuted(bool muted) {
    if (_muted == muted) return;
    _muted = muted;
    for (final e in _entries.values) {
      e.controller?.setVolume(muted ? 0 : 1);
    }
  }

  void _applyPlayback(_Entry entry) {
    final c = entry.controller;
    if (c == null || !c.value.isInitialized) return;
    final wantsPlay = entry.players.isNotEmpty;
    if (wantsPlay && !c.value.isPlaying) {
      c.play();
    } else if (!wantsPlay && c.value.isPlaying) {
      c.pause();
    }
  }

  void _evict() {
    while (_entries.length > capacity) {
      final victim = _entries.values.where((e) => e.holders.isEmpty).firstOrNull;
      if (victim == null) return; // everything is in use
      _entries.remove(victim.url);
      final c = victim.controller;
      if (c != null) {
        c.pause();
        c.dispose();
      } else {
        victim.ready?.then((c) => c?.dispose());
      }
    }
  }

  void dispose() {
    _disposed = true;
    for (final e in _entries.values) {
      e.controller?.dispose();
    }
    _entries.clear();
  }
}

class _Entry {
  _Entry(this.url);

  final String url;
  VideoPlayerController? controller;
  Future<VideoPlayerController?>? ready;
  final Set<Object> holders = {};
  final Set<Object> players = {};
}
