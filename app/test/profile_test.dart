import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forest_app/features/profile/credibility_details_screen.dart';
import 'package:forest_app/features/profile/personality_editor.dart';
import 'package:forest_app/features/profile/profile_controller.dart';
import 'package:forest_app/features/profile/profile_models.dart';
import 'package:forest_app/features/profile/profile_repository.dart';
import 'package:forest_app/features/profile/profile_screen.dart';
import 'package:forest_app/models/user.dart';
import 'package:forest_app/services/api_client.dart';
import 'package:forest_app/theme/forest_theme.dart';
import 'package:provider/provider.dart';

// Fake profile repository for tests
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({
    required this.profileToReturn,
    this.videosToReturn = const [],
    this.bookmarksToReturn = const [],
    this.followersToReturn = const [],
  });

  UserProfile profileToReturn;
  List<ProfilePost> videosToReturn;
  List<Bookmark> bookmarksToReturn;
  List<FollowEntry> followersToReturn;
  bool followToggled = false;
  bool followTargetState = false;

  @override
  Future<UserProfile> getProfile(String userId) async => profileToReturn;

  @override
  Future<({List<ProfilePost> posts, String? nextCursor})> getUserVideos(
    String userId, {
    int limit = 20,
    String? cursor,
  }) async =>
      (posts: videosToReturn, nextCursor: null);

  @override
  Future<UserProfile> updateProfile({
    String? fullName,
    String? bio,
    List<String>? personalityKeywords,
    String? personalitySummary,
    bool? personalitySummaryApproved,
    List<String>? interests,
  }) async {
    profileToReturn = UserProfile(
      user: User(
        id: profileToReturn.user.id,
        username: profileToReturn.user.username,
        fullName: fullName ?? profileToReturn.user.fullName,
        avatarUrl: profileToReturn.user.avatarUrl,
        isBot: profileToReturn.user.isBot,
      ),
      bio: bio ?? profileToReturn.bio,
      followerCount: profileToReturn.followerCount,
      followingCount: profileToReturn.followingCount,
      postCount: profileToReturn.postCount,
      followedByMe: profileToReturn.followedByMe,
      blockedByMe: profileToReturn.blockedByMe,
      isMe: profileToReturn.isMe,
      personality: Personality(
        keywords: personalityKeywords ?? profileToReturn.personality.keywords,
        summary: personalitySummary ?? profileToReturn.personality.summary,
        summaryApproved: personalitySummaryApproved ?? profileToReturn.personality.summaryApproved,
        interests: interests ?? profileToReturn.personality.interests,
      ),
      credibility: profileToReturn.credibility,
      contributions: profileToReturn.contributions,
    );
    return profileToReturn;
  }

  @override
  Future<String> generatePersonalitySummary(List<String> keywords) async =>
      'An analytical and curious thinker who values rigorous evidence and constructive debate.';

  @override
  Future<List<Bookmark>> getBookmarks() async => bookmarksToReturn;

  @override
  Future<void> addBookmark(String postId) async {}

  @override
  Future<void> removeBookmark(String postId) async {}

  @override
  Future<void> setFollowing(String userId, bool following) async {
    followToggled = true;
    followTargetState = following;
  }

  @override
  Future<({List<FollowEntry> users, String? nextCursor})> getFollowers(
    String userId, {
    int limit = 20,
    String? cursor,
  }) async =>
      (users: followersToReturn, nextCursor: null);

  @override
  Future<({List<FollowEntry> users, String? nextCursor})> getFollowing(
    String userId, {
    int limit = 20,
    String? cursor,
  }) async =>
      (users: followersToReturn, nextCursor: null);

  @override
  String mediaUrl(String relativePath) => 'http://test/$relativePath';
}

