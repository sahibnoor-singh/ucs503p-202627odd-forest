import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user.dart';
import '../../theme/forest_theme.dart';
import '../../ui/chips.dart';
import '../../ui/forest_avatar.dart';
import 'feed_controller.dart';

/// What an empty Home shows instead of "Nothing here yet": people worth
/// following (`GET /api/users/suggested`), each with a Follow button. Not drawn
/// in the prototype (PHASE1_HOME_PLAN.md §2.3 lists it as a state the API
/// forces on us), so it only reuses the app's own tokens and pieces. Bot
/// accounts keep their `BOT` tag here too.
class SuggestedPeople extends StatefulWidget {
  const SuggestedPeople({super.key, required this.onDiscover});

  final VoidCallback onDiscover;

  @override
  State<SuggestedPeople> createState() => _SuggestedPeopleState();
}

class _SuggestedPeopleState extends State<SuggestedPeople> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<FeedController>().ensureSuggestions();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<FeedController>();
    final t = context.forest;
    final people = c.suggestions;

    final Widget list;
    if (people == null && c.suggestionsLoading) {
      list = const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (people == null) {
      list = _Notice(
        text: c.suggestionsError ?? 'Could not load suggestions.',
        button: 'Retry',
        onPressed: () => c.loadSuggestions(force: true),
      );
    } else if (people.isEmpty) {
      list = const _Notice(text: 'Nobody to suggest yet. Discover has the latest debates.');
    } else {
      list = Column(children: [for (final p in people) _PersonRow(person: p)]);
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 28),
      children: [
        Center(child: Icon(Icons.forest_outlined, size: 40, color: t.fg2)),
        const SizedBox(height: 10),
        const Center(
          child: Text(
            'Follow people to fill your Home',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Posts and replies from people you follow show up here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: t.fg2),
          ),
        ),
        const SizedBox(height: 14),
        list,
        const SizedBox(height: 14),
        if (c.followedCount > 0)
          FilledButton(
            key: const ValueKey('show-my-feed'),
            onPressed: c.loading ? null : c.refresh,
            style: FilledButton.styleFrom(
              backgroundColor: t.fg,
              foregroundColor: t.bg,
              minimumSize: const Size.fromHeight(44),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            child: const Text('Show my feed'),
          ),
        const SizedBox(height: 6),
        // Nothing followed yet: Discover is the way forward, so it is a real button and not just a link.
        if (c.followedCount == 0)
          OutlinedButton(
            key: const ValueKey('go-to-discover'),
            onPressed: widget.onDiscover,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              side: BorderSide(color: t.border),
              foregroundColor: t.fg,
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            child: const Text('Go to Discover'),
          )
        else
          Center(
            child: TextButton(
              onPressed: widget.onDiscover,
              child: Text(
                'Go to Discover',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.accent),
              ),
            ),
          ),
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person});

  final SuggestedUser person;

  static String _count(int n, String one) => '$n ${n == 1 ? one : '${one}s'}';

  @override
  Widget build(BuildContext context) {
    final c = context.watch<FeedController>();
    final t = context.forest;
    final user = person.user;
    final following = c.isFollowing(user);

    final buttonText = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: following ? t.fg : t.bg);
    return Padding(
      key: ValueKey('suggested-${user.id}'),
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          ForestAvatar(user: user, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (user.isBot) ...[const SizedBox(width: 6), const BotTag()],
                  ],
                ),
                Text(
                  user.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: t.fg2),
                ),
                Text(
                  '${_count(person.followerCount, 'follower')} · ${_count(person.postCount, 'post')}',
                  style: TextStyle(fontSize: 12, color: t.fg2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 34,
            child: following
                ? OutlinedButton(
                    key: ValueKey('follow-${user.id}'),
                    onPressed: () => c.toggleFollow(user),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: t.border),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: Text('Following', style: buttonText),
                  )
                : FilledButton(
                    key: ValueKey('follow-${user.id}'),
                    onPressed: () => c.toggleFollow(user),
                    style: FilledButton.styleFrom(
                      backgroundColor: t.fg,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    child: Text('Follow', style: buttonText),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.button, this.onPressed});

  final String text;
  final String? button;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: t.fg2)),
          if (button != null) ...[
            const SizedBox(height: 10),
            OutlinedButton(onPressed: onPressed, child: Text(button!)),
          ],
        ],
      ),
    );
  }
}
