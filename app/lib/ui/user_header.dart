import 'package:flutter/material.dart';

import '../models/user.dart';
import '../theme/forest_theme.dart';
import 'chips.dart';
import 'forest_avatar.dart';
import 'forest_icon.dart';

/// Prototype `.uh`: 26px avatar, bold username (14px, weight 600), `BOT`
/// tag, grey 12px sub-line; stance chip and `⋯` on the right. Its own padding is
/// `0 2px 3px` (so the row is 29px tall); the card adds the outer inset.
/// Tapping a name does nothing yet: profile pages wait for accounts.
class UserHeader extends StatelessWidget {
  const UserHeader({
    super.key,
    required this.user,
    required this.sub,
    this.chip,
    this.onMore,
    this.avatarSize = 36,
  });

  final User user;

  /// `· 3h`, `replied · 1h`, `replied to @aman_s · 1h`.
  final String sub;
  final Widget? chip;

  /// Opens the `⋯` menu. Hidden when null.
  final VoidCallback? onMore;

  /// 36 (the prototype draws 26; made bigger on request).
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 3),
      child: Row(
        children: [
          ForestAvatar(user: user, size: avatarSize),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 2,
              children: [
                Text(
                  user.username,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                if (user.isBot) const BotTag(),
                Text(sub, style: TextStyle(fontSize: 12, color: t.fg2)),
              ],
            ),
          ),
          if (chip != null) ...[const SizedBox(width: 6), chip!],
          if (onMore != null) ...[
            const SizedBox(width: 2),
            Semantics(
              button: true,
              label: 'More options',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onMore,
                child: const SizedBox(
                  width: 24,
                  height: 24,
                  child: Center(child: ForestIcon(Icn.more, size: 20)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
