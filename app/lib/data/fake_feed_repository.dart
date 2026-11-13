import '../features/editor/recipe.dart';
import '../models/feed_item.dart';
import '../models/post.dart';
import '../models/user.dart';
import '../services/api_client.dart';
import 'feed_repository.dart';

/// In-memory stand-in for the server, with the same rules (counts come from
/// READY descendants, newest sibling first, blocked people vanish from
/// threads). Used by tests; also handy for running the UI without a backend.
class FakeFeedRepository implements FeedRepository {
  FakeFeedRepository._({
    required List<_Row> rows,
    required List<String> homeOrder,
    required this.meUser,
  })  : _rows = {for (final r in rows) r.post.id: r},
        _homeOrder = List.of(homeOrder);

  /// The prototype's sample debate (docs/design/home_prototype.html): one
  /// opinion with video and text replies, a reply-to-a-reply, and a bot post
  /// whose video has no file.
  factory FakeFeedRepository.sample({DateTime? now, List<String>? homeOrder}) {
    final t = (now ?? DateTime.now()).toUtc();
    DateTime ago(int minutes) => t.subtract(Duration(minutes: minutes));

    const aman = User(id: 'u1', username: 'aman_s', fullName: 'Aman Singh', avatarUrl: null, isBot: false);
    const riya = User(id: 'u2', username: 'riya_k', fullName: 'Riya Kapoor', avatarUrl: null, isBot: false);
    const kabir = User(id: 'u3', username: 'kabir_m', fullName: 'Kabir Mehta', avatarUrl: null, isBot: false);
    const simran = User(id: 'u4', username: 'simran.v', fullName: 'Simran Verma', avatarUrl: null, isBot: false);
    const dev = User(id: 'u5', username: 'dev.p', fullName: 'Dev Patel', avatarUrl: null, isBot: false);
    const priya = User(id: 'u6', username: 'priya_n', fullName: 'Priya Nair', avatarUrl: null, isBot: false);
    const daily = User(id: 'u7', username: 'forest_daily', fullName: 'FOREST Daily Prompt', avatarUrl: null, isBot: true);
    const me = User(id: 'me', username: 'you', fullName: 'You', avatarUrl: null, isBot: false);

    final rows = <_Row>[
      _Row(aman, _post('p1', PostKind.video, null, 'p1', 0, ago(180),
          title: 'Should Punjabi be mandatory in schools till Class 12?',
          body: 'Aman argues a state language should be compulsory through school.',
          media: '/uploads/p1.mp4', likes: 40)),
      _Row(riya, _post('r1', PostKind.video, 'p1', 'p1', 1, ago(60),
          body: 'Mandates hurt students from other states',
          media: '/uploads/r1.mp4', stance: Stance.against, likes: 12)),
      _Row(simran, _post('r2', PostKind.text, 'p1', 'p1', 1, ago(120),
          body: 'Most states that did this saw dropout rates rise for migrant kids.',
          stance: Stance.against, likes: 5)),
      _Row(kabir, _post('r3', PostKind.video, 'r1', 'p1', 2, ago(20),
          body: 'The problem is the rollout, not the language itself.',
          stance: Stance.forSide, likes: 7)), // no file on purpose
      _Row(daily, _post('p2', PostKind.video, null, 'p2', 0, ago(300),
          title: 'Daily debate: should colleges ban phones in lecture halls?',
          body: 'Daily prompt posted by the FOREST bot to start a conversation.',
          likes: 12)),
      _Row(dev, _post('r4', PostKind.text, 'p2', 'p2', 1, ago(360),
          body: 'Depends on the class. Taking notes on a laptop is different from scrolling reels.',
          stance: Stance.unresolved, likes: 3)),
      _Row(priya, _post('x1', PostKind.text, 'p1', 'p1', 1, ago(150),
          body: 'Learning your state’s language is basic respect.',
          stance: Stance.forSide, likes: 9)),
      _Row(dev, _post('x2', PostKind.text, 'p1', 'p1', 1, ago(170),
          body: 'Mandatory till Class 10 and optional after sounds like a fair middle.',
          stance: Stance.unresolved, likes: 4)),
      _Row(aman, _post('x3', PostKind.text, 'r2', 'p1', 2, ago(95),
          body: 'Dropout data needs context. Which states and which years?',
          stance: Stance.unresolved, likes: 2)),
    ];
    return FakeFeedRepository._(
      rows: rows,
      homeOrder: homeOrder ?? ['r3', 'r1', 'r2', 'p1', 'p2', 'r4'],
      meUser: me,
    );
  }

