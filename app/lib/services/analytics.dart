import 'dart:async';

import 'api_client.dart';

/// Tells the server about the few things only the app can see (opening it, tapping the daily question), so the founders can tell
/// whether anything works. Events are small flags (`docs/api.md`, "Events"): never video, text, search words or contact details.
///
/// Measuring must never get in the way of the app: a failed send is dropped, nothing is retried, and nothing waits on it. Events go out
/// as soon as they are tracked, one batch at a time, so no timer is left running.
class Analytics {
  Analytics(this._api);

  final ApiClient _api;
  final List<Map<String, Object?>> _queue = [];
  bool _sending = false;

  void track(String name, [Map<String, Object?>? props]) {
    if (_queue.length >= 100) _queue.removeAt(0);
    _queue.add({'name': name, 'props': ?props});
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_sending || _queue.isEmpty) return;
    _sending = true;
    final batch = _queue.take(50).toList();
    _queue.removeRange(0, batch.length);
    try {
      await _api.sendJson('POST', '/api/events', body: {'events': batch});
    } on Object {
      // dropped on purpose
    } finally {
      _sending = false;
    }
    if (_queue.isNotEmpty) unawaited(_drain());
  }
}
