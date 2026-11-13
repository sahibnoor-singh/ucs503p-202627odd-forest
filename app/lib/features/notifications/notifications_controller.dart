import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/api_client.dart';
import 'notifications_repository.dart';

/// The notifications list and the number on the bell at the top of Home. Asks the server every so often while Home is on screen (no
/// push yet). A failed ask keeps what is already shown.
class NotificationsController extends ChangeNotifier {
  NotificationsController(this._repository, {this.every = const Duration(seconds: 45)});

  final NotificationsRepository _repository;
  final Duration every;
  Timer? _timer;
  bool _disposed = false;

  int unread = 0;
  List<AppNotification> items = const [];
  bool loading = false;
  String? error;

  void start() {
    unawaited(refreshCount());
    _timer ??= Timer.periodic(every, (_) => unawaited(refreshCount()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Only the number (cheap, for the bell).
  Future<void> refreshCount() async {
    try {
      final r = await _repository.load();
      if (_disposed) return;
      unread = r.unread;
      items = r.items;
      notifyListeners();
    } on Object {
      // keep the old number
    }
  }

  /// Opening the list: show what there is, then mark it all read (the dots stay on the lines for this visit).
  Future<void> open() async {
    loading = items.isEmpty;
    error = null;
    notifyListeners();
    try {
      final r = await _repository.load();
      if (_disposed) return;
      items = r.items;
      unread = r.unread;
      loading = false;
      notifyListeners();
      if (r.unread > 0) {
        await _repository.markAllRead();
        if (_disposed) return;
        unread = 0;
        notifyListeners();
      }
    } on Object catch (e) {
      if (_disposed) return;
      loading = false;
      error = e is ApiException ? e.message : 'Could not load your notifications. Check your connection and try again.';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