  static Post _post(
    String id,
    PostKind kind,
    String? parentId,
    String rootId,
    int depth,
    DateTime createdAt, {
    String? title,
    String? body,
    String? media,
    Stance stance = Stance.parent,
    int likes = 0,
    PostStatus status = PostStatus.ready,
  }) =>
      Post(
        id: id,
        kind: kind,
        parentId: parentId,
        rootId: rootId,
        depth: depth,
        title: title,
        body: body,
        mediaUrl: media,
        stance: stance,
        status: status,
        summary: null,
        createdAt: createdAt,
        likeCount: likes,
        likedByMe: false,
        replyCount: 0,
        forCount: 0,
        againstCount: 0,
      );

  final User meUser;
  final Map<String, _Row> _rows;
  final List<String> _homeOrder;
  final Set<String> _blocked = {};
  int _seq = 0;

  /// What the fake was asked to do, in order (`like:p1`, `report:p1:SPAM`, ...).
  final List<String> log = [];

  /// Set to make the next call fail with this exception (then it clears).
  ApiException? failNext;

  /// Stance a new text reply gets.
  Stance nextTextStance = Stance.forSide;

  /// A new video reply stays PROCESSING for this many `post(id)` polls.
  int pollsUntilReady = 1;

  /// When true, a PROCESSING video ends FAILED instead of READY (until a retry
  /// succeeds: `failNextAnalysis` clears itself after one failure).
  bool failNextAnalysis = false;

  /// Posts whose stored file is "gone": retrying them answers 410.
  final Set<String> goneFiles = {};

  /// How many times `post(id)` was called (polling).
  int postReads = 0;

  /// How many times `home()` was called.
  int homeReads = 0;

  /// Makes `suggestedUsers` fail (and nothing else).
  ApiException? failSuggestions;

  /// What `suggestedUsers` returns. Null = everyone with a post except you.
  List<SuggestedUser>? suggested;
  final Map<String, int> _polls = {};

  void _maybeFail() {
    final error = failNext;
    if (error != null) {
      failNext = null;
      throw error;
    }
  }

  // ---- reads shaped like the server's JSON ----

  ({int replies, int forCount, int againstCount}) _counts(String id) {
    var replies = 0, f = 0, a = 0;
    void walk(String parent) {
      for (final r in _rows.values) {
        if (r.post.parentId == parent && r.post.status == PostStatus.ready) {
          replies++;
          if (r.post.stance == Stance.forSide) f++;
          if (r.post.stance == Stance.against) a++;
          walk(r.post.id);
        }
      }
    }

    walk(id);
    return (replies: replies, forCount: f, againstCount: a);
  }

  Post _shaped(Post p) {
    final c = _counts(p.id);
    return p.copyWith(replyCount: c.replies, forCount: c.forCount, againstCount: c.againstCount);
  }

  FeedItem _item(String id) {
    final row = _rows[id]!;
    final post = _shaped(row.post);
    ParentRef? parent;
    RootRef? root;
    if (post.parentId != null) {
      final p = _rows[post.parentId!]!;
      parent = ParentRef(actor: p.actor, post: _shaped(p.post));
      if (post.rootId != post.parentId) {
        final r = _rows[post.rootId]!;
        root = RootRef(id: r.post.id, username: r.actor.username, title: r.post.title);
      }
    }
    return FeedItem(
      type: parent == null
          ? ItemType.post
          : (post.kind == PostKind.video ? ItemType.videoReply : ItemType.textReply),
      actor: row.actor,
      post: post,
      parent: parent,
      root: root,
      createdAt: post.createdAt,
    );
  }

