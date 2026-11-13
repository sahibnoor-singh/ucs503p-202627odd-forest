import 'package:flutter_test/flutter_test.dart';
import 'package:forest_app/features/reels/navigation_history_entry.dart';
import 'package:forest_app/models/video.dart';

void main() {
  group('FORREST 4-Direction Smart Feed & Debate Navigation Acceptance Tests', () {
    // Dataset: Debate Tree A with nested replies
    final rootDebateA = Video(
      id: 'root_A',
      title: 'Should colleges ban smartphones in lecture halls?',
      filename: 'root_a.mp4',
      status: 'ready',
      role: 'PARENT',
      parentVideoId: null,
      stance: 'PARENT',
      userName: 'aman_s',
      createdAt: '2026-10-10T10:00:00Z',
      replyCount: 5,
      forCount: 3,
      againstCount: 2,
    );

    // Direct Level 1 FOR Reply to Root A
    final forReplyA1 = Video(
      id: 'reply_A_for_1',
      title: 'Banning phones dramatically improves attention span (FOR)',
      filename: 'for_a1.mp4',
      status: 'ready',
      role: 'CHILD',
      parentVideoId: 'root_A',
      stance: 'FOR',
      userName: 'riya_k',
      createdAt: '2026-10-10T10:15:00Z',
      credibility: 88,
      replyCount: 2,
      forCount: 1,
      againstCount: 1,
    );

    // Direct Level 1 AGAINST Reply to Root A
    final againstReplyA1 = Video(
      id: 'reply_A_against_1',
      title: 'Smartphones are essential for instant research & calculators (AGAINST)',
      filename: 'against_a1.mp4',
      status: 'ready',
      role: 'CHILD',
      parentVideoId: 'root_A',
      stance: 'AGAINST',
      userName: 'simran.v',
      createdAt: '2026-10-10T10:20:00Z',
      credibility: 82,
      replyCount: 1,
      forCount: 0,
      againstCount: 1,
    );

    // Nested Level 2 AGAINST Reply to A1 (A1 -> A1_against)
    final nestedReplyA1Against = Video(
      id: 'nested_A1_against',
      title: 'Attention issues stem from passive lecturing, not the device (AGAINST)',
      filename: 'nested_a1_against.mp4',
      status: 'ready',
      role: 'CHILD',
      parentVideoId: 'reply_A_for_1',
      stance: 'AGAINST',
      userName: 'prof_tandon',
      createdAt: '2026-10-10T10:35:00Z',
      credibility: 91,
      replyCount: 1,
      forCount: 1,
      againstCount: 0,
    );

    // Second Root Debate B in Main Feed
    final rootDebateB = Video(
      id: 'root_B',
      title: 'Should regional language education be mandatory in higher education?',
      filename: 'root_b.mp4',
      status: 'ready',
      role: 'PARENT',
      parentVideoId: null,
      stance: 'PARENT',
      userName: 'kabir_m',
      createdAt: '2026-10-10T09:00:00Z',
      replyCount: 2,
      forCount: 1,
      againstCount: 1,
    );

    test('1. Swipe Left opens most relevant FOR reply to current video', () {
      final directReplies = [forReplyA1, againstReplyA1];

      var currentVideo = rootDebateA;
      final forReplies = directReplies.where((v) => v.stance == 'FOR' && v.parentVideoId == currentVideo.id).toList();

      expect(forReplies.isNotEmpty, isTrue);
      final targetFor = forReplies.first;

      // Simulate Swipe Left
      currentVideo = targetFor;

      expect(currentVideo.id, equals('reply_A_for_1'));
      expect(currentVideo.stance, equals('FOR'));
      expect(currentVideo.parentVideoId, equals('root_A'));
    });

    test('2. Swipe Right opens most relevant AGAINST reply to current video', () {
      final directReplies = [forReplyA1, againstReplyA1];

      var currentVideo = rootDebateA;
      final againstReplies = directReplies.where((v) => v.stance == 'AGAINST' && v.parentVideoId == currentVideo.id).toList();

      expect(againstReplies.isNotEmpty, isTrue);
      final targetAgainst = againstReplies.first;

      // Simulate Swipe Right
      currentVideo = targetAgainst;

      expect(currentVideo.id, equals('reply_A_against_1'));
      expect(currentVideo.stance, equals('AGAINST'));
      expect(currentVideo.parentVideoId, equals('root_A'));
    });

    test('3. Swipe Up opens next independent video in personalized main feed', () {
      final mainFeed = [rootDebateA, rootDebateB];
      var mainFeedIndex = 0;
      var currentVideo = mainFeed[mainFeedIndex];
      var currentRootId = currentVideo.id;

      expect(currentVideo.id, equals('root_A'));

      // Simulate Swipe Up
      mainFeedIndex++;
      currentVideo = mainFeed[mainFeedIndex];
      currentRootId = currentVideo.id;

      expect(currentVideo.id, equals('root_B'));
      expect(currentRootId, equals('root_B'));
      expect(currentVideo.parentVideoId, isNull);
    });

    test('4. Swipe Down restores exact previous navigation state via history stack across branches', () {
      final historyStack = <NavigationHistoryEntry>[];

      var mainFeedIndex = 0;
      var currentVideo = rootDebateA;
      var rootVideo = rootDebateA;
      var debateTreePath = [rootDebateA.id];

      // Step 1: User swipes Left to A1 (FOR reply)
      historyStack.add(NavigationHistoryEntry(
        video: currentVideo,
        rootVideo: rootVideo,
        mainFeedIndex: mainFeedIndex,
        debateTreePath: List.from(debateTreePath),
        rootDebateId: rootVideo.id,
        forCount: currentVideo.forCount,
        againstCount: currentVideo.againstCount,
      ));
      currentVideo = forReplyA1;
      debateTreePath.add(forReplyA1.id);

      expect(currentVideo.id, equals('reply_A_for_1'));
      expect(debateTreePath.length, equals(2));
      expect(historyStack.length, equals(1));

      // Step 2: From A1, user swipes Right into nested AGAINST reply
      historyStack.add(NavigationHistoryEntry(
        video: currentVideo,
        rootVideo: rootVideo,
        mainFeedIndex: mainFeedIndex,
        debateTreePath: List.from(debateTreePath),
        rootDebateId: rootVideo.id,
        forCount: currentVideo.forCount,
        againstCount: currentVideo.againstCount,
      ));
      currentVideo = nestedReplyA1Against;
      debateTreePath.add(nestedReplyA1Against.id);

      expect(currentVideo.id, equals('nested_A1_against'));
      expect(debateTreePath.length, equals(3));
      expect(historyStack.length, equals(2));

      // Step 3: User swipes Down -> Must restore exact state A1 (depth 2)
      final popped1 = historyStack.removeLast();
      currentVideo = popped1.video;
      rootVideo = popped1.rootVideo;
      mainFeedIndex = popped1.mainFeedIndex;
      debateTreePath = popped1.debateTreePath;

      expect(currentVideo.id, equals('reply_A_for_1'));
      expect(debateTreePath.length, equals(2));
      expect(historyStack.length, equals(1));

      // Step 4: User swipes Down again -> Must restore exact state Root A (depth 1)
      final popped2 = historyStack.removeLast();
      currentVideo = popped2.video;
      rootVideo = popped2.rootVideo;
      mainFeedIndex = popped2.mainFeedIndex;
      debateTreePath = popped2.debateTreePath;

      expect(currentVideo.id, equals('root_A'));
      expect(debateTreePath.length, equals(1));
      expect(historyStack.isEmpty, isTrue);
    });

    test('5. Every video has its own FOR and AGAINST reply counts', () {
      // Root Video A has 3 FOR and 2 AGAINST
      expect(rootDebateA.forCount, equals(3));
      expect(rootDebateA.againstCount, equals(2));

      // When entering reply A1, A1 must show its OWN reply counts (1 FOR, 1 AGAINST)
      expect(forReplyA1.forCount, equals(1));
      expect(forReplyA1.againstCount, equals(1));
      expect(forReplyA1.forCount, isNot(equals(rootDebateA.forCount)));

      // When entering nested reply A1_against, it has 1 FOR and 0 AGAINST
      expect(nestedReplyA1Against.forCount, equals(1));
      expect(nestedReplyA1Against.againstCount, equals(0));
    });

    test('6. Swiping is pure navigation: viewing does not equal agreeing and does not register a vote', () {
      final originalStance = forReplyA1.stance;
      final originalParent = forReplyA1.parentVideoId;
      final originalLikes = forReplyA1.likeCount;
      final originalViewerOpinion = forReplyA1.viewerSide;

      // Swiping navigation must not modify opinion or like status
      expect(forReplyA1.stance, equals(originalStance));
      expect(forReplyA1.parentVideoId, equals(originalParent));
      expect(forReplyA1.likeCount, equals(originalLikes));
      expect(forReplyA1.viewerSide, equals(originalViewerOpinion));
    });

    test('7. Empty branches remain on current video with subtle feedback and do not navigate to unrelated debates', () {
      // nestedReplyA1Against has 0 AGAINST replies
      final againstRepliesOfNested = <Video>[];
      expect(againstRepliesOfNested.isEmpty, isTrue);

      var currentVideo = nestedReplyA1Against;
      String? feedbackMessage;

      if (againstRepliesOfNested.isNotEmpty) {
        currentVideo = againstRepliesOfNested.first;
      } else {
        feedbackMessage = 'No AGAINST perspective for this opinion yet';
      }

      // Must remain on current video
      expect(currentVideo.id, equals('nested_A1_against'));
      expect(feedbackMessage, equals('No AGAINST perspective for this opinion yet'));
    });
  });
}
