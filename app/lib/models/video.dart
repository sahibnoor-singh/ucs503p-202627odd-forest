import 'caption_cue.dart';

/// Full Video domain model reflecting database schema and API contracts.
class Video {
  final String id;
  final String? title;
  final String caption;
  final String filename;

  /// Server path of a still picture of the video (`/uploads/...`), or null when it has none (use [ReelsRepository.coverUrl]).
  final String? coverUrl;
  final String status;
  final String role; // PARENT | CHILD
  final String? parentVideoId;
  final String stance; // PARENT | FOR | AGAINST | UNRESOLVED
  final int credibility;
  final int durationS;
  final String? userId;
  final String userName;

  /// The author's account id (what block and report need; [userId] is their username). Null from an older server.
  final String? authorId;

  /// The author's profile picture (a server path), or null: shown beside the name on a video.
  final String? authorAvatarUrl;

  /// The viewer already follows the author (the Follow button is hidden then). False when the server does not say.
  final bool authorFollowed;

  /// Posted by an automated account: always shown with a BOT label (CLAUDE.md hard rule).
  final bool isBot;

  /// Why Discover picked this for the person: a friend's username ("picked by riya's taste"), or null.
  final String? pickedBy;

  /// Discover put this here to show something outside the person's usual topics.
  final bool exploring;
  final String createdAt;
  final int likeCount;
  final int replyCount;
  final int forCount;
  final int againstCount;
  final String? viewerSide; // FOR | AGAINST
  final bool isLiked;

  /// Short text for the post body (X-style caption), pulled from the Gemini
  /// analysis stored in `transcript` — overallSummary first, falling back to
  /// the raw transcript text. Null while processing or if analysis failed.
  final String? summary;

  /// Subtitle lines (inside the analysis the feed sends as `transcript`). Empty when there is no speech.
  final List<CaptionCue> captions;

  Video({
    required this.id,
    this.title,
    this.caption = '',
    required this.filename,
    this.coverUrl,
    required this.status,
    required this.role,
    this.parentVideoId,
    required this.stance,
    this.credibility = 50,
    this.durationS = 0,
    this.userId,
    this.userName = 'kabir_m',
    this.authorId,
    this.authorAvatarUrl,
    this.authorFollowed = false,
    this.isBot = false,
    this.pickedBy,
    this.exploring = false,
    required this.createdAt,
    this.likeCount = 0,
    this.replyCount = 0,
    this.forCount = 0,
    this.againstCount = 0,
    this.viewerSide,
    this.isLiked = false,
    this.summary,
    this.captions = const [],
  });

  factory Video.fromJson(Map<String, dynamic> json) {
    final title = json['title'] as String?;
    final caption = json['caption'] as String? ?? title ?? '';
    final userId = json['user_id'] as String? ?? json['userId'] as String?;
    final userName = json['userName'] as String? ?? userId ?? 'kabir_m';

    int parseInt(dynamic val, [int fallback = 0]) {
      if (val == null) return fallback;
      if (val is int) return val;
      if (val is num) return val.toInt();
      return int.tryParse(val.toString()) ?? fallback;
    }

    return Video(
      id: json['id']?.toString() ?? '',
      title: title,
      caption: caption,
      filename: json['filename'] as String? ?? '',
      coverUrl: _nonEmpty(json['coverUrl']),
      status: (json['status'] as String? ?? 'ready').toLowerCase(),
      role: (json['role'] as String? ?? 'PARENT').toUpperCase(),
      parentVideoId: (json['parent_video_id'] ?? json['parentVideoId'])?.toString(),
      stance: (json['stance'] as String? ?? 'PARENT').toUpperCase(),
      credibility: parseInt(json['credibility'], 50),
      durationS: parseInt(json['duration_s'] ?? json['durationS'], 0),
      userId: userId,
      userName: userName,
      authorId: _nonEmpty(json['authorId']),
      authorAvatarUrl: _nonEmpty(json['authorAvatarUrl']),
      authorFollowed: json['authorFollowed'] == true,
      isBot: json['isBot'] == true,
      pickedBy: _whyFriend(json['why']),
      exploring: _whyKind(json['why']) == 'explore',
      createdAt: json['created_at']?.toString() ?? json['createdAt']?.toString() ?? '',
      likeCount: parseInt(json['likeCount'] ?? json['like_count'], 0),
      replyCount: parseInt(json['replyCount'] ?? json['reply_count'], 0),
      forCount: parseInt(json['forCount'] ?? json['for_count'], 0),
      againstCount: parseInt(json['againstCount'] ?? json['against_count'], 0),
      viewerSide: json['viewerSide'] as String?,
      isLiked: json['liked'] == true || json['isLiked'] == true,
      summary: _summaryFrom(json['transcript']),
      captions: CaptionCue.listFrom(json['transcript'] is Map ? (json['transcript'] as Map)['captions'] : null),
    );
  }

