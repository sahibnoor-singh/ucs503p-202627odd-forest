// `Post` in docs/api.md.

enum PostKind {
  video('VIDEO'),
  text('TEXT');

  const PostKind(this.wire);
  final String wire;

  static PostKind parse(String value) => values.firstWhere(
        (e) => e.wire == value,
        orElse: () => throw FormatException('Unknown post kind "$value"'),
      );
}

enum Stance {
  parent('PARENT'),
  forSide('FOR'),
  against('AGAINST'),
  unresolved('UNRESOLVED');

  const Stance(this.wire);
  final String wire;

  static Stance parse(String value) => values.firstWhere(
        (e) => e.wire == value,
        orElse: () => throw FormatException('Unknown stance "$value"'),
      );
}

enum PostStatus {
  processing('PROCESSING'),
  ready('READY'),
  failed('FAILED');

  const PostStatus(this.wire);
  final String wire;

  static PostStatus parse(String value) => values.firstWhere(
        (e) => e.wire == value,
        orElse: () => throw FormatException('Unknown post status "$value"'),
      );
}

/// The motion room a post was made in (`post.room`).
class PostRoom {
  const PostRoom({required this.id, required this.name});

  final String id;
  final String name;
}

/// `post.analysis`, only present on `GET /api/posts/:id`.
class PostAnalysis {
  const PostAnalysis({
    required this.transcript,
    required this.overallSummary,
    required this.claims,
  });

  factory PostAnalysis.fromJson(Map<String, dynamic> json) => PostAnalysis(
        transcript: json['transcript'] as String?,
        overallSummary: json['overallSummary'] as String?,
        claims: [
          for (final c in (json['claims'] as List<dynamic>? ?? const []))
            if (c is Map<String, dynamic>) c,
        ],
      );

  final String? transcript;
  final String? overallSummary;
  final List<Map<String, dynamic>> claims;
}

class Post {
  const Post({
    required this.id,
    required this.kind,
    required this.parentId,
    required this.rootId,
    required this.depth,
    required this.title,
    required this.body,
    required this.mediaUrl,
    required this.stance,
    required this.status,
    required this.summary,
    required this.createdAt,
    required this.likeCount,
    required this.likedByMe,
    required this.replyCount,
    required this.forCount,
    required this.againstCount,
    this.analysis,
    this.hasCaptions = false,
    this.coverUrl,
    this.promptDay,
    this.room,
    this.roomStance,
  });

  factory Post.fromJson(Map<String, dynamic> json) => Post(
        id: json['id'] as String,
        kind: PostKind.parse(json['kind'] as String),
        parentId: json['parentId'] as String?,
        rootId: json['rootId'] as String,
        depth: (json['depth'] as num).toInt(),
        title: json['title'] as String?,
        body: json['body'] as String?,
        mediaUrl: json['mediaUrl'] as String?,
        stance: Stance.parse(json['stance'] as String),
        status: PostStatus.parse(json['status'] as String),
        summary: json['summary'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        likeCount: (json['likeCount'] as num).toInt(),
        likedByMe: json['likedByMe'] as bool,
        replyCount: (json['replyCount'] as num).toInt(),
        forCount: (json['forCount'] as num).toInt(),
        againstCount: (json['againstCount'] as num).toInt(),
        analysis: json['analysis'] is Map<String, dynamic>
            ? PostAnalysis.fromJson(json['analysis'] as Map<String, dynamic>)
            : null,
        hasCaptions: json['hasCaptions'] == true,
        coverUrl: json['coverUrl'] as String?,
        promptDay: json['promptDay'] as String?,
        room: json['room'] is Map<String, dynamic>
            ? PostRoom(id: (json['room'] as Map<String, dynamic>)['id'] as String, name: (json['room'] as Map<String, dynamic>)['name'] as String)
            : null,
        roomStance: json['roomStance'] is String ? _stanceOrNull(json['roomStance'] as String) : null,
      );

  final String id;
  final PostKind kind;

  /// The post this directly replies to; null for an opinion.
  final String? parentId;

  /// The opinion that started the debate (equal to [id] for a root).
  final String rootId;

  /// 0 opinion, 1 reply, 2 reply-to-a-reply, ...
  final int depth;

  /// Roots only.
  final String? title;

  /// Text reply, or an optional caption (max 280 chars).
  final String? body;

  /// Relative (`/uploads/x.mp4`); resolve it against the server's base URL.
  final String? mediaUrl;
  final Stance stance;
  final PostStatus status;

  /// Gemini's overallSummary, once analysed.
  final String? summary;
  final DateTime createdAt;
  final int likeCount;
  final bool likedByMe;

  /// ALL replies below this post, direct and indirect.
  final int replyCount;
  final int forCount;
  final int againstCount;
  final PostAnalysis? analysis;

  /// The video has subtitle lines (GET /api/posts/:id/captions).
  final bool hasCaptions;

  /// A picture of the video to show before it plays (relative, like [mediaUrl]); editor posts have one.
  final String? coverUrl;

  /// The day (`YYYY-MM-DD`) of the daily question this opinion answers.
  final String? promptDay;

  /// The motion room this opinion was posted into, and (once the AI has read it) which side of the motion it takes.
  final PostRoom? room;
  final Stance? roomStance;

  static Stance? _stanceOrNull(String wire) {
    for (final s in Stance.values) {
      if (s.wire == wire) return s;
    }
    return null;
  }

  bool get isRoot => parentId == null;

  Post copyWith({
    PostStatus? status,
    Stance? stance,
    String? mediaUrl,
    String? summary,
    int? likeCount,
    bool? likedByMe,
    int? replyCount,
    int? forCount,
    int? againstCount,
  }) =>
      Post(
        id: id,
        kind: kind,
        parentId: parentId,
        rootId: rootId,
        depth: depth,
        title: title,
        body: body,
        mediaUrl: mediaUrl ?? this.mediaUrl,
        stance: stance ?? this.stance,
        status: status ?? this.status,
        summary: summary ?? this.summary,
        createdAt: createdAt,
        likeCount: likeCount ?? this.likeCount,
        likedByMe: likedByMe ?? this.likedByMe,
        replyCount: replyCount ?? this.replyCount,
        forCount: forCount ?? this.forCount,
        againstCount: againstCount ?? this.againstCount,
        analysis: analysis,
        hasCaptions: hasCaptions,
        coverUrl: coverUrl,
        promptDay: promptDay,
        room: room,
        roomStance: roomStance,
      );
}
