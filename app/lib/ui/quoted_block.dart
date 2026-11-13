import 'package:flutter/material.dart';

import '../models/feed_item.dart';
import '../models/post.dart';
import '../theme/forest_theme.dart';
import 'action_bar.dart';
import 'chips.dart';
import 'forest_icon.dart';

/// The post a reply replies to, shown small under a video reply (Card B).
/// A video parent gets a thumbnail strip with a play icon; a text parent does not.
class QuotedBlock extends StatelessWidget {
  const QuotedBlock({
    super.key,
    required this.parent,
    required this.parentPost,
    required this.root,
    required this.onTap,
    this.coverUrl,
    this.onOpenRoot,
    this.onLike,
    this.onThread,
    this.onShare,
  });

  final ParentRef parent;

  /// The parent's post at its latest known state (likes, counts).
  final Post parentPost;

  /// Set only when the root differs from the parent.
  final RootRef? root;

  /// Opens the viewer for a video parent, the thread for a text parent.
  final VoidCallback onTap;

  /// Absolute URL of the parent video's cover picture, shown in the strip behind the play icon; null for none.
  final String? coverUrl;
  final VoidCallback? onOpenRoot;
  final VoidCallback? onLike;
  final VoidCallback? onThread;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final isVideo = parentPost.kind == PostKind.video;
    final title = parentPost.title ?? parentPost.body ?? '';
    return Material(
      color: t.raised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: t.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        // A Stack, not an IntrinsicHeight row: the strip is pinned to the
        // body's height without Flutter measuring the whole body twice.
        child: Stack(
          children: [
            if (isVideo)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 46,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Color(0xFF222222)),
                    if (coverUrl != null)
                      Image.network(coverUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                    const Center(
                      child: ForestIcon(
                        Icn.play,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: EdgeInsets.only(left: isVideo ? 46 : 0),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            runSpacing: 2,
                            children: [
                              Text(
                                isVideo ? 'Parent video' : 'Parent reply',
                                style: TextStyle(fontSize: 12, color: t.fg2),
                              ),
                              Text(
                                '@${parent.actor.username}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (parent.actor.isBot) const BotTag(),
                            ],
                          ),
                        ),
                        if (root != null && onOpenRoot != null)
                          GestureDetector(
                            onTap: onOpenRoot,
                            child: Text(
                              'in @${root!.username}’s debate →',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: t.accent,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    ActionBar(
                      dense: true,
                      post: parentPost,
                      onLike: onLike,
                      onThread: onThread,
                      onShare: onShare,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
