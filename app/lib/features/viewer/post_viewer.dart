import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/post.dart';
import '../../models/user.dart';
import '../../ui/action_bar.dart';
import '../../ui/chips.dart';
import '../../ui/forest_avatar.dart';
import '../../ui/forest_icon.dart';
import '../../ui/format.dart';
import '../../ui/post_media.dart';
import '../../ui/reel_focus.dart';
import '../home/feed_controller.dart';
import '../home/feed_item_card.dart';

/// Opens the full-screen viewer over the app and pauses the feed's videos
/// while it is open.
Future<void> openPostViewer(
  BuildContext context, {
  required Post post,
  required User author,
  required CardActions actions,
}) {
  return pauseFeedWhile<void>(
    context,
    () => Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 160),
        reverseTransitionDuration: const Duration(milliseconds: 120),
        pageBuilder: (_, _, _) => PostViewer(post: post, author: author, actions: actions),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    ),
  );
}

/// Black layer: the video fills the screen, tap pauses, double tap likes.
class PostViewer extends StatelessWidget {
  const PostViewer({
    super.key,
    required this.post,
    required this.author,
    required this.actions,
  });

  final Post post;
  final User author;
  final CardActions actions;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<FeedController>();
    final live = c.resolve(post);
    final text = live.title ?? live.body ?? '';
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PostMedia(
            post: live,
            mediaUrl: c.mediaUrl(live),
            coverUrl: c.coverUrl(live),
            muted: c.muted,
            onToggleMute: c.toggleMute,
            fullscreen: true,
            onDoubleTap: actions.likeOnly == null ? null : () => actions.likeOnly!(live),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _Shade(
              top: true,
              padding: EdgeInsets.fromLTRB(4, MediaQuery.paddingOf(context).top + 6, 56, 18),
              child: Row(
                children: [
                  Tooltip(
                    message: 'Back to feed',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).maybePop(),
                      child: const SizedBox(
                        width: 34,
                        height: 34,
                        child: Center(child: ForestIcon(Icn.back, size: 18, color: Colors.white)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ForestAvatar(user: author, size: 26),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      author.username,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (author.isBot) ...[const SizedBox(width: 6), const BotTag()],
                  const SizedBox(width: 6),
                  Text(
                    '· ${relativeTime(live.createdAt)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _Shade(
              top: false,
              // 32 px more at the bottom: the video's progress bar (which can be dragged) sits in that strip, under the buttons
              padding: EdgeInsets.fromLTRB(12, 24, 12, MediaQuery.paddingOf(context).bottom + 44),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          shadows: [Shadow(blurRadius: 4, color: Color(0x99000000))],
                        ),
                      ),
                    ),
                  ActionBar(
                    light: true,
                    post: live,
                    onLike: actions.like == null ? null : () => actions.like!(live),
                    onThread: actions.openThread == null
                        ? null
                        : () => actions.openThread!(live, author),
                    onReply: actions.reply == null ? null : () => actions.reply!(live, author),
                    onShare: actions.share == null ? null : () => actions.share!(live),
                    onScore: actions.openGraph == null ? null : () => actions.openGraph!(live),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The dark shade behind the viewer's top bar or bottom buttons so white text stays readable over any video. It is only a picture:
/// it lets every tap through to the video's own controls (CC, mute, the progress bar) underneath it, and only the widgets drawn
/// on it (the back arrow, the buttons) take taps.
class _Shade extends StatelessWidget {
  const _Shade({required this.top, required this.padding, required this.child});

  final bool top;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: top ? const [Color(0x8C000000), Color(0x00000000)] : const [Color(0x00000000), Color(0xA6000000)],
                ),
              ),
            ),
          ),
        ),
        Padding(padding: padding, child: child),
      ],
    );
  }
}
