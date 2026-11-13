import 'package:flutter/material.dart';

import '../../theme/forest_theme.dart';
import '../../ui/chips.dart';
import '../../ui/forest_avatar.dart';
import '../profile/profile_screen.dart';
import '../safety/safety_actions.dart';
import 'discover_search_controller.dart';
import 'search_repository.dart';

/// The one place Discover asks to show a person. The profile page is built separately; when it exists, replace the body of this
/// function with a push of that page (it gets the person's id and username) and nothing else in Discover has to change.
/// Until then this is a small card: who they are, how many follow them, and a Follow button.
Future<void> openProfile(BuildContext context, AccountHit hit, DiscoverSearchController controller) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.forest.raised,
    barrierColor: context.forest.scrim,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheet) => SafeArea(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => _ProfileCard(hit: controller.accountById(hit.user.id) ?? hit, controller: controller),
      ),
    ),
  );
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.hit, required this.controller});

  final AccountHit hit;
  final DiscoverSearchController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final user = hit.user;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ForestAvatar(user: user, size: 84),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(user.username, style: TextStyle(color: t.fg, fontSize: 18, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
              if (user.isBot) ...[const SizedBox(width: 8), const BotTag()],
            ],
          ),
          Text(user.fullName, style: TextStyle(color: t.fg2, fontSize: 14)),
          const SizedBox(height: 12),
          Text(
            '${hit.followerCount} ${hit.followerCount == 1 ? 'follower' : 'followers'} · ${hit.postCount} ${hit.postCount == 1 ? 'post' : 'posts'}',
            style: TextStyle(color: t.fg2, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            icon: const Icon(Icons.person_outline, size: 16),
            label: const Text('View Full Profile', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            onPressed: () {
              Navigator.of(context).pop();
              openProfileScreen(context, user.id);
            },
          ),
          if (!hit.isMe) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: hit.followedByMe
                  ? OutlinedButton(onPressed: () => _toggle(context), child: Text('Following', style: TextStyle(color: t.fg, fontWeight: FontWeight.w700)))
                  : FilledButton(
                      onPressed: () => _toggle(context),
                      style: FilledButton.styleFrom(backgroundColor: t.fg),
                      child: Text('Follow', style: TextStyle(color: t.bg, fontWeight: FontWeight.w700)),
                    ),
            ),
            TextButton(
              key: const Key('profile-block'),
              onPressed: () async {
                final blocked = await blockPersonFlow(context, userId: hit.user.id, username: hit.user.username);
                if (blocked) controller.removeAccount(hit.user.id);
                if (blocked && context.mounted) Navigator.of(context).maybePop();
              },
              child: Text('Block @${user.username}', style: TextStyle(color: t.like)),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggle(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final problem = await controller.toggleFollow(hit);
    if (problem != null) messenger?.showSnackBar(SnackBar(content: Text(problem)));
  }
}