  // ---- FeedRepository ----

  @override
  Future<User> me() async {
    // Not affected by failNext: the app treats me() as optional.
    return meUser;
  }

  @override
  Future<HomePage> home({String? cursor, int limit = 20}) async {
    homeReads++;
    _maybeFail();
    final visible = [
      for (final id in _homeOrder)
        if (!_blocked.contains(_rows[id]!.actor.id) &&
            !(_rows[id]!.post.parentId != null &&
                _blocked.contains(_rows[_rows[id]!.post.parentId!]!.actor.id)))
          id,
    ];
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = (start + limit).clamp(0, visible.length);
    return HomePage(
      items: [for (final id in visible.sublist(start, end)) _item(id)],
      nextCursor: end < visible.length ? '$end' : null,
    );
  }

  @override
  Future<FeedItem> post(String id) async {
    postReads++;
    _maybeFail();
    final row = _rows[id];
    if (row == null) throw const ApiException('Post not found', statusCode: 404);
    if (row.post.status == PostStatus.processing) {
      final polls = (_polls[id] ?? 0) + 1;
      _polls[id] = polls;
      if (polls >= pollsUntilReady) {
        final fails = failNextAnalysis;
        failNextAnalysis = false;
        _rows[id] = _Row(
          row.actor,
          fails
              ? row.post.copyWith(status: PostStatus.failed)
              : row.post.copyWith(status: PostStatus.ready, stance: Stance.forSide),
        );
      }
    }
    return _item(id);
  }

  @override
  Future<ThreadResponse> thread(String id, {int limit = 100}) async {
    _maybeFail();
    final ordered = <_Row>[];
    void walk(String parent) {
      final kids = _rows.values
          .where((r) =>
              r.post.parentId == parent &&
              r.post.status == PostStatus.ready &&
              !_blocked.contains(r.actor.id))
          .toList()
        ..sort((a, b) => b.post.createdAt.compareTo(a.post.createdAt));
      for (final k in kids) {
        ordered.add(k);
        walk(k.post.id);
      }
    }

    walk(id);
    return ThreadResponse(
      item: _item(id),
      replies: [
        for (final r in ordered.take(limit))
          ThreadReply(actor: r.actor, post: _shaped(r.post)),
      ],
      total: ordered.length,
    );
  }

  @override
  Future<LikeResult> setLiked(String postId, bool liked) async {
    _maybeFail();
    log.add('${liked ? 'like' : 'unlike'}:$postId');
    final row = _rows[postId]!;
    if (row.post.likedByMe != liked) {
      _rows[postId] = _Row(
        row.actor,
        row.post.copyWith(likedByMe: liked, likeCount: row.post.likeCount + (liked ? 1 : -1)),
      );
    }
    final now = _rows[postId]!.post;
    return LikeResult(liked: now.likedByMe, likeCount: now.likeCount);
  }

  FeedItem _create(Post Function(String id, Post parent) build, String parentId) {
    final parent = _rows[parentId];
    if (parent == null) throw const ApiException('The post you are replying to was not found', statusCode: 404);
    final id = 'new${++_seq}';
    _rows[id] = _Row(meUser, build(id, parent.post));
    return _item(id);
  }

  @override
  Future<FeedItem> replyText({required String parentId, required String body}) async {
    _maybeFail();
    log.add('replyText:$parentId:$body');
    return _create(
      (id, parent) => _post(id, PostKind.text, parentId, parent.rootId, parent.depth + 1,
          DateTime.now().toUtc(), body: body, stance: nextTextStance),
      parentId,
    );
  }

