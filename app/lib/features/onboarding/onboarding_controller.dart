import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show IconData;
import 'package:flutter/material.dart' show Icons;

import '../../data/feed_repository.dart';
import '../../models/user.dart';
import '../../services/api_client.dart';
import 'onboarding_repository.dart';

enum OnboardingStep { topics, people, guide }

/// The logic of the two first-run pages, with no widgets, so it can be tested alone.
///
///   topics → [continueWithTopics] / [skip] → people → [openGuide] → guide ([nextGuide]) → (the screen calls Session.finishOnboarding)
///
/// Rules this class keeps:
///  * nothing is required: a failed or skipped save never traps the person, and every page can be skipped;
///  * no topic is ticked to begin with, and at most [OnboardingTopics.max] can be;
///  * a follow is shown at once and undone if the server refuses.
class OnboardingController extends ChangeNotifier {
  OnboardingController(this._onboarding, this._feed);

  final OnboardingRepository _onboarding;
  final FeedRepository _feed;

  OnboardingStep step = OnboardingStep.topics;

  OnboardingTopics? offer;
  bool loadingTopics = true;
  String? topicsError;
  final Set<String> selected = {};

  bool saving = false;
  String? saveError;

  List<SuggestedUser>? people;
  bool loadingPeople = false;
  final Set<String> followed = {};

  /// Set when a follow could not be made; the screen shows it once.
  String? followError;

  /// The short "how it works" page: one idea at a time, always skippable. [guidePage] is the idea on show.
  static const guideSlides = <GuideSlide>[
    GuideSlide(Icons.videocam_outlined, 'Share an opinion', 'Post a short video on something you care about. Others can reply with their own video.'),
    GuideSlide(Icons.reply_outlined, 'Reply with a video', 'Tap Reply to answer. FOREST works out whether you are for or against.'),
    GuideSlide(Icons.swap_horiz, 'See both sides', 'Swipe sideways on a debate to move between the FOR and AGAINST replies.'),
  ];
  int guidePage = 0;

  /// People page → guide. Called by "Done" on the people page.
  void openGuide() {
    step = OnboardingStep.guide;
    guidePage = 0;
    notifyListeners();
  }

  /// Next idea; returns true when that was the last one (the screen then leaves onboarding).
  bool nextGuide() {
    if (guidePage >= guideSlides.length - 1) return true;
    guidePage++;
    notifyListeners();
    return false;
  }

  int get min => offer?.min ?? 3;
  int get max => offer?.max ?? 8;
  bool get canContinue => selected.length >= min && !saving;

  Future<void> loadTopics() async {
    loadingTopics = true;
    topicsError = null;
    notifyListeners();
    try {
      offer = await _onboarding.topics();
    } on ApiException catch (e) {
      topicsError = e.message;
    } finally {
      loadingTopics = false;
      notifyListeners();
    }
  }

  /// Ticks or unticks a topic. Ticking past the maximum does nothing (the screen says why).
  void toggle(String id) {
    if (!selected.remove(id)) {
      if (selected.length >= max) return;
      selected.add(id);
    }
    saveError = null;
    notifyListeners();
  }

  Future<void> continueWithTopics() async {
    if (!canContinue) return;
    await _saveThenPeople([for (final t in offer!.topics) if (selected.contains(t.id)) t.id]);
  }

  /// "Skip for now": same as continuing with no topics.
  Future<void> skip() async {
    if (saving) return;
    await _saveThenPeople(const []);
  }

  Future<void> _saveThenPeople(List<String> ids) async {
    saving = true;
    saveError = null;
    notifyListeners();
    var failed = false;
    try {
      await _onboarding.save(ids);
    } on ApiException catch (e) {
      // Do not trap anyone on this page: say so, and let them carry on (the topics can be chosen again later).
      failed = true;
      saveError = e.message;
    }
    saving = false;
    step = OnboardingStep.people;
    notifyListeners();
    if (failed && ids.isNotEmpty) saveError = 'Your topics could not be saved. You can choose them again later.';
    await _loadPeople();
  }

  Future<void> _loadPeople() async {
    loadingPeople = true;
    notifyListeners();
    try {
      people = await _feed.suggestedUsers(limit: 10);
    } on Object {
      people = const []; // the page still has a way forward
    } finally {
      loadingPeople = false;
      notifyListeners();
    }
  }

  Future<void> toggleFollow(User user) async {
    final now = !followed.contains(user.id);
    if (now) {
      followed.add(user.id);
    } else {
      followed.remove(user.id);
    }
    followError = null;
    notifyListeners();
    try {
      await _feed.setFollowing(user.id, now);
    } on Object catch (e) {
      if (now) {
        followed.remove(user.id);
      } else {
        followed.add(user.id);
      }
      followError = e is ApiException ? e.message : 'Could not follow @${user.username}.';
      notifyListeners();
    }
  }
}

/// One idea of the guide: a short title and one or two sentences.
class GuideSlide {
  const GuideSlide(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}
