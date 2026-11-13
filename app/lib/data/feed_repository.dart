import '../features/editor/recipe.dart';
import '../models/feed_item.dart';
import '../models/user.dart';

/// The five fixed report reasons from docs/api.md, with the labels the
/// report sheet shows.
enum ReportReason {
  misinformation('MISINFORMATION', 'Misinformation'),
  harassment('HARASSMENT', 'Harassment or hate'),
  spam('SPAM', 'Spam or fake account'),
  violence('VIOLENCE', 'Violent or graphic content'),
  other('OTHER', 'Something else');

  const ReportReason(this.wire, this.label);
  final String wire;
  final String label;
}

/// Everything the Home tab needs from the server. Screens and controllers only
/// ever talk to this, never to `http` (PHASE1_HOME_PLAN.md §7). Failures are
/// thrown as `ApiException` with a message that is safe to show.
abstract class FeedRepository {
  /// `GET /api/me`: who the server thinks we are.
  Future<User> me();

  /// `GET /api/home`: newest first. Pass the previous `nextCursor` for the next page.
  Future<HomePage> home({String? cursor, int limit = 20});

  /// `GET /api/posts/:id`: one card (with `post.analysis`).
  Future<FeedItem> post(String id);

  /// `GET /api/posts/:id/thread`: every reply below the post.
  Future<ThreadResponse> thread(String id, {int limit = 100});

  /// `POST` / `DELETE /api/posts/:id/like`. Idempotent.
  Future<LikeResult> setLiked(String postId, bool liked);

  /// `POST /api/posts` with `kind=TEXT`. The stance comes back already classified.
  Future<FeedItem> replyText({required String parentId, required String body});

  /// `POST /api/posts` with `kind=VIDEO`. Comes back `PROCESSING`; poll [post].
  Future<FeedItem> replyVideo({
    required String parentId,
    required String filePath,
    String? caption,
  });

  /// `POST /api/posts/compose`: a post made in the editor (docs/api.md → "Editor posts"). The server renders the [recipe] and
  /// the files into one video, so it comes back PROCESSING; poll [post]. A reply when [parentId] is given, else a new opinion.
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
  });

  /// `POST /api/posts/:id/retry`: runs the analysis again for your own video
  /// that ended FAILED. Comes back PROCESSING; poll [post]. Throws a 410
  /// `ApiException` when the stored file is gone (record it again).
  Future<FeedItem> retryPost(String postId);

  /// `GET /api/users/suggested`: people worth following, for an empty Home.
  Future<List<SuggestedUser>> suggestedUsers({int limit = 10});

  /// `POST /api/posts/:id/report`.
  Future<void> report(String postId, ReportReason reason);

  /// `POST` / `DELETE /api/users/:id/block`. Blocking also removes the follow.
  Future<void> setBlocked(String userId, bool blocked);

  /// `POST` / `DELETE /api/users/:id/follow`.
  Future<void> setFollowing(String userId, bool following);

  /// Turns the relative `post.mediaUrl` into something a player can open.
  String mediaUrl(String relativePath);
}
