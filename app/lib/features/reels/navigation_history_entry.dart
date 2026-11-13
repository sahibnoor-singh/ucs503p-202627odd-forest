import '../../models/video.dart';

/// Represents a snapshot of the user's navigation position in FORREST:
/// - Exact video that was playing
/// - Root video of the debate tree
/// - Position in personalized main feed
/// - Path taken down the debate tree hierarchy
/// - Exact reply counts displayed at that moment
class NavigationHistoryEntry {
  const NavigationHistoryEntry({
    required this.video,
    required this.rootVideo,
    required this.mainFeedIndex,
    required this.debateTreePath,
    required this.rootDebateId,
    this.forCount = 0,
    this.againstCount = 0,
  });

  final Video video;
  final Video rootVideo;
  final int mainFeedIndex;
  final List<String> debateTreePath;
  final String rootDebateId;
  final int forCount;
  final int againstCount;

  @override
  String toString() =>
      'NavigationHistoryEntry(videoId: ${video.id}, rootId: $rootDebateId, feedIdx: $mainFeedIndex, depth: ${debateTreePath.length})';
}
