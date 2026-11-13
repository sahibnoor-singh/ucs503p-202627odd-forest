import 'dart:async';

import 'package:flutter/foundation.dart';

import 'messages_repository.dart';

/// How many conversations have something new: the number on the paper-plane at the top of Home. Asks the server every so often while
/// Home is on screen (no push yet), and whenever someone has just read or written. A failed ask leaves the old number.
class UnreadController extends ChangeNotifier {
  UnreadController(this._repository, {this.every = const Duration(seconds: 30)});

  final MessagesRepository _repository;
  final Duration every;
  int _count = 0;
  Timer? _timer;
  bool _disposed = false;

  int get count => _count;

  void start() {
    unawaited(refresh());
    _timer ??= Timer.periodic(every, (_) => unawaited(refresh()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> refresh() async {
    try {
      set(await _repository.unread());
    } on Object {
      // keep the old number
    }
  }

  /// The inbox already knows the number.
  void set(int n) {
    if (_disposed || n == _count) return;
    _count = n;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
