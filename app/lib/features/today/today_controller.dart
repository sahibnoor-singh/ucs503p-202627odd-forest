import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/feed_item.dart';
import 'today_repository.dart';

/// What the top of Home shows besides the feed: the day's question and the opinions waiting for a reply. Both are optional extras: if
/// the server cannot be reached, or has no such thing yet, nothing shows (see [prompt]) and Home works exactly as before.
class TodayController extends ChangeNotifier {
  TodayController(this.repository);

  final TodayRepository repository;

  DailyPrompt? prompt;
  List<FeedItem> waiting = const [];
  bool loading = false;
  bool _disposed = false;

  /// Loads both. Safe to call again (pull to refresh, coming back from answering).
  Future<void> load() async {
    if (loading) return;
    loading = true;
    try {
      final results = await Future.wait<Object?>([
        repository.prompt().then<Object?>((p) => p, onError: (Object _) => null),
        repository.replyWanted().then<Object?>((w) => w, onError: (Object _) => null),
      ]);
      prompt = results[0] as DailyPrompt? ?? prompt;
      waiting = (results[1] as List<FeedItem>?) ?? waiting;
    } finally {
      loading = false;
      _notify();
    }
  }

  /// A reply was just posted to [postId]: it no longer needs one.
  void markReplied(String postId) {
    waiting = [for (final i in waiting) if (i.post.id != postId) i];
    _notify();
  }

  /// This person just answered the question.
  void markAnswered() {
    final p = prompt;
    if (p == null || p.answered) return;
    prompt = p.copyWith(answered: true, answerCount: p.answerCount + 1);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