  @override
  Future<FeedItem> replyVideo({
    required String parentId,
    required String filePath,
    String? caption,
  }) async {
    _maybeFail();
    log.add('replyVideo:$parentId:$filePath');
    return _create(
      (id, parent) => _post(id, PostKind.video, parentId, parent.rootId, parent.depth + 1,
          DateTime.now().toUtc(),
          body: caption,
          media: '/uploads/$id.mp4',
          stance: Stance.unresolved,
          status: PostStatus.processing),
      parentId,
    );
  }

  /// What [compose] was last called with, for tests.
  final composed = <Map<String, Object?>>[];

  @override
  Future<FeedItem> compose({
    required Recipe recipe,
    double? videoSeconds,
    String? parentId,
    String? title,
    String? body,
    String? videoPath,
    List<String> photoPaths = const [],
    String? musicPath,
    String? promptDay,
    String? roomId,
  }) async {
    _maybeFail();
    log.add('compose:${parentId ?? 'root'}');
    composed.add({
      'promptDay': promptDay,
      'roomId': roomId,
      'recipe': recipe.toJson(videoSeconds: videoSeconds),
      'parentId': parentId,
      'title': title,
      'body': body,
      'videoPath': videoPath,
      'photoPaths': photoPaths,
      'musicPath': musicPath,
    });
    if (parentId != null) {
      return _create(
        (id, parent) => _post(id, PostKind.video, parentId, parent.rootId, parent.depth + 1, DateTime.now().toUtc(),
            body: body, stance: Stance.unresolved, status: PostStatus.processing, media: '/uploads/$id.mp4'),
        parentId,
      );
    }
    final id = 'new${++_seq}';
    _rows[id] = _Row(meUser, _post(id, PostKind.video, null, id, 0, DateTime.now().toUtc(),
        title: title, body: body, status: PostStatus.processing, media: '/uploads/$id.mp4'));
    return _item(id);
  }

  @override
  Future<FeedItem> retryPost(String postId) async {
    _maybeFail();
    log.add('retry:$postId');
    final row = _rows[postId];
    if (row == null || row.actor.id != meUser.id) {
      throw const ApiException('Post not found', statusCode: 404);
    }
    if (row.post.status != PostStatus.failed) {
      throw const ApiException('Only a failed video can be retried.', statusCode: 409);
    }
    if (goneFiles.contains(postId)) {
      throw const ApiException('The video file is gone. Upload it again.', statusCode: 410);
    }
    _polls.remove(postId);
    _rows[postId] = _Row(row.actor, row.post.copyWith(status: PostStatus.processing));
    return _item(postId);
  }

  @override
  Future<List<SuggestedUser>> suggestedUsers({int limit = 10}) async {
    log.add('suggested');
    final failure = failSuggestions;
    if (failure != null) throw failure;
    final given = suggested;
    if (given != null) return given.take(limit).toList();
    final seen = <String>{};
    return [
      for (final r in _rows.values)
        if (r.actor.id != meUser.id && seen.add(r.actor.id))
          SuggestedUser(
            user: r.actor,
            followerCount: 0,
            postCount: _rows.values.where((x) => x.actor.id == r.actor.id).length,
          ),
    ].take(limit).toList();
  }

  @override
  Future<void> report(String postId, ReportReason reason) async {
    _maybeFail();
    log.add('report:$postId:${reason.wire}');
  }

  @override
  Future<void> setBlocked(String userId, bool blocked) async {
    _maybeFail();
    log.add('${blocked ? 'block' : 'unblock'}:$userId');
    blocked ? _blocked.add(userId) : _blocked.remove(userId);
  }

  @override
  Future<void> setFollowing(String userId, bool following) async {
    _maybeFail();
    log.add('${following ? 'follow' : 'unfollow'}:$userId');
  }

  @override
  String mediaUrl(String relativePath) => 'http://fake.test$relativePath';
}

class _Row {
  const _Row(this.actor, this.post);

  final User actor;
  final Post post;
}
