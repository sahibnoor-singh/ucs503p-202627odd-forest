import '../../models/post.dart';
import '../../models/user.dart';

/// Personality section of a user's profile.
class Personality {
  const Personality({
    this.keywords = const [],
    this.summary,
    this.summaryApproved = false,
    this.interests = const [],
  });

  factory Personality.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const Personality();
    return Personality(
      keywords: (json['keywords'] as List<dynamic>?)?.cast<String>() ?? const [],
      summary: json['summary'] as String?,
      summaryApproved: json['summaryApproved'] == true,
      interests: (json['interests'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }

  final List<String> keywords;
  final String? summary;
  final bool summaryApproved;
  final List<String> interests;

  bool get hasSummary => summary != null && summary!.isNotEmpty;
  bool get hasKeywords => keywords.isNotEmpty;
  bool get hasInterests => interests.isNotEmpty;
  bool get isEmpty => !hasKeywords && !hasSummary && !hasInterests;
}

/// Credibility information for a user.
class UserCredibility {
  const UserCredibility({
    this.score,
    this.analyzedVideos = 0,
    this.totalClaims = 0,
    this.verdictDistribution = const {},
    this.sufficient = false,
  });

  factory UserCredibility.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const UserCredibility();
    return UserCredibility(
      score: (json['score'] as num?)?.toDouble(),
      analyzedVideos: (json['analyzedVideos'] as num?)?.toInt() ?? 0,
      totalClaims: (json['totalClaims'] as num?)?.toInt() ?? 0,
      verdictDistribution: (json['verdictDistribution'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toInt())) ??
          const {},
      sufficient: json['sufficient'] == true,
    );
  }

  final double? score;
  final int analyzedVideos;
  final int totalClaims;
  final Map<String, int> verdictDistribution;
  final bool sufficient;

  /// Score as a 0-100 integer, or null if not sufficient.
  int? get scorePercent => (score != null && sufficient) ? (score! * 100).round().clamp(0, 100) : null;
}

/// Contribution stats.
class Contributions {
  const Contributions({
    this.totalPosts = 0,
    this.analyzedPosts = 0,
    this.totalReplies = 0,
    this.debatesStarted = 0,
  });

  factory Contributions.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const Contributions();
    return Contributions(
      totalPosts: (json['totalPosts'] as num?)?.toInt() ?? 0,
      analyzedPosts: (json['analyzedPosts'] as num?)?.toInt() ?? 0,
      totalReplies: (json['totalReplies'] as num?)?.toInt() ?? 0,
      debatesStarted: (json['debatesStarted'] as num?)?.toInt() ?? 0,
    );
  }

  final int totalPosts;
  final int analyzedPosts;
  final int totalReplies;
  final int debatesStarted;

  bool get isEmpty => totalPosts == 0 && totalReplies == 0;
}

/// Full profile data from GET /api/users/:id/profile.
class UserProfile {
  const UserProfile({
    required this.user,
    this.bio,
    required this.followerCount,
    required this.followingCount,
    required this.postCount,
    required this.followedByMe,
    required this.blockedByMe,
    required this.isMe,
    required this.personality,
    required this.credibility,
    required this.contributions,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        user: User.fromJson(json['user'] as Map<String, dynamic>),
        bio: json['bio'] as String?,
        followerCount: (json['followerCount'] as num).toInt(),
        followingCount: (json['followingCount'] as num).toInt(),
        postCount: (json['postCount'] as num).toInt(),
        followedByMe: json['followedByMe'] as bool,
        blockedByMe: json['blockedByMe'] as bool,
        isMe: json['isMe'] as bool,
        personality: Personality.fromJson(json['personality'] as Map<String, dynamic>?),
        credibility: UserCredibility.fromJson(json['credibility'] as Map<String, dynamic>?),
        contributions: Contributions.fromJson(json['contributions'] as Map<String, dynamic>?),
      );

  final User user;
  final String? bio;
  final int followerCount;
  final int followingCount;
  final int postCount;
  final bool followedByMe;
  final bool blockedByMe;
  final bool isMe;
  final Personality personality;
  final UserCredibility credibility;
  final Contributions contributions;
}

/// A user's video in their profile grid.
class ProfilePost {
  const ProfilePost({required this.actor, required this.post});

  factory ProfilePost.fromJson(Map<String, dynamic> json) => ProfilePost(
        actor: User.fromJson(json['actor'] as Map<String, dynamic>),
        post: Post.fromJson(json['post'] as Map<String, dynamic>),
      );

  final User actor;
  final Post post;
}

/// A bookmarked post (saved tree).
class Bookmark {
  const Bookmark({required this.actor, required this.post, required this.savedAt});

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
        actor: User.fromJson(json['actor'] as Map<String, dynamic>),
        post: Post.fromJson(json['post'] as Map<String, dynamic>),
        savedAt: DateTime.parse(json['savedAt'] as String),
      );

  final User actor;
  final Post post;
  final DateTime savedAt;
}

/// A follower or following entry.
class FollowEntry {
  const FollowEntry({required this.user, required this.followedByMe});

  factory FollowEntry.fromJson(Map<String, dynamic> json) => FollowEntry(
        user: User.fromJson(json['user'] as Map<String, dynamic>),
        followedByMe: json['followedByMe'] as bool,
      );

  final User user;
  final bool followedByMe;
}
