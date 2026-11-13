import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// How a feed video sits relative to the scroll viewport.
class MediaProximity {
  const MediaProximity({required this.visible, required this.near});

  static const none = MediaProximity(visible: 0, near: false);

  /// 0.0 (not on screen) to 1.0 (fully inside the viewport).
  final double visible;

  /// On screen, or close enough to start loading: up to half a screen below and
  /// a fifth of a screen above.
  final bool near;
}

/// Something on screen that can report where it sits in the viewport.
abstract interface class ReelFocusMember {
  Object get focusKey;

  MediaProximity measure();
}

/// Decides which feed video plays and which ones get loaded. Rule from the
/// plan (§2.5): only one reel plays at a time, the most visible one, and only
/// when more than about 45% of it is on screen. Videos that are [near] get a
/// player ahead of time, so by the time you scroll to them they are ready (and
/// the last ones you passed keep theirs, see VideoPool).
class ReelFocus extends ChangeNotifier {
  static const double playThreshold = 0.45;

  final Set<ReelFocusMember> _members = {};
  final Set<Object> _near = {};
  Object? _focused;
  int _suspended = 0;
  bool _scheduled = false;
  bool _disposed = false;

  /// The key that should be playing, or null (nothing qualifies, or suspended).
  Object? get focusedKey => _suspended > 0 ? null : _focused;

  bool isNear(Object key) => _near.contains(key);

  void register(ReelFocusMember member) {
    _members.add(member);
    scheduleUpdate();
  }

  void unregister(ReelFocusMember member) {
    _members.remove(member);
    scheduleUpdate();
  }

  /// Recompute after the next frame (cheap to call on every scroll event).
  void scheduleUpdate() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) update();
    });
  }

  void update() {
    Object? best;
    var bestFraction = playThreshold;
    final near = <Object>{};
    for (final m in _members) {
      final p = m.measure();
      if (p.near) near.add(m.focusKey);
      if (p.visible > bestFraction) {
        bestFraction = p.visible;
        best = m.focusKey;
      }
    }
    final changed = best != _focused || !setEquals(near, _near);
    _focused = best;
    _near
      ..clear()
      ..addAll(near);
    if (changed) notifyListeners();
  }

  /// Pause everything (a sheet or the full-screen viewer is covering the
  /// feed, or the app is in the background). Calls nest.
  void suspend() {
    _suspended++;
    notifyListeners();
  }

  void resume() {
    if (_suspended > 0) _suspended--;
    notifyListeners();
    scheduleUpdate();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Puts a [ReelFocus] in the tree. Dependents rebuild when it changes.
class ReelFocusScope extends InheritedNotifier<ReelFocus> {
  const ReelFocusScope({super.key, required ReelFocus focus, required super.child})
      : super(notifier: focus);

  static ReelFocus? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReelFocusScope>()?.notifier;

  /// Same, without rebuilding when it changes (for use in event handlers).
  static ReelFocus? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ReelFocusScope>()?.notifier;
}

/// Pauses the feed's videos while [open] runs (a sheet, the viewer), then
/// resumes them.
Future<T?> pauseFeedWhile<T>(BuildContext context, Future<T?> Function() open) async {
  final focus = ReelFocusScope.read(context);
  focus?.suspend();
  try {
    return await open();
  } finally {
    focus?.resume();
  }
}
