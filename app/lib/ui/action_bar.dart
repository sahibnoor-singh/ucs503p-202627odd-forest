import 'package:flutter/material.dart';

import '../models/post.dart';
import '../theme/forest_theme.dart';
import 'forest_icon.dart';

/// One tappable icon (+ optional count), prototype `.act`: 18px icon, 6px gap,
/// 12.5px / weight 600 label, 22px tall. With no [onTap] it is a plain
/// read-only display: buttons that are not wired up are hidden, not faked.
class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.icon,
    this.label,
    this.onTap,
    this.color,
    this.semanticLabel,
    this.pop = false,
    this.iconSize = 18,
    this.fontSize = 12.5,
  });

  /// An [Icn] name.
  final String icon;
  final String? label;
  final VoidCallback? onTap;
  final Color? color;
  final String? semanticLabel;

  /// Plays the small "pop" when it flips on (the like heart).
  final bool pop;
  final double iconSize;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.forest.fg;
    Widget iconWidget = ForestIcon(icon, size: iconSize, color: c);
    if (pop) {
      iconWidget = TweenAnimationBuilder<double>(
        key: ValueKey(icon),
        tween: Tween(begin: 1.3, end: 1.0),
        duration: const Duration(milliseconds: 160),
        builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
        child: iconWidget,
      );
    }
    final content = SizedBox(
      height: 22,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget,
            if (label != null) ...[
              const SizedBox(width: 6),
              Text(
                label!,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  color: c,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkResponse(onTap: onTap, radius: 22, child: content),
    );
  }
}

/// The action row (prototype `.acts`, Plain mode): like + replies, Reply, the
/// FOR/AGAINST score, and the paper-plane share. `dense` is the quoted
/// parent's mini row (`.q-meta`: 12px labels, 17px icons, share pushed right).
class ActionBar extends StatelessWidget {
  const ActionBar({
    super.key,
    required this.post,
    this.onLike,
    this.onThread,
    this.onReply,
    this.onShare,
    this.onScore,
    this.light = false,
    this.dense = false,
  });

  /// Already resolved to the latest known state (likes, counts).
  final Post post;
  final VoidCallback? onLike;
  final VoidCallback? onThread;
  final VoidCallback? onReply;
  final VoidCallback? onShare;

  /// Tapping the FOR / AGAINST score: opens the debate graph.
  final VoidCallback? onScore;

  /// White-on-dark variant for the full-screen viewer.
  final bool light;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final base = light ? Colors.white : t.fg;
    final muted = light ? Colors.white70 : t.fg2;
    final liked = post.likedByMe;
    final hasScore = post.forCount + post.againstCount > 0;
    final iconSize = dense ? 17.0 : 18.0;
    final fontSize = dense ? 12.0 : 12.5;

    final like = ActionButton(
      icon: liked ? Icn.heartFilled : Icn.heart,
      label: '${post.likeCount}',
      color: liked ? t.like : base,
      onTap: onLike,
      semanticLabel: liked ? 'Unlike' : 'Like',
      pop: liked,
      iconSize: iconSize,
      fontSize: fontSize,
    );
    final thread = ActionButton(
      icon: Icn.comment,
      label: '${post.replyCount}',
      color: base,
      onTap: onThread,
      semanticLabel: 'Open replies',
      iconSize: iconSize,
      fontSize: fontSize,
    );
    final share = onShare == null
        ? null
        : ActionButton(
            icon: Icn.send,
            color: base,
            onTap: onShare,
            semanticLabel: 'Send',
            iconSize: iconSize,
          );

    if (dense) {
      return Row(children: [like, const SizedBox(width: 14), thread, const Spacer(), ?share]);
    }
    return Row(
      children: [
        like,
        const SizedBox(width: 14),
        thread,
        if (onReply != null) ...[
          const SizedBox(width: 16),
          ActionButton(
            icon: Icn.reply,
            label: 'Reply',
            color: base,
            onTap: onReply,
            semanticLabel: 'Reply',
          ),
        ],
        const SizedBox(width: 16),
        Expanded(
          child: hasScore
              ? Semantics(
                  button: onScore != null,
                  label: 'Open the debate graph',
                  excludeSemantics: onScore != null,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onScore,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '${post.forCount} FOR · ${post.againstCount} AGAINST',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: muted),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (share != null) ...[const SizedBox(width: 16), share],
      ],
    );
  }
}