  /// What to call this video on screen: its title or caption, else the start of the AI summary, else who made it. Never the raw id.
  String get displayTitle {
    if (title != null && title!.trim().isNotEmpty) return title!.trim();
    if (caption.trim().isNotEmpty) return caption.trim();
    final sum = summary?.trim();
    if (sum != null && sum.isNotEmpty) return sum.length > 120 ? '${sum.substring(0, 117).trimRight()}…' : sum;
    return role == 'CHILD' ? 'Video reply by @$userName' : 'Video by @$userName';
  }

  Video copyWith({
    String? id,
    String? title,
    String? caption,
    String? filename,
    String? coverUrl,
    String? status,
    String? role,
    String? parentVideoId,
    String? stance,
    int? credibility,
    int? durationS,
    String? userId,
    String? userName,
    String? authorId,
    String? authorAvatarUrl,
    bool? authorFollowed,
    bool? isBot,
    String? pickedBy,
    bool? exploring,
    String? createdAt,
    int? likeCount,
    int? replyCount,
    int? forCount,
    int? againstCount,
    String? viewerSide,
    bool? isLiked,
    String? summary,
    List<CaptionCue>? captions,
  }) {
    return Video(
      id: id ?? this.id,
      title: title ?? this.title,
      caption: caption ?? this.caption,
      filename: filename ?? this.filename,
      coverUrl: coverUrl ?? this.coverUrl,
      status: status ?? this.status,
      role: role ?? this.role,
      parentVideoId: parentVideoId ?? this.parentVideoId,
      stance: stance ?? this.stance,
      credibility: credibility ?? this.credibility,
      durationS: durationS ?? this.durationS,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      authorId: authorId ?? this.authorId,
      authorAvatarUrl: authorAvatarUrl ?? this.authorAvatarUrl,
      authorFollowed: authorFollowed ?? this.authorFollowed,
      isBot: isBot ?? this.isBot,
      pickedBy: pickedBy ?? this.pickedBy,
      exploring: exploring ?? this.exploring,
      createdAt: createdAt ?? this.createdAt,
      likeCount: likeCount ?? this.likeCount,
      replyCount: replyCount ?? this.replyCount,
      forCount: forCount ?? this.forCount,
      againstCount: againstCount ?? this.againstCount,
      viewerSide: viewerSide ?? this.viewerSide,
      isLiked: isLiked ?? this.isLiked,
      summary: summary ?? this.summary,
      captions: captions ?? this.captions,
    );
  }

  static String? _whyKind(Object? why) => why is Map ? why['kind'] as String? : null;

  static String? _whyFriend(Object? why) => why is Map && why['kind'] == 'friend' ? _nonEmpty(why['by']) : null;

  static String? _nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;

  /// `transcript` comes back from GET /api/videos/all already JSON-parsed
  /// (see getAllVideos in Website/backend/models/db.js), but older rows may
  /// be a plain string — handle both.
  static String? _summaryFrom(Object? transcript) {
    String? pick(Object? v) =>
        v is String && v.trim().isNotEmpty ? v.trim() : null;
    if (transcript is Map) {
      return pick(transcript['overallSummary']) ?? pick(transcript['transcript']);
    }
    return pick(transcript);
  }
}
