import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/feed_repository.dart';
import '../../models/user.dart';
import '../../services/session.dart';
import '../../theme/forest_theme.dart';
import '../../ui/chips.dart';
import '../../ui/forest_avatar.dart';
import 'onboarding_controller.dart';
import 'onboarding_repository.dart';

/// The first-run pages after sign-up: pick topics, follow a few people, then a three-idea "how it works" (one idea per page). Nothing is required, every page can be skipped,
/// and it is shown once (docs/ONBOARDING_PLAN.md). [AuthGate] shows it instead of the app while `Session.needsOnboarding` is set.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final OnboardingController _c;

  @override
  void initState() {
    super.initState();
    _c = OnboardingController(context.read<OnboardingRepository>(), context.read<FeedRepository>())
      ..addListener(_onChange)
      ..loadTopics();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c
      ..removeListener(_onChange)
      ..dispose();
    super.dispose();
  }

  Future<void> _finish() => context.read<Session>().finishOnboarding();

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: switch (_c.step) {
            OnboardingStep.topics => _topics(t),
            OnboardingStep.people => _people(t),
            OnboardingStep.guide => _guide(t),
          },
        ),
      ),
    );
  }

  Widget _topics(ForestTokens t) {
    final offer = _c.offer;
    return Padding(
      key: const Key('onboarding-topics'),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The heading scrolls with the chips, so a small phone or large system text never pushes the buttons off screen.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('What should we show you?', style: TextStyle(color: t.fg, fontSize: 26, fontWeight: FontWeight.w800, height: 1.2)),
                  const SizedBox(height: 8),
                  Text(
                    'Pick ${_c.min} to ${_c.max} topics to start with. It is only a first guess: what you watch will change it, and you will still see the other side.',
                    style: TextStyle(color: t.fg2, fontSize: 14.5, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  _topicBody(t, offer),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_c.saveError != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_c.saveError!, style: TextStyle(color: t.like, fontSize: 13))),
          Text(
            _c.selected.length >= _c.min ? '${_c.selected.length} chosen' : '${_c.selected.length} of ${_c.min} chosen',
            key: const Key('onboarding-count'),
            style: TextStyle(color: t.fg2, fontSize: 13),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            width: double.infinity,
            child: FilledButton(
              key: const Key('onboarding-continue'),
              onPressed: _c.canContinue ? _c.continueWithTopics : null,
              style: FilledButton.styleFrom(backgroundColor: t.accent, foregroundColor: Colors.white, disabledBackgroundColor: t.raised, disabledForegroundColor: t.fg2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: _c.saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Continue', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
          Center(
            child: TextButton(
              key: const Key('onboarding-skip'),
              onPressed: _c.saving ? null : _c.skip,
              child: Text('Skip for now', style: TextStyle(color: t.fg2)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topicBody(ForestTokens t, OnboardingTopics? offer) {
    if (_c.loadingTopics) return const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: CircularProgressIndicator()));
    if (offer == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_c.topicsError ?? 'Could not load the topics.', textAlign: TextAlign.center, style: TextStyle(color: t.fg2)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _c.loadTopics, child: const Text('Try again')),
          ]),
        ),
      );
    }
    return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final topic in offer.topics)
            FilterChip(
              key: Key('topic-${topic.id}'),
              label: Text(topic.label),
              selected: _c.selected.contains(topic.id),
              onSelected: (_) => _c.toggle(topic.id),
              showCheckmark: false,
              labelStyle: TextStyle(
                color: _c.selected.contains(topic.id) ? Colors.white : t.fg,
                fontWeight: FontWeight.w600,
                fontSize: 14.5,
              ),
              selectedColor: t.accent,
              backgroundColor: t.raised,
              side: BorderSide(color: _c.selected.contains(topic.id) ? t.accent : t.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            ),
        ],
    );
  }

  /// "How it works": one idea at a time, with a Skip that is always there. No tour, no pointing at buttons.
  Widget _guide(ForestTokens t) {
    final slide = OnboardingController.guideSlides[_c.guidePage];
    final last = _c.guidePage == OnboardingController.guideSlides.length - 1;
    return Padding(
      key: Key('onboarding-guide-${_c.guidePage}'),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(key: const Key('guide-skip'), onPressed: _finish, child: Text('Skip', style: TextStyle(color: t.fg2))),
          ),
          // Centred when there is room; scrolls (instead of overflowing) on a small phone or with large system text.
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(color: t.raised, borderRadius: BorderRadius.circular(20), border: Border.all(color: t.border)),
                    child: Icon(slide.icon, size: 34, color: t.accent),
                  ),
                  const SizedBox(height: 22),
                  Text('${_c.guidePage + 1} of ${OnboardingController.guideSlides.length}', style: TextStyle(color: t.fg2, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Text(slide.title, style: TextStyle(color: t.fg, fontSize: 30, fontWeight: FontWeight.w800, height: 1.15)),
                  const SizedBox(height: 14),
                  Text(slide.body, style: TextStyle(color: t.fg2, fontSize: 17, height: 1.45)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < OnboardingController.guideSlides.length; i++)
                Container(
                  width: i == _c.guidePage ? 22 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(color: i == _c.guidePage ? t.accent : t.border, borderRadius: BorderRadius.circular(4)),
                ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            width: double.infinity,
            child: FilledButton(
              key: const Key('guide-next'),
              onPressed: () {
                if (_c.nextGuide()) _finish();
              },
              style: FilledButton.styleFrom(backgroundColor: t.accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: Text(last ? 'Start' : 'Next', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _people(ForestTokens t) {
    final people = _c.people;
    final followed = _c.followed.length;
    return Padding(
      key: const Key('onboarding-people'),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Follow a few people', style: TextStyle(color: t.fg, fontSize: 26, fontWeight: FontWeight.w800, height: 1.2)),
          const SizedBox(height: 8),
          Text(
            'Their videos fill your Home. You can follow or unfollow anyone, any time.',
            style: TextStyle(color: t.fg2, fontSize: 14.5, height: 1.4),
          ),
          if (_c.saveError != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_c.saveError!, style: TextStyle(color: t.fg2, fontSize: 13))),
          const SizedBox(height: 12),
          Expanded(
            child: _c.loadingPeople || people == null
                ? const Center(child: CircularProgressIndicator())
                : people.isEmpty
                    ? Center(child: Text('Nobody to suggest yet. Your Home will fill as people join.', textAlign: TextAlign.center, style: TextStyle(color: t.fg2)))
                    : ListView.builder(
                        itemCount: people.length,
                        itemBuilder: (_, i) => _PersonRow(
                          key: ValueKey('person-${people[i].user.id}'),
                          person: people[i],
                          following: _c.followed.contains(people[i].user.id),
                          onTap: () => _c.toggleFollow(people[i].user),
                        ),
                      ),
          ),
          if (_c.followError != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_c.followError!, style: TextStyle(color: t.like, fontSize: 13))),
          SizedBox(
            height: 52,
            width: double.infinity,
            child: FilledButton(
              key: const Key('onboarding-done'),
              onPressed: _c.openGuide,
              style: FilledButton.styleFrom(backgroundColor: t.accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: Text(followed == 0 ? 'Skip for now' : 'Done, following $followed', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({super.key, required this.person, required this.following, required this.onTap});

  final SuggestedUser person;
  final bool following;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final user = person.user;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          ForestAvatar(user: user, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(child: Text(user.username, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.fg, fontWeight: FontWeight.w700, fontSize: 15))),
                  if (user.isBot) ...[const SizedBox(width: 6), const BotTag()],
                ]),
                Text(
                  '${person.postCount} ${person.postCount == 1 ? 'post' : 'posts'} · ${person.followerCount} ${person.followerCount == 1 ? 'follower' : 'followers'}',
                  style: TextStyle(color: t.fg2, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 36,
            child: following
                ? OutlinedButton(key: Key('follow-${user.id}'), onPressed: onTap, child: const Text('Following'))
                : FilledButton(
                    key: Key('follow-${user.id}'),
                    onPressed: onTap,
                    style: FilledButton.styleFrom(backgroundColor: t.accent, foregroundColor: Colors.white),
                    child: const Text('Follow'),
                  ),
          ),
        ],
      ),
    );
  }
}
