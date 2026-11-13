import 'dart:async';

import 'package:flutter/material.dart';


import '../../models/user.dart';
import '../../models/video.dart';
import '../../ui/chips.dart';
import '../../ui/forest_avatar.dart';
import 'sides_heard.dart';

/// Overlays on the Reel: Top debate breadcrumbs & persistent mute, right action rail,
/// bottom metadata with accurate current-video reply counts, and accessible controls.
class ReelOverlay extends StatelessWidget {
  const ReelOverlay({
    super.key,
    required this.video,
    required this.rootVideo,
    required this.muteNotifier,
    required this.onToggleMute,
    required this.onLike,
    required this.onOpenTree,
    required this.onOpenReplySheet,
    required this.onMoreOptions,
    this.onReturnToRoot,
    this.onGoBack,
    this.onClose,
    this.onShare,
    this.canGoBack = false,
    this.treeDepth = 1,
    this.forCount = 0,
    this.againstCount = 0,
    this.sidesNote,
    this.onOpenProfile,
    this.onShowFor,
    this.onShowAgainst,
    this.titleExpanded = false,
    this.onToggleTitle,
    this.onFollow,
    this.following = false,
    this.onComments,
  });

  final Video video;
  final Video rootVideo;
  final ValueNotifier<bool> muteNotifier;
  final VoidCallback onToggleMute;
  final VoidCallback onLike;
  final VoidCallback onOpenTree;
  final VoidCallback onOpenReplySheet;
  final VoidCallback onMoreOptions;
  final VoidCallback? onReturnToRoot;
  final VoidCallback? onGoBack;

  /// Leaves the feed: a back arrow at the top left, beside the parent button.
  final VoidCallback? onClose;

  /// The paper-plane: send this video to a friend. Hidden when null.
  final VoidCallback? onShare;
  final bool canGoBack;
  final int treeDepth;
  final int forCount;
  final int againstCount;

  /// "You have heard both sides" / "swipe for the other side"; null when the debate has no replies on both sides.
  final SidesNote? sidesNote;

  /// Taps on the author's picture or name. Null when the server did not say who the author is.
  final VoidCallback? onOpenProfile;

  /// The two ends of the debate bar are buttons too (a mouse or keyboard cannot swipe).
  final VoidCallback? onShowFor;
  final VoidCallback? onShowAgainst;

  /// Whether the whole title is showing, and the "more" / "less" toggle (owned by the reel, so a tap on the video can close it).
  final bool titleExpanded;
  final VoidCallback? onToggleTitle;

  /// The Follow button beside the author's name. Null hides it (it is you, or you already follow them, or the server did not say who).
  final VoidCallback? onFollow;
  final bool following;

  /// The speech bubble: the written replies to this video. Null hides it.
  final VoidCallback? onComments;

