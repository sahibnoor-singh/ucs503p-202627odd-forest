// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/video.dart';
import '../../services/api_client.dart';
import 'recent_searches.dart';
import 'search_repository.dart';

/// What the Discover search box does: waits until typing pauses, asks the server, keeps one set of results per tab (All, Accounts,
/// Posts) for the words in the box, and pages through them.
///
/// An answer that arrives after the words changed is dropped, so results never belong to something that was typed earlier.
class DiscoverSearchController extends ChangeNotifier {
  DiscoverSearchController(
    this._repository, {
    required Future<void> Function(String userId, bool following) setFollowing,
    RecentSearches? recents,
    this.pause = const Duration(milliseconds: 300),
  })  : _setFollowing = setFollowing,
        _recents = recents ?? RecentSearches() {
    _recents.load().then((list) {
      _recent = list;
      _changed();
    });
  }

  /// Fewest letters worth asking the server about.
  static const minLength = 2;

  final SearchRepository _repository;
  final Future<void> Function(String userId, bool following) _setFollowing;
  final RecentSearches _recents;
  final Duration pause;

  String _query = '';
  SearchType _type = SearchType.all;
  final Map<SearchType, _Slot> _slots = {for (final t in SearchType.values) t: _Slot()};
  List<String> _recent = const [];
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;

  /// The words being searched for, tidied (no extra spaces).
  String get query => _query;
  SearchType get type => _type;

  /// There is something to search for (otherwise the screen shows recent searches).
  bool get hasQuery => _query.length >= minLength;
  List<String> get recent => _recent;

  _Slot get _now => _slots[_type]!;
  List<AccountHit> get accounts => _now.accounts;
  List<Video> get posts => _now.posts;

  /// Waiting for the first answer (including the short pause before it is asked for).
  bool get loading => hasQuery && !_now.loaded && _now.error == null;
  bool get loadingMore => _now.loadingMore;
  bool get moreFailed => _now.moreFailed;
  bool get hasMore => _now.cursor != null;
  String? get error => _now.error;
  bool get loaded => _now.loaded;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  static String tidy(String raw) => raw.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Called on every keystroke.
  void setQuery(String raw) {
    final q = tidy(raw);
    if (q == _query) return;
    _query = q;
    _generation++;
    _timer?.cancel();
    for (final s in _slots.values) {
      s.reset();
    }
    if (hasQuery) _timer = Timer(pause, () => _load(_type));
    _changed();
  }

  /// The person pressed search on the keyboard: ask now, and remember the words.
  void submit() {
    _timer?.cancel();
    if (!hasQuery) return;
    _recents.add(_query).then((list) {
      _recent = list;
      _changed();
    });
    if (!_now.loaded && !_now.busy) _load(_type);
  }

  void setType(SearchType type) {
    if (type == _type) return;
    _type = type;
    if (hasQuery && !_now.loaded && !_now.busy && _timer?.isActive != true) _load(type);
    _changed();
  }

  /// The person opened a result: that is a search worth remembering.
  void remember() {
    if (!hasQuery) return;
    _recents.add(_query).then((list) {
      _recent = list;
      _changed();
    });
  }

  Future<void> removeRecent(String q) async {
    _recent = await _recents.remove(q);
    _changed();
  }

  Future<void> clearRecents() async {
    _recent = await _recents.clear();
    _changed();
  }

  Future<void> retry() => _load(_type);

  /// Takes a person out of every tab's results (they were just blocked).
  void removeAccount(String userId) {
    for (final s in _slots.values) {
      s.accounts = [for (final a in s.accounts) if (a.user.id != userId) a];
    }
    _changed();
  }

  /// The latest state of a person in any tab (their follow button may have been pressed since a screen was opened).
  AccountHit? accountById(String userId) {
    for (final s in _slots.values) {
      for (final a in s.accounts) {
        if (a.user.id == userId) return a;
      }
    }
    return null;
  }

  Future<void> _load(SearchType type, {String? cursor}) async {
    final gen = _generation;
    final slot = _slots[type]!;
    final more = cursor != null;
    slot.error = null;
    if (more) {
      slot.loadingMore = true;
      slot.moreFailed = false;
    } else {
      slot.busy = true;
    }
    _changed();
    try {
      final page = await _repository.search(_query, type: type, cursor: cursor);
      if (_disposed || gen != _generation) return;
      if (more) {
        final have = {for (final v in slot.posts) v.id};
        final haveUsers = {for (final a in slot.accounts) a.user.id};
        slot.posts = [...slot.posts, ...page.posts.where((v) => have.add(v.id))];
        slot.accounts = [...slot.accounts, ...page.accounts.where((a) => haveUsers.add(a.user.id))];
      } else {
        slot.posts = page.posts;
        slot.accounts = page.accounts;
        slot.loaded = true;
      }
      slot.cursor = page.nextCursor;
    } on Object catch (e) {
      if (_disposed || gen != _generation) return;
      if (more) {
        slot.moreFailed = true;
      } else {
        slot.error = e is ApiException ? e.message : 'Could not search. Check your connection and try again.';
      }
    } finally {
      if (!_disposed && gen == _generation) {
        slot.busy = false;
        slot.loadingMore = false;
        _changed();
      }
    }
  }

  Future<void> loadMore() async {
    final slot = _now;
    if (slot.cursor == null || slot.loadingMore || slot.busy || !slot.loaded) return;
    await _load(_type, cursor: slot.cursor);
  }

  /// Follows or unfollows at once in every tab, and undoes it if the server refuses. Returns why it failed, or null.
  Future<String?> toggleFollow(AccountHit hit) async {
    final want = !hit.followedByMe;
    _replace(hit.user.id, (h) => h.copyWith(followedByMe: want, followerCount: h.followerCount + (want ? 1 : -1)));
    try {
      await _setFollowing(hit.user.id, want);
      return null;
    } on Object catch (e) {
      _replace(hit.user.id, (h) => h.copyWith(followedByMe: !want, followerCount: h.followerCount + (want ? -1 : 1)));
      final name = '@${hit.user.username}';
      return e is ApiException ? e.message : (want ? 'Could not follow $name.' : 'Could not unfollow $name.');
    }
  }

  void _replace(String userId, AccountHit Function(AccountHit) change) {
    for (final s in _slots.values) {
      s.accounts = [for (final a in s.accounts) a.user.id == userId ? change(a) : a];
    }
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

class _Slot {
  List<AccountHit> accounts = const [];
  List<Video> posts = const [];
  String? cursor;
  bool loaded = false;
  bool busy = false;
  bool loadingMore = false;
  bool moreFailed = false;
  String? error;

  void reset() {
    accounts = const [];
    posts = const [];
    cursor = null;
    loaded = false;
    busy = false;
    loadingMore = false;
    moreFailed = false;
    error = null;
  }
}
