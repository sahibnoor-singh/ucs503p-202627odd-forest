import 'package:flutter/material.dart';

import '../../models/video.dart';
import '../../theme/forest_theme.dart';
import '../../ui/chips.dart';

/// One post in the Discover grid: its picture, how the debate stands (FOR / AGAINST), a BOT label for automated accounts (always,
/// CLAUDE.md hard rule) and, on the big tiles, the title and who posted it. Tapping opens the post in the full-screen feed.
class DiscoverTile extends StatelessWidget {
  const DiscoverTile({
    super.key,
    required this.video,
    required this.coverUrl,
    required this.big,
    required this.onTap,
  });

  final Video video;

  /// Absolute URL of the post's picture, or null (the title is shown on a plain background instead).
  final String? coverUrl;

  /// Room for a title: this tile is bigger than one cell.
  final bool big;
  final VoidCallback onTap;

  static const _scrimText = TextStyle(color: Colors.white, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 3, color: Colors.black54)]);

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final title = (video.title ?? '').trim().isNotEmpty ? video.title!.trim() : video.caption.trim();
    final hasScore = video.forCount + video.againstCount > 0;

    return Semantics(
      button: true,
      label: '${title.isEmpty ? 'Video' : title} by ${video.userName}${video.isBot ? ' (automated account)' : ''}'
          '${hasScore ? ', ${video.forCount} for, ${video.againstCount} against' : ''}',
      excludeSemantics: true,
      child: Material(
        color: t.raised,
        child: InkWell(
          onTap: onTap,
          child: LayoutBuilder(builder: (context, box) {
            final dpr = MediaQuery.devicePixelRatioOf(context);
            return Stack(
              fit: StackFit.expand,
              children: [
                if (coverUrl != null)
                  Image.network(
                    coverUrl!,
                    fit: BoxFit.cover,
                    // decode at the size it is drawn: a 720 px picture in a 120 dp tile is wasted memory
                    cacheWidth: (box.maxWidth * dpr).ceil(),
                    frameBuilder: (context, child, frame, sync) => sync
                        ? child
                        : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 180), child: child),
                    errorBuilder: (_, _, _) => _Plain(title: title, big: big),
                  )
                else
                  _Plain(title: title, big: big),
                // darkens the bottom so the white text reads on any picture
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 64,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xB3000000)]),
                    ),
                  ),
                ),
                Positioned(
                  left: 6,
                  right: 6,
                  bottom: 5,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (big && title.isNotEmpty)
                        Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: _scrimText.copyWith(fontSize: 13, height: 1.2)),
                      if (big)
                        Text('@${video.userName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _scrimText.copyWith(fontSize: 11, fontWeight: FontWeight.w500)),
                      if (hasScore) ...[
                        if (big) const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Count(color: t.forStance, count: video.forCount),
                            const SizedBox(width: 6),
                            _Count(color: t.againstStance, count: video.againstCount),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (video.isBot) const Positioned(left: 5, top: 5, child: BotTag(compact: true)),
                const Positioned(
                  right: 5,
                  top: 4,
                  child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18, shadows: [Shadow(blurRadius: 4, color: Colors.black54)]),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

/// A coloured dot and a number: "3 people took this side".
class _Count extends StatelessWidget {
  const _Count({required this.color, required this.count});

  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 3),
          Text('$count', style: DiscoverTile._scrimText.copyWith(fontSize: 11)),
        ],
      );
}

/// The tile of a post that has no picture (yet): its title on a plain background.
class _Plain extends StatelessWidget {
  const _Plain({required this.title, required this.big});

  final String title;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 24, 8, 24),
      child: Center(
        child: big
            ? const SizedBox.shrink() // the title is already printed over the bottom of a big tile
            : Text(
                title,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.fg2, fontSize: 11, height: 1.25),
              ),
      ),
    );
  }
}
