import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../data/feed_repository.dart';
import '../../models/feed_item.dart';
import '../../models/post.dart';
import '../../models/user.dart';
import '../../services/api_client.dart';
import '../editor/post_attachment.dart';
import '../editor/recipe.dart';

/// A short message for the user ("Link copied", "Blocked @x" + Undo).
class ToastEvent {
  const ToastEvent(this.message, {this.actionLabel, this.onAction, this.duration});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// How long it stays; null = the default for its kind.
  final Duration? duration;
}

/// State behind the Home tab: the feed, paging, and one shared, latest view of
/// every post the app has seen (so liking a post in a card, its quoted copy,
/// the viewer and the thread all agree). Talks only to a [FeedRepository].
class FeedController extends ChangeNotifier {
  FeedController(
    this._repo, {
    this.pageSize = 20,
    this.pollInterval = const Duration(seconds: 3),
    this.maxPolls = 60,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final FeedRepository _repo;
  final int pageSize;
  final Duration pollInterval;
  final int maxPolls;
  final DateTime Function() _clock;

  /// Who we are (for hiding Report/Block on our own posts). Null until known.
  User? me;

  final List<FeedItem> _items = [];
  String? _cursor;
  final Map<String, Post> _posts = {};
  final Set<String> _blockedUserIds = {};
  final Set<String> _likesInFlight = {};
  final Set<String> _seenStories = {};
  final Set<Timer> _timers = {};
  final Set<String> _retriesInFlight = {};

  /// After a 429/503 the server is left alone until this time: no refresh, no
  /// next page, whatever the user scrolls (docs/api.md "Limits").
  DateTime? _coolDownUntil;

  /// After any failed next-page load the scroll listener must not fire it again
  /// on every scroll event.
  DateTime? _loadMoreRetryAt;
  static const _loadMorePause = Duration(seconds: 5);
  final StreamController<ToastEvent> _toasts = StreamController.broadcast();
  bool _disposed = false;

  bool loaded = false;
  bool loading = false;
  bool loadingMore = false;
  bool hasMore = false;

  // ---- who to follow (empty Home) ----

  /// The suggested people (`GET /api/users/suggested`); null until asked.
  List<SuggestedUser>? suggestions;
  bool suggestionsLoading = false;
  String? suggestionsError;
  final Set<String> _followedIds = {};
  final Set<String> _followsInFlight = {};

  /// Set only when the first page could not be loaded and there is nothing to show.
  String? error;

  /// One mute switch for every video in the app (prototype: feed-wide).
  bool muted = true;

  Stream<ToastEvent> get toasts => _toasts.stream;

  /// The feed without anyone we just blocked.
  List<FeedItem> get items => [
        for (final i in _items)
          if (!_blockedUserIds.contains(i.actor.id) &&
              !(i.parent != null && _blockedUserIds.contains(i.parent!.actor.id)))
            i,
      ];

  /// People you follow, for the stories row: everyone who authored a card
  /// in the feed (Home only shows people you follow), in feed order. Not you.
  List<User> get storyUsers {
    final seen = <String>{};
    return [
      for (final i in items)
        if (!isMine(i.actor) && seen.add(i.actor.id)) i.actor,
    ];
  }

  /// Stories have no server support yet: "seen" is only remembered locally.
  bool isStorySeen(User user) => _seenStories.contains(user.id);

  void toggleStorySeen(User user) {
    if (!_seenStories.remove(user.id)) _seenStories.add(user.id);
    _notify();
  }

  String? mediaUrl(Post post) =>
      post.mediaUrl == null ? null : _repo.mediaUrl(post.mediaUrl!);

  /// The picture shown before the video plays, if the post has one.
  String? coverUrl(Post post) =>
      post.coverUrl == null ? null : _repo.mediaUrl(post.coverUrl!);

  bool isMine(User user) => me != null && me!.id == user.id;

  /// [base] at its latest known state (likes, counts, status).
  Post resolve(Post base) => _posts[base.id] ?? base;

  // ---- loading ----

  void ensureLoaded() {
    if (!loaded && !loading) refresh();
  }

  /// Seconds left of a 429/503 cool-down, or 0.
  int get coolDownSeconds {
    final until = _coolDownUntil;
    if (until == null) return 0;
    final left = until.difference(_clock());
    return left.isNegative ? 0 : (left.inMilliseconds / 1000).ceil();
  }

  void _startCoolDown(ApiException e) {
    if (e.shouldBackOff) _coolDownUntil = _clock().add(e.backOff());
  }

  Future<void> refresh() async {
    final wait = coolDownSeconds;
    if (wait > 0) {
      _say('The server asked us to slow down. Try again in $wait s.');
      return;
    }
    loading = true;
    error = null;
    _notify();
    unawaited(_loadMe());
    try {
      final page = await _repo.home(limit: pageSize);
      _items
        ..clear()
        ..addAll(page.items);
      _cursor = page.nextCursor;
      hasMore = _cursor != null;
      _loadMoreRetryAt = null;
      _registerItems(page.items);
      loaded = true;
    } on ApiException catch (e) {
      _startCoolDown(e);
      _loadFailed(e.message);
    } on Object {
      _loadFailed('Could not load your feed.');
    } finally {
      loading = false;
      _notify();
    }
    if (loaded && items.isEmpty) unawaited(loadSuggestions(force: true));
  }

  void _loadFailed(String message) {
    if (_items.isEmpty) {
      error = message;
    } else {
      _say(message); // keep what is on screen
    }
  }

  Future<void> loadMore() async {
    if (!hasMore || loadingMore || loading || _cursor == null) return;
    if (coolDownSeconds > 0) return;
    final retryAt = _loadMoreRetryAt;
    if (retryAt != null && _clock().isBefore(retryAt)) return;
    loadingMore = true;
    _notify();
    try {
      final page = await _repo.home(cursor: _cursor, limit: pageSize);
      _items.addAll(page.items);
      _cursor = page.nextCursor;
      hasMore = _cursor != null;
      _loadMoreRetryAt = null;
      _registerItems(page.items);
    } on ApiException catch (e) {
      _startCoolDown(e);
      _loadMoreRetryAt = _clock().add(_loadMorePause);
      _say(e.message);
    } on Object {
      _loadMoreRetryAt = _clock().add(_loadMorePause);
      _say('Could not load more.');
    } finally {
      loadingMore = false;
      _notify();
    }
  }

  // ---- who to follow ----

  /// Loads the suggestions the first time the empty Home needs them; never
  /// again after a failure (the Retry button does that, and respects any wait).
  void ensureSuggestions() {
    if (suggestions == null && suggestionsError == null && !suggestionsLoading) {
      unawaited(loadSuggestions());
    }
  }

  /// Loads the suggestions once (or again when [force]d).
  Future<void> loadSuggestions({bool force = false}) async {
    if (suggestionsLoading || (suggestions != null && !force)) return;
    if (coolDownSeconds > 0) {
      suggestionsError = 'The server asked us to slow down. Try again in $coolDownSeconds s.';
      _notify();
      return;
    }
    suggestionsLoading = true;
    suggestionsError = null;
    _notify();
    try {
      suggestions = await _repo.suggestedUsers();
    } on ApiException catch (e) {
      _startCoolDown(e);
      suggestionsError = e.message;
    } on Object {
      suggestionsError = 'Could not load suggestions.';
    } finally {
      suggestionsLoading = false;
      _notify();
    }
  }

  bool isFollowing(User user) => _followedIds.contains(user.id);

  /// How many people were followed from the suggestions this session.
  int get followedCount => _followedIds.length;

  /// Follow / unfollow from the suggestions, shown at once and rolled back
  /// with the server's reason when it refuses.
  Future<void> toggleFollow(User user) async {
    if (!_followsInFlight.add(user.id)) return;
    final want = !_followedIds.contains(user.id);
    want ? _followedIds.add(user.id) : _followedIds.remove(user.id);
    _notify();
    try {
      await _repo.setFollowing(user.id, want);
    } on Object catch (e) {
      want ? _followedIds.remove(user.id) : _followedIds.add(user.id);
      _say(_messageOf(e, want ? 'Could not follow @${user.username}.' : 'Could not unfollow @${user.username}.'));
    } finally {
      _followsInFlight.remove(user.id);
      _notify();
    }
  }

  Future<void> _loadMe() async {
    try {
      me = await _repo.me();
      _notify();
    } on Object {
      // Not critical: we just can't hide Report/Block on our own posts.
    }
  }

  void _registerItems(List<FeedItem> items) {
    for (final i in items) {
      _posts[i.post.id] = i.post;
      if (i.parent != null) _posts[i.parent!.post.id] = i.parent!.post;
    }
  }

  void _registerPost(Post post) => _posts[post.id] = post;

  /// Lets cards for posts that did not come from Home (the question's answers, a room's posts, the opinions waiting for a reply)
  /// share likes and counts with it.
  void adopt(List<FeedItem> items) => _registerItems(items);

  // ---- thread ----

  /// `GET /api/posts/:id/thread`, with every post it returns registered so
  /// likes in the thread and in the feed stay in step.
  Future<ThreadResponse> loadThread(String postId) async {
    final thread = await _repo.thread(postId);
    _registerPost(thread.item.post);
    for (final r in thread.replies) {
      _registerPost(r.post);
    }
    _notify();
    return thread;
  }

  // ---- likes ----

  Future<void> toggleLike(Post base) async {
    final current = resolve(base);
    if (current.status != PostStatus.ready || !_likesInFlight.add(current.id)) return;
    final want = !current.likedByMe;
    _setPost(current.copyWith(
      likedByMe: want,
      likeCount: math.max(0, current.likeCount + (want ? 1 : -1)),
    ));
    try {
      final result = await _repo.setLiked(current.id, want);
      _setPost(resolve(current).copyWith(likedByMe: result.liked, likeCount: result.likeCount));
    } on Object catch (e) {
      _setPost(resolve(current).copyWith(
        likedByMe: current.likedByMe,
        likeCount: current.likeCount,
      ));
      _say(_messageOf(e, 'Could not update your like.'));
    } finally {
      _likesInFlight.remove(current.id);
    }
  }

  /// Double tap: likes, never un-likes.
  Future<void> likeOnly(Post base) async {
    if (!resolve(base).likedByMe) await toggleLike(base);
  }

  // ---- replies ----

  /// Posts a text reply. Throws [ApiException] so the composer can show the
  /// reason and stay open.
  Future<FeedItem> replyText(Post parent, String body) async {
    final item = await _repo.replyText(parentId: parent.id, body: body.trim());
    _registerPost(item.post);
    _countNewReply(parent.id, item.post);
    _say('Reply posted. AI stance: ${item.post.stance.wire}');
    return item;
  }

  /// Posts a video reply. It comes back PROCESSING; we poll until it is READY
  /// and only then count it, because the server counts READY replies only.
  Future<FeedItem> replyVideo(Post parent, String filePath) async {
    final item = await _repo.replyVideo(parentId: parent.id, filePath: filePath);
    _registerPost(item.post);
    _say('Reply posted. Analysing it now.');
    _poll(item.post.id, parent.id);
    return item;
  }

  /// Posts something made in the editor: a reply when [parent] is given, else a new opinion. The server renders it and the AI
  /// reads it, so it comes back PROCESSING and we poll until it is READY, like a video reply. Throws [ApiException] so the
  /// editor can show the reason and stay open.
  Future<FeedItem> compose({
    Post? parent,
    required Recipe recipe,
    double? videoSeconds,
    String? title,
    String? body,
    String? videoPath,
    List<String> photoPaths = const [],
    String? musicPath,
    PostAttachment? attach,
  }) async {
    final item = await _repo.compose(
      recipe: recipe,
      videoSeconds: videoSeconds,
      parentId: parent?.id,
      title: title,
      body: body,
      videoPath: videoPath,
      photoPaths: photoPaths,
      musicPath: musicPath,
      promptDay: attach?.promptDay,
      roomId: attach?.roomId,
    );
    _registerPost(item.post);
    _say(parent == null ? 'Posted. Making your video now.' : 'Reply posted. Making your video now.');
    _poll(item.post.id, parent?.id);
    return item;
  }

  void _countNewReply(String parentId, Post reply) {
    for (final id in {parentId, reply.rootId}) {
      final known = _posts[id];
      if (known == null) continue;
      _setPost(known.copyWith(
        replyCount: known.replyCount + 1,
        forCount: known.forCount + (reply.stance == Stance.forSide ? 1 : 0),
        againstCount: known.againstCount + (reply.stance == Stance.against ? 1 : 0),
      ));
    }
  }

  /// [parentId] is null for a new opinion (nothing to count).
  void _poll(String postId, String? parentId, {int attempt = 0, Duration? delay, bool told = false}) {
    late final Timer timer;
    timer = Timer(delay ?? pollInterval, () async {
      _timers.remove(timer);
      if (_disposed) return;
      var nextDelay = pollInterval;
      var toldAboutLimit = told;
      try {
        final item = await _repo.post(postId);
        if (_disposed) return;
        _registerPost(item.post);
        if (item.post.status == PostStatus.ready) {
          if (parentId == null) {
            _say('Your post is ready.');
            return;
          }
          _countNewReply(parentId, item.post);
          _say('Your video reply is ready. AI stance: ${item.post.stance.wire}');
          return;
        }
        if (item.post.status == PostStatus.failed) {
          _say(
            parentId == null ? 'Your post could not be processed.' : 'Your video reply could not be processed.',
            actionLabel: 'Retry',
            onAction: () => retryVideo(item.post),
            duration: const Duration(seconds: 10),
          );
          return;
        }
        toldAboutLimit = false;
      } on ApiException catch (e) {
        if (e.shouldBackOff) {
          // Never poll faster than the server asked, and say so once.
          nextDelay = e.backOff() > pollInterval ? e.backOff() : pollInterval;
          if (!toldAboutLimit) _say(e.message);
          toldAboutLimit = true;
        }
      } on Object {
        // Try again on the next tick.
      }
      if (attempt + 1 < maxPolls) {
        _poll(postId, parentId, attempt: attempt + 1, delay: nextDelay, told: toldAboutLimit);
      }
    });
    _timers.add(timer);
  }

  /// "Retry" on a video that ended FAILED: the server runs the analysis again
  /// from the stored file, so nothing is uploaded twice. If the file is gone
  /// (410) the person has to record again.
  Future<void> retryVideo(Post failed) async {
    if (resolve(failed).status != PostStatus.failed) return;
    if (!_retriesInFlight.add(failed.id)) return;
    try {
      final item = await _repo.retryPost(failed.id);
      _registerPost(item.post);
      _say('Trying again. Analysing it now.');
      _poll(item.post.id, item.post.parentId);
    } on ApiException catch (e) {
      _say(e.statusCode == 410 ? '${e.message} Record it again.' : e.message);
    } on Object {
      _say('Could not retry. Check your connection and try again.');
    } finally {
      _retriesInFlight.remove(failed.id);
    }
  }

  // ---- report / block ----

  /// Returns true when the report was accepted.
  Future<bool> report(Post post, ReportReason reason) async {
    try {
      await _repo.report(post.id, reason);
      _say('Reported. We will review it.');
      return true;
    } on Object catch (e) {
      _say(_messageOf(e, 'Could not send your report.'));
      return false;
    }
  }

  /// Hides [user] everywhere right away, then tells the server. Undo
  /// unblocks, and re-follows when [wasFollowing] (blocking removes the follow).
  Future<void> block(User user, {required bool wasFollowing}) async {
    if (!_blockedUserIds.add(user.id)) return;
    _notify();
    try {
      await _repo.setBlocked(user.id, true);
      _say(
        'Blocked @${user.username}',
        actionLabel: 'Undo',
        onAction: () => unblock(user, wasFollowing: wasFollowing),
      );
    } on Object catch (e) {
      _blockedUserIds.remove(user.id);
      _notify();
      _say(_messageOf(e, 'Could not block @${user.username}.'));
    }
  }

  Future<void> unblock(User user, {required bool wasFollowing}) async {
    try {
      await _repo.setBlocked(user.id, false);
      if (wasFollowing) await _repo.setFollowing(user.id, true);
      _blockedUserIds.remove(user.id);
      _notify();
      _say('Unblocked @${user.username}');
    } on Object catch (e) {
      _say(_messageOf(e, 'Could not unblock @${user.username}.'));
    }
  }

  // ---- misc ----

  void toggleMute() {
    muted = !muted;
    _notify();
    _say(muted ? 'Videos muted' : 'Sound on');
  }

  void say(String message) => _say(message);

  void _setPost(Post post) {
    _posts[post.id] = post;
    _notify();
  }

  String _messageOf(Object error, String fallback) =>
      error is ApiException ? error.message : fallback;

  void _say(String message, {String? actionLabel, VoidCallback? onAction, Duration? duration}) {
    if (_disposed || _toasts.isClosed) return;
    _toasts.add(ToastEvent(message, actionLabel: actionLabel, onAction: onAction, duration: duration));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _toasts.close();
    super.dispose();
  }
}
