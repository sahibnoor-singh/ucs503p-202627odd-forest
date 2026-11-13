import 'post.dart';
import 'user.dart';

// `Item` in docs/api.md: one card.

enum ItemType {
  post('POST'),
  videoReply('VIDEO_REPLY'),
  textReply('TEXT_REPLY');

  const ItemType(this.wire);
  final String wire;

  static ItemType parse(String value) => values.firstWhere(
        (e) => e.wire == value,
        orElse: () => throw FormatException('Unknown item type "$value"'),
      );
}

/// `item.parent`: the post it directly replies to, with its author.
class ParentRef {
  const ParentRef({required this.actor, required this.post});

  factory ParentRef.fromJson(Map<String, dynamic> json) => ParentRef(
        actor: User.fromJson(json['actor'] as Map<String, dynamic>),
        post: Post.fromJson(json['post'] as Map<String, dynamic>),
      );

  final User actor;
  final Post post;
}

/// `item.root`: set only when the root is not the direct parent.
class RootRef {
  const RootRef({required this.id, required this.username, required this.title});

  factory RootRef.fromJson(Map<String, dynamic> json) => RootRef(
        id: json['id'] as String,
        username: json['username'] as String,
        title: json['title'] as String?,
      );

  final String id;
  final String username;
  final String? title;
}

class FeedItem {
  const FeedItem({
    required this.type,
    required this.actor,
    required this.post,
    required this.parent,
    required this.root,
    required this.createdAt,
  });

  factory FeedItem.fromJson(Map<String, dynamic> json) => FeedItem(
        type: ItemType.parse(json['type'] as String),
        actor: User.fromJson(json['actor'] as Map<String, dynamic>),
        post: Post.fromJson(json['post'] as Map<String, dynamic>),
        parent: json['parent'] == null
            ? null
            : ParentRef.fromJson(json['parent'] as Map<String, dynamic>),
        root: json['root'] == null
            ? null
            : RootRef.fromJson(json['root'] as Map<String, dynamic>),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  final ItemType type;
  final User actor;
  final Post post;
  final ParentRef? parent;
  final RootRef? root;
  final DateTime createdAt;
}

/// One entry of `GET /api/posts/:id/thread` `replies`.
class ThreadReply {
  const ThreadReply({required this.actor, required this.post});

  factory ThreadReply.fromJson(Map<String, dynamic> json) => ThreadReply(
        actor: User.fromJson(json['actor'] as Map<String, dynamic>),
        post: Post.fromJson(json['post'] as Map<String, dynamic>),
      );

  final User actor;
  final Post post;
}

/// `GET /api/posts/:id/thread`: [replies] is flat, depth-first, newest
/// sibling first; rebuild the tree from `post.parentId`.
class ThreadResponse {
  const ThreadResponse({
    required this.item,
    required this.replies,
    required this.total,
  });

  factory ThreadResponse.fromJson(Map<String, dynamic> json) => ThreadResponse(
        item: FeedItem.fromJson(json['item'] as Map<String, dynamic>),
        replies: [
          for (final r in json['replies'] as List<dynamic>)
            ThreadReply.fromJson(r as Map<String, dynamic>),
        ],
        total: (json['total'] as num).toInt(),
      );

  final FeedItem item;
  final List<ThreadReply> replies;

  /// All replies that exist; may be more than [replies] when the API capped it.
  final int total;
}

/// `GET /api/home`.
class HomePage {
  const HomePage({required this.items, required this.nextCursor});

  final List<FeedItem> items;
  final String? nextCursor;
}

/// `POST/DELETE /api/posts/:id/like`.
class LikeResult {
  const LikeResult({required this.liked, required this.likeCount});

  factory LikeResult.fromJson(Map<String, dynamic> json) => LikeResult(
        liked: json['liked'] as bool,
        likeCount: (json['likeCount'] as num).toInt(),
      );

  final bool liked;
  final int likeCount;
}