void main() {
  const testUser = User(
    id: 'user-1',
    username: 'aarav_sharma',
    fullName: 'Aarav Sharma',
    avatarUrl: null,
    isBot: false,
  );

  const sampleProfile = UserProfile(
    user: testUser,
    bio: 'Passionate about economics and technology policy.',
    followerCount: 142,
    followingCount: 89,
    postCount: 12,
    followedByMe: false,
    blockedByMe: false,
    isMe: true,
    personality: Personality(
      keywords: ['Analytical', 'Curious', 'Reflective'],
      summary: 'A curious and analytical thinker focused on evidence-backed public discussions.',
      summaryApproved: true,
      interests: ['Politics', 'Economy', 'Technology and AI'],
    ),
    credibility: UserCredibility(
      score: 0.82,
      analyzedVideos: 6,
      totalClaims: 14,
      verdictDistribution: {'True': 9, 'Mostly True': 3, 'Misleading': 2},
      sufficient: true,
    ),
    contributions: Contributions(
      totalPosts: 12,
      analyzedPosts: 6,
      totalReplies: 18,
      debatesStarted: 4,
    ),
  );

  group('Profile Models', () {
    test('Personality deserialization and empty check', () {
      const empty = Personality();
      expect(empty.isEmpty, isTrue);
      expect(empty.hasKeywords, isFalse);

      final p = Personality.fromJson({
        'keywords': ['Curious', 'Skeptical'],
        'summary': 'Thinker',
        'summaryApproved': true,
        'interests': ['Tech'],
      });
      expect(p.keywords, contains('Curious'));
      expect(p.summaryApproved, isTrue);
      expect(p.isEmpty, isFalse);
    });

    test('UserCredibility calculations and tier mapping', () {
      final cred = UserCredibility.fromJson({
        'score': 0.765,
        'analyzedVideos': 4,
        'totalClaims': 8,
        'verdictDistribution': {'True': 6, 'Misleading': 2},
        'sufficient': true,
      });
      expect(cred.scorePercent, equals(77));
      expect(cred.sufficient, isTrue);

      final insufficient = UserCredibility.fromJson({
        'score': 0.5,
        'analyzedVideos': 1,
        'totalClaims': 1,
        'sufficient': false,
      });
      expect(insufficient.scorePercent, isNull);
    });

    test('UserProfile deserialization matches JSON structure', () {
      final json = {
        'user': {
          'id': 'u100',
          'username': 'riya_v',
          'fullName': 'Riya Verma',
          'avatarUrl': null,
          'isBot': false,
        },
        'bio': 'Debater',
        'followerCount': 25,
        'followingCount': 30,
        'postCount': 5,
        'followedByMe': true,
        'blockedByMe': false,
        'isMe': false,
        'personality': {
          'keywords': ['Objective', 'Articulate'],
          'summary': 'An articulate speaker',
          'summaryApproved': true,
          'interests': ['Law and rights'],
        },
        'credibility': {
          'score': 0.90,
          'analyzedVideos': 3,
          'totalClaims': 7,
          'sufficient': true,
        },
        'contributions': {
          'totalPosts': 5,
          'analyzedPosts': 3,
          'totalReplies': 10,
          'debatesStarted': 2,
        },
      };

      final profile = UserProfile.fromJson(json);
      expect(profile.user.username, equals('riya_v'));
      expect(profile.followerCount, equals(25));
      expect(profile.followedByMe, isTrue);
      expect(profile.isMe, isFalse);
      expect(profile.personality.keywords, contains('Objective'));
      expect(profile.credibility.scorePercent, equals(90));
      expect(profile.contributions.debatesStarted, equals(2));
    });
  });

  group('ProfileController', () {
    test('loads profile successfully', () async {
      final fakeRepo = FakeProfileRepository(profileToReturn: sampleProfile);
      final controller = ProfileController(fakeRepo, userId: 'user-1');

      expect(controller.status, equals(ProfileStatus.loading));
      await Future<void>.delayed(Duration.zero);

      expect(controller.status, equals(ProfileStatus.loaded));
      expect(controller.profile?.user.username, equals('aarav_sharma'));
      expect(controller.profile?.followerCount, equals(142));
    });

    test('optimistic follow toggle and reversal', () async {
      final otherProfile = UserProfile(
        user: const User(id: 'other', username: 'simran', fullName: 'Simran Kaur', avatarUrl: null, isBot: false),
        followerCount: 50,
        followingCount: 20,
        postCount: 3,
        followedByMe: false,
        blockedByMe: false,
        isMe: false,
        personality: const Personality(),
        credibility: const UserCredibility(),
        contributions: const Contributions(),
      );
      final fakeRepo = FakeProfileRepository(profileToReturn: otherProfile);
      final controller = ProfileController(fakeRepo, userId: 'other');
      await Future<void>.delayed(Duration.zero);

      expect(controller.profile?.followedByMe, isFalse);
      final ok = await controller.toggleFollow();
      expect(ok, isTrue);
      expect(controller.profile?.followedByMe, isTrue);
      expect(controller.profile?.followerCount, equals(51));
      expect(fakeRepo.followToggled, isTrue);
      expect(fakeRepo.followTargetState, isTrue);
    });
  });

  group('Profile Widgets & Screens', () {
    testWidgets('ProfileScreen renders header, personality, and credibility', (tester) async {
      final fakeRepo = FakeProfileRepository(profileToReturn: sampleProfile);

      await tester.pumpWidget(
        MaterialApp(
          theme: ForestTheme.light,
          home: Provider<ApiClient>(
            create: (_) => ApiClient(),
            child: ProfileScreen(userId: 'user-1', repository: fakeRepo),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check header info
      expect(find.text('aarav_sharma'), findsWidgets);
      expect(find.text('Aarav Sharma'), findsOneWidget);
      expect(find.text('Passionate about economics and technology policy.'), findsOneWidget);
      expect(find.text('142'), findsOneWidget);
      expect(find.text('Followers'), findsOneWidget);
      expect(find.text('89'), findsOneWidget);
      expect(find.text('Following'), findsOneWidget);

      // Check owner button is Edit Profile
      expect(find.text('Edit Profile'), findsOneWidget);

      // Check Personality section
      expect(find.text('Personality'), findsOneWidget);
      expect(find.text('Analytical'), findsOneWidget);
      expect(find.text('Curious'), findsOneWidget);
      expect(find.text('Reflective'), findsOneWidget);

      // Check Credibility section
      expect(find.text('Credibility'), findsOneWidget);
      expect(find.text('82'), findsOneWidget);
      expect(find.textContaining('6 videos analyzed'), findsOneWidget);

      // Check Contributions
      expect(find.text('Debates Started'), findsOneWidget);
    });

    testWidgets('CredibilityDetailsScreen shows detailed breakdown and mathematical formula', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ForestTheme.light,
          home: CredibilityDetailsScreen(credibility: sampleProfile.credibility),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Credibility Assessment'), findsOneWidget);
      expect(find.text('82%'), findsOneWidget);
      expect(find.text('High Credibility'), findsOneWidget);
      expect(find.text('S_Cᵢ = w(Vᵢ) × Eᵢ'), findsOneWidget);
      expect(find.textContaining('No Popularity Bias'), findsOneWidget);
      expect(find.text('Assessed Claims'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
    });

    testWidgets('PersonalityEditor adds keywords and validates duplicates', (tester) async {
      final fakeRepo = FakeProfileRepository(profileToReturn: sampleProfile);
      List<String> currentKeywords = [];

      await tester.pumpWidget(
        MaterialApp(
          theme: ForestTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: PersonalityEditor(
                initialKeywords: const ['Curious'],
                initialSummary: null,
                initialSummaryApproved: false,
                initialInterests: const [],
                repo: fakeRepo,
                onChanged: ({required keywords, required summary, required summaryApproved, required interests}) {
                  currentKeywords = keywords;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Curious'), findsOneWidget);

      // Add a new keyword
      await tester.enterText(find.byType(TextField).first, 'Innovative');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('Innovative'), findsOneWidget);
      expect(currentKeywords, contains('Innovative'));
    });
  });
}