  @override
  Widget build(BuildContext context) {
    final isChild = video.id != rootVideo.id;

    return SafeArea(
      child: Stack(
        children: [
          // Top bar: Debate Breadcrumb / Back button + 4D Gesture Hints + Mute toggle
          Positioned(
            top: 10,
            left: 14,
            right: 14,
            child: Row(
              children: [
                // Leaves the feed (opened from the Discover grid)
                if (onClose != null) ...[
                  Semantics(
                    button: true,
                    label: 'Back',
                    child: InkWell(
                      onTap: onClose,
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                // Breadcrumb / Back button
                if (canGoBack || isChild)
                  Semantics(
                    button: true,
                    label: 'Back to the parent video',
                    child: InkWell(
                      onTap: onGoBack ?? onReturnToRoot,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.70),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.arrow_back_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Parent video',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else if (video.durationS > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3.5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '0:${video.durationS.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                const Spacer(),

                // Persistent Mute toggle
                ValueListenableBuilder<bool>(
                  valueListenable: muteNotifier,
                  builder: (context, isMuted, _) {
                    return Semantics(
                      label: 'Toggle mute',
                      button: true,
                      child: InkWell(
                        onTap: onToggleMute,
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isMuted
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                            color: Colors.white,
                            size: 19,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Right-hand rail: small and close together, so the picture stays the main thing.
          Positioned(
            right: 8,
            bottom: 10,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RailButton(icon: Icons.reply_rounded, label: 'Reply', onTap: onOpenReplySheet),
                _RailButton(
                  icon: video.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  iconColor: video.isLiked ? const Color(0xFFDC2626) : Colors.white,
                  label: video.likeCount.toString(),
                  onTap: onLike,
                ),
                if (onComments != null) _RailButton(icon: Icons.chat_bubble_outline_rounded, label: '', onTap: onComments!, semantics: 'Comments'),
                _RailButton(
                  icon: Icons.account_tree_outlined,
                  label: (forCount + againstCount > 0) ? '${forCount + againstCount}' : (video.replyCount > 0 ? video.replyCount.toString() : ''),
                  onTap: onOpenTree,
                  semantics: 'The debate tree',
                ),
                if (onShare != null) _RailButton(icon: Icons.send_outlined, label: '', onTap: onShare!, semantics: 'Send to a friend'),
                _RailButton(icon: Icons.more_horiz_rounded, label: '', onTap: onMoreOptions, semantics: 'More'),
              ],
            ),
          ),

          // Bottom block: who (picture, name, Follow), what they said (two lines, then "more"), and the tally.
          Positioned(
            left: 14,
            right: 62,
            bottom: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _AuthorRow(video: video, rootVideo: rootVideo, isChild: isChild, onTap: onOpenProfile, onFollow: onFollow, following: following),
                const SizedBox(height: 6),
                _TitleText(
                  text: video.displayTitle,
                  expanded: titleExpanded,
                  onToggle: onToggleTitle,
                ),
                if (sidesNote != null) ...[
                  const SizedBox(height: 4),
                  // Said for a few seconds, then it gets out of the way: the picture is what people came for.
                  FadingNote(key: ValueKey(sidesNote!.text), note: sidesNote!),
                ],
                if ((video.pickedBy != null || video.exploring) && MediaQuery.sizeOf(context).height >= 700) ...[
                  const SizedBox(height: 4),
                  // why Discover chose this (nothing is shown for the person's own picks)
                  Semantics(
                    label: video.pickedBy != null ? "Picked by ${video.pickedBy}'s taste" : 'Something different from what you usually watch',
                    excludeSemantics: true,
                    child: Text(
                      video.pickedBy != null ? "Picked by @${video.pickedBy}'s taste" : 'Something different from your usual',
                      style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600, shadows: [Shadow(color: Colors.black87, blurRadius: 4)]),
                    ),
                  ),
                ],
                _Tally(forCount: forCount, againstCount: againstCount, onFor: onShowFor, onAgainst: onShowAgainst),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _forGreen = Color(0xFF4CC38A);
const _againstOrange = Color(0xFFF2784B);
const _textShadow = [Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1))];

/// Picture, @name (+ BOT) and a Follow button beside it. The picture and name open the profile; below, which side this video is on (and who
/// it answers).
class _AuthorRow extends StatelessWidget {
  const _AuthorRow({required this.video, required this.rootVideo, required this.isChild, required this.onTap, required this.onFollow, required this.following});

  final Video video;
  final Video rootVideo;
  final bool isChild;
  final VoidCallback? onTap;
  final VoidCallback? onFollow;
  final bool following;

  @override
  Widget build(BuildContext context) {
    final stance = video.stance.toUpperCase();
    final side = (stance == 'FOR' || stance == 'AGAINST') ? stance : null;
    final person = User(id: video.authorId ?? '', username: video.userName, fullName: video.userName, avatarUrl: video.authorAvatarUrl, isBot: video.isBot);
    final subtitle = [?side, if (isChild) 'replying to @${rootVideo.userName}'];
    return Row(
      children: [
        Flexible(
          child: Semantics(
            button: onTap != null,
            label: "Open @${video.userName}'s profile",
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(24),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ForestAvatar(user: person, size: 32),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Flexible(child: Text('@${video.userName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800, shadows: _textShadow))),
                          if (video.isBot) ...[const SizedBox(width: 5), const BotTag(compact: true)],
                        ]),
                        if (subtitle.isNotEmpty)
                          Text.rich(
                            TextSpan(children: [
                              if (side != null) TextSpan(text: side, style: TextStyle(color: side == 'FOR' ? _forGreen : _againstOrange, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                              if (side != null && isChild) const TextSpan(text: '  '),
                              if (isChild) TextSpan(text: 'replying to @${rootVideo.userName}'),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w500, shadows: _textShadow),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (onFollow != null) ...[
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: following ? 'Following @${video.userName}. Tap to unfollow' : 'Follow @${video.userName}',
            child: InkWell(
              key: const Key('reel-follow'),
              onTap: onFollow,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: following ? Colors.transparent : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: following ? Colors.white54 : Colors.white),
                ),
                child: Text(following ? 'Following' : 'Follow', style: TextStyle(color: following ? Colors.white70 : const Color(0xFF111827), fontSize: 12, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The title: at most two lines, with "… more" at the end of the second one (strictly two lines, "more" included). Tapping it opens the
/// rest on a dark panel you can scroll; "less" (or a tap on the video) closes it.
class _TitleText extends StatelessWidget {
  const _TitleText({required this.text, required this.expanded, required this.onToggle});

  final String text;
  final bool expanded;
  final VoidCallback? onToggle;

  static const _style = TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, height: 1.3, shadows: _textShadow);
  static const _more = '… more';

  /// The longest start of [text] that still fits in two lines once "… more" is added.
  static String _cut(String text, double width, TextScaler scaler) {
    bool fits(String s) {
      final p = TextPainter(text: TextSpan(text: s, style: _style), maxLines: 2, textDirection: TextDirection.ltr, textScaler: scaler)..layout(maxWidth: width);
      return !p.didExceedMaxLines;
    }

    var lo = 0, hi = text.length;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (fits('${text.substring(0, mid).trimRight()}$_more')) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return text.substring(0, lo).trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final scaler = MediaQuery.textScalerOf(context);
      final painter = TextPainter(text: TextSpan(text: text, style: _style), maxLines: 2, textDirection: TextDirection.ltr, textScaler: scaler)
        ..layout(maxWidth: box.maxWidth);
      final cut = painter.didExceedMaxLines;
      if (expanded && cut) {
        final maxHeight = MediaQuery.sizeOf(context).height * 0.34;
        return Container(
          key: const Key('title-expanded'),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.62), borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            ConstrainedBox(constraints: BoxConstraints(maxHeight: maxHeight), child: SingleChildScrollView(child: Text(text, style: _style.copyWith(fontWeight: FontWeight.w500, fontSize: 15)))),
            _MoreLess(label: 'less', onTap: onToggle),
          ]),
        );
      }
      if (!cut) return Text(text, maxLines: 2, style: _style);
      return InkWell(
        key: const Key('title-more'),
        onTap: onToggle,
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: '${_cut(text, box.maxWidth, scaler)}… '),
            const TextSpan(text: 'more', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800)),
          ]),
          maxLines: 2,
          overflow: TextOverflow.clip,
          style: _style,
        ),
      );
    });
  }
}

class _MoreLess extends StatelessWidget {
  const _MoreLess({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        key: Key('title-$label'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w800, shadows: _textShadow)),
        ),
      );
}

/// "2 FOR · 3 AGAINST". Each half is a button: tap FOR or AGAINST to go to that side (the same as swiping, and what a mouse can do).
class _Tally extends StatelessWidget {
  const _Tally({required this.forCount, required this.againstCount, required this.onFor, required this.onAgainst});

  final int forCount;
  final int againstCount;
  final VoidCallback? onFor;
  final VoidCallback? onAgainst;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800, shadows: _textShadow);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _Half(key: const Key('bar-for'), text: '$forCount FOR', onTap: onFor, style: style),
      const Text('  ·  ', style: style),
      _Half(key: const Key('bar-against'), text: '$againstCount AGAINST', onTap: onAgainst, style: style),
    ]);
  }
}

class _Half extends StatelessWidget {
  const _Half({super.key, required this.text, required this.onTap, required this.style});

  final String text;
  final VoidCallback? onTap;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        label: text,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 30), child: Center(widthFactor: 1, child: Text(text, style: style))),
        ),
      );
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor = Colors.white,
    this.semantics,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color iconColor;
  final String? semantics;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantics ?? (label.isNotEmpty ? label : 'action'),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              if (label.isNotEmpty)
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, height: 1.1, shadows: [Shadow(color: Colors.black87, blurRadius: 4)])),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "heard both sides" line: visible for a few seconds each time it changes, then it fades and takes no room.
class FadingNote extends StatefulWidget {
  const FadingNote({super.key, required this.note, this.visibleFor = const Duration(milliseconds: 4500)});

  final SidesNote note;
  final Duration visibleFor;

  @override
  State<FadingNote> createState() => _FadingNoteState();
}

class _FadingNoteState extends State<FadingNote> {
  bool _show = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.visibleFor, () {
      if (mounted) setState(() => _show = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final colour = note.done ? const Color(0xFF6FD18C) : Colors.white70;
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 350),
      crossFadeState: _show ? CrossFadeState.showFirst : CrossFadeState.showSecond,
      firstChild: Semantics(
        key: const Key('sides-note'),
        label: note.text,
        excludeSemantics: true,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(note.done ? Icons.check_circle : Icons.swap_horiz, size: 14, color: colour),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              note.text,
              style: TextStyle(color: colour, fontSize: 11.5, fontWeight: FontWeight.w700, shadows: const [Shadow(color: Colors.black87, blurRadius: 4)]),
            ),
          ),
        ]),
      ),
      secondChild: const SizedBox(width: double.infinity),
    );
  }
}
