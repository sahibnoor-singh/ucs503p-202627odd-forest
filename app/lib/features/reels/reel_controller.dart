import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import 'sides_heard.dart';

/// mixWithOthers: our players must not fight over Android audio focus (a second player asking for it pauses the first).
VideoPlayerController _defaultPlayer(Uri url) =>
    VideoPlayerController.networkUrl(url, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));

/// Manages VideoPlayerController lifecycle across Reels pages.
/// Retains at most 3 active controllers (previous, current, next) to conserve memory.
class ReelController extends ChangeNotifier {
  /// [playerFactory] is for tests (fake players); the app streams each video from its URL.
  ReelController({required this.muteNotifier, VideoPlayerController Function(Uri url)? playerFactory})
      : _newPlayer = playerFactory ?? _defaultPlayer;

  final VideoPlayerController Function(Uri url) _newPlayer;

  final ValueNotifier<bool> muteNotifier;

  /// Which sides of each debate were watched during this visit (drives the "you have heard both sides" note).
  final SidesHeard sidesHeard = SidesHeard();

  /// Authors the viewer followed or unfollowed from a reel in this visit (author id -> following now), so every reel of that person agrees.
  final Map<String, bool> followState = {};
  final Map<int, VideoPlayerController> _controllers = {};
  final Map<String, Duration> _savedPositions = {};
  int _currentIndex = 0;
  bool _disposed = false;

  int get currentIndex => _currentIndex;
  VideoPlayerController? get currentController => _controllers[_currentIndex];

  VideoPlayerController? controllerFor(int index) => _controllers[index];

  /// Initialize and buffer a video for [index] if not already present.
  /// Throws when the video cannot be loaded (offline, 404, bad file): the dead player is removed first,
  /// so the caller can show "tap to retry" and a retry really tries again.
  Future<void> prime(int index, String url, {String? videoId}) async {
    if (_disposed || _controllers.containsKey(index)) return;
    final controller = _newPlayer(Uri.parse(url));
    _controllers[index] = controller; // registered before any await, so nobody else creates a second one
    await _start(index, controller, videoId: videoId, playIfCurrent: true);
  }

  /// Replace the controller for [index] with a new video [url] and start playing immediately.
  Future<void> replaceAndPlay(int index, String url, {String? videoId}) async {
    if (_disposed) return;
    final controller = _newPlayer(Uri.parse(url));
    // Swap synchronously: with an await in between, a concurrent prime() for the same index would create its
    // own player, which this call would then overwrite and never dispose (it would keep playing sound).
    final old = _controllers[index];
    _controllers[index] = controller;
    if (old != null) {
      unawaited(old.dispose().catchError((_) {})); // dispose() also stops playback
    }
    notifyListeners();
    await _start(index, controller, videoId: videoId, playIfCurrent: false, alwaysPlay: true);
  }

  Future<void> _start(
    int index,
    VideoPlayerController controller, {
    String? videoId,
    required bool playIfCurrent,
    bool alwaysPlay = false,
  }) async {
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(muteNotifier.value ? 0 : 1);
      if (videoId != null && _savedPositions.containsKey(videoId)) {
        await controller.seekTo(_savedPositions[videoId]!);
      }
      // Superseded (another video took this slot) or purged while loading: this player is garbage now.
      if (_disposed || !identical(_controllers[index], controller)) {
        await controller.dispose();
        return;
      }
      if (alwaysPlay || (playIfCurrent && index == _currentIndex)) await controller.play();
      notifyListeners();
    } on Object catch (e) {
      debugPrint('[ReelController] Failed to load video for index $index: $e');
      if (identical(_controllers[index], controller)) _controllers.remove(index);
      try {
        await controller.dispose();
      } on Object catch (_) {/* already gone */}
      if (!_disposed) notifyListeners();
      rethrow;
    }
  }

  /// Drops every player and remembered position. Call when the list of videos is replaced (pull to refresh),
  /// otherwise slot 0 would keep playing the old list's first video.
  void reset() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    _savedPositions.clear();
    if (!_disposed) notifyListeners();
  }

  /// Switch the active visible reel. Plays [index], pauses all others,
  /// and purges controllers outside the [index - 1, index + 1] window.
  void activatePage(int index, {List<String>? videoIds}) {
    if (_disposed) return;
    _currentIndex = index;

    // Save playback position of the previous page
    _controllers.forEach((idx, c) {
      if (c.value.isInitialized && videoIds != null && idx < videoIds.length) {
        _savedPositions[videoIds[idx]] = c.value.position;
      }
    });

    // Pause all except active
    _controllers.forEach((idx, c) {
      if (idx == index) {
        if (c.value.isInitialized && !c.value.isPlaying) {
          c.play();
        }
      } else {
        if (c.value.isPlaying) {
          c.pause();
        }
      }
    });

    // Prune distant controllers (keep only index - 1, index, index + 1)
    final keysToRemove = <int>[];
    _controllers.forEach((idx, c) {
      if ((idx - index).abs() > 1) {
        c.dispose();
        keysToRemove.add(idx);
      }
    });
    for (final k in keysToRemove) {
      _controllers.remove(k);
    }

    notifyListeners();
  }

  /// A page was put in at [at], above the one that was there: every player from [at] on moves one slot down with its page, and the
  /// current page is now [newCurrent]. Says nothing to listeners: the caller rebuilds the pages in the same frame, and a listener that
  /// ran in between would see old page numbers against the new current one.
  void insertSlot(int at, {required int newCurrent}) {
    if (_disposed) return;
    final moved = <int, VideoPlayerController>{};
    _controllers.forEach((slot, c) => moved[slot >= at ? slot + 1 : slot] = c);
    _controllers
      ..clear()
      ..addAll(moved);
    _currentIndex = newCurrent;
  }

  /// Pauses the current reel and reports whether it was playing (so the caller can resume it later).
  bool pauseCurrent() {
    final c = currentController;
    if (c == null || !c.value.isPlaying) return false;
    c.pause();
    return true;
  }

  void resumeCurrent() {
    final c = currentController;
    if (_disposed || c == null || !c.value.isInitialized || c.value.isPlaying) return;
    c.play();
  }

  void togglePlayPause() {
    final c = currentController;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
    notifyListeners();
  }

  void toggleMute() {
    muteNotifier.value = !muteNotifier.value;
    final vol = muteNotifier.value ? 0.0 : 1.0;
    _controllers.forEach((_, c) {
      c.setVolume(vol);
    });
    notifyListeners();
  }

  void savePosition(String videoId, Duration position) {
    _savedPositions[videoId] = position;
  }

  Duration? getSavedPosition(String videoId) => _savedPositions[videoId];

  @override
  void dispose() {
    _disposed = true;
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    super.dispose();
  }
}
