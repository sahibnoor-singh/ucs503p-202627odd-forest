import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../../theme/forest_theme.dart';
import '../../ui/chips.dart';
import '../../ui/forest_avatar.dart';

/// The prototype's `.stories` row: a "Your story" tile with a +, then one
/// ring per person you follow. Rings only toggle a local "seen" look; stories
/// themselves have no server support yet (PHASE1_HOME_PLAN.md §10).
class StoriesRow extends StatelessWidget {
  const StoriesRow({
    super.key,
    required this.users,
    required this.isSeen,
    required this.onToggleSeen,
    required this.onYourStory,
  });

  final List<User> users;
  final bool Function(User user) isSeen;
  final void Function(User user) onToggleSeen;
  final VoidCallback onYourStory;

  @override
  Widget build(BuildContext context) {
    // No divider and a short bottom edge: the row flows straight into the first post.
    return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Tile(
              label: 'Your story',
              onTap: onYourStory,
              ring: const _YourStoryRing(),
            ),
            for (final user in users) ...[
              const SizedBox(width: 12),
              _Tile(
                key: ValueKey('story-${user.id}'),
                label: user.username,
                bot: user.isBot,
                onTap: () => onToggleSeen(user),
                ring: _Ring(user: user, seen: isSeen(user)),
              ),
            ],
          ],
        ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.label, required this.ring, required this.onTap, this.bot = false});

  final String label;
  final Widget ring;
  final VoidCallback onTap;
  final bool bot;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Semantics(
      button: true,
      label: label == 'Your story' ? label : 'Story from $label${bot ? ' (automated account)' : ''}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 64,
          child: Column(
            children: [
              ring,
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: t.fg2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.user, required this.seen});

  final User user;
  final bool seen;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final ring = Container(
      key: ValueKey('story-ring-${user.id}'),
      width: 60,
      height: 60,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: seen ? t.border : t.fg, width: 2),
      ),
      child: ForestAvatar(user: user, size: 50),
    );
    if (!user.isBot) return ring;
    // Bot accounts are always marked (CLAUDE.md). The mark sits on the ring,
    // so it takes no room and never shortens the name.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ring,
        const Positioned(left: 0, right: 0, bottom: -4, child: Center(child: BotTag(compact: true))),
      ],
    );
  }
}

class _YourStoryRing extends StatelessWidget {
  const _YourStoryRing();

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return CustomPaint(
      painter: _DashedCircle(color: t.fg2),
      child: Container(
        width: 60,
        height: 60,
        padding: const EdgeInsets.all(3),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: t.raised,
            border: Border.all(color: t.border),
          ),
          alignment: Alignment.center,
          child: Text('+', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: t.fg2)),
        ),
      ),
    );
  }
}

class _DashedCircle extends CustomPainter {
  const _DashedCircle({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()..addOval(Rect.fromLTWH(1, 1, size.width - 2, size.height - 2));
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 8) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedCircle old) => old.color != color;
}
