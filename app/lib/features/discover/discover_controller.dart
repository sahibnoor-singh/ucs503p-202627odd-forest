// ignore_for_file: prefer_initializing_formals
import 'package:flutter/foundation.dart';

import '../../models/video.dart';
import '../../services/api_client.dart';
import '../reels/reels_repository.dart';
import '../safety/safety_repository.dart';

/// The posts in the Discover grid, in the order the server ranked them for this person, loaded a page at a time.
///
/// It shows what the server said and nothing else: when the server cannot be reached [error] says so (and the screen offers a
/// retry) instead of falling back to made-up posts.
class DiscoverController extends ChangeNotifier {
  DiscoverController(this._repository, {this.pageSize = 24, BlocklistController? blocklist}) : _blocklist = blocklist {
    _blocklist?.addListener(_changed);
  }

  final ReelsRepository _repository;
  final BlocklistController? _blocklist;
  final int pageSize;

  List<Video> _videos = const [];
  String? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _moreFailed = false;
  String? _error;
  String? _refreshError;
  int _generation = 0; // bumped by every refresh: an answer to an older question is dropped
  bool _disposed = false;

  /// What the grid shows: the server's list without anyone blocked since it was loaded.
  List<Video> get videos => _blocklist == null ? _videos : [for (final v in _videos) if (!_blocklist.isBlocked(v.authorId)) v];

  /// The cursor to carry on from after [videos] (null when there is no more).
  String? get cursor => _cursor;
  bool get hasMore => _cursor != null;

  /// First load (nothing to show yet).
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;

  /// The next page could not be loaded; [loadMore] tries again.
  bool get moreFailed => _moreFailed;

  /// Why nothing could be shown, in words fit for the screen. Only set while [videos] is empty.
  String? get error => _error;

  /// Why the last pull to refresh failed while posts were on screen (they stay); null after a refresh that worked.
  String? get refreshError => _refreshError;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Loads the first page, or reloads it (pull to refresh). Posts stay on screen while a reload is under way, and if it fails.
  Future<void> refresh() async {
    final gen = ++_generation;
    _refreshError = null;
    if (_videos.isEmpty) {
      _loading = true;
      _error = null;
      _changed();
    }
    try {
      final page = await _repository.getFeed(limit: pageSize);
      if (_disposed || gen != _generation) return;
      _videos = page.videos;
      _cursor = page.nextCursor;
      _error = null;
      _moreFailed = false;
      _loadingMore = false;
    } on Object catch (e) {
      if (_disposed || gen != _generation) return;
      if (_videos.isEmpty) {
        _error = _words(e);
      } else {
        _refreshError = _words(e);
      }
    } finally {
      if (!_disposed && gen == _generation) {
        _loading = false;
        _loadingMore = false; // a page that was being loaded for the old list will be dropped
        _changed();
      }
    }
  }

  Future<void> loadMore() async {
    if (_loadingMore || _cursor == null || _loading) return;
    final gen = _generation;
    _loadingMore = true;
    _moreFailed = false;
    _changed();
    try {
      final page = await _repository.getFeed(cursor: _cursor, limit: pageSize);
      if (_disposed || gen != _generation) return;
      final have = {for (final v in _videos) v.id};
      _videos = [..._videos, ...page.videos.where((v) => have.add(v.id))];
      _cursor = page.nextCursor;
    } on Object {
      if (_disposed || gen != _generation) return;
      _moreFailed = true;
    } finally {
      if (!_disposed && gen == _generation) {
        _loadingMore = false;
        _changed();
      }
    }
  }

  static String _words(Object e) => e is ApiException ? e.message : 'Could not load posts. Check your connection and try again.';

  @override
  void dispose() {
    _blocklist?.removeListener(_changed);
    _disposed = true;
    super.dispose();
  }
}
