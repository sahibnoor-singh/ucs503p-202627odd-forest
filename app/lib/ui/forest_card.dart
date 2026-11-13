import 'package:flutter/material.dart';

import '../theme/forest_theme.dart';

/// Card shell for every feed card (prototype `.card` / `.orig`): 1px border,
/// radius 14 (12 for the boxed original), a flex column with a [gap] between
/// rows and [bottomPad] under the last. Media runs edge to edge; each text row
/// brings its own horizontal inset.
class ForestCard extends StatelessWidget {
  const ForestCard({
    super.key,
    required this.children,
    this.raised = false,
    this.radius = 14,
    this.gap = 2,
    this.bottomPad = 3,
  });

  final List<Widget> children;

  /// Use the `raised` fill (quoted / original blocks) instead of `surface`.
  final bool raised;
  final double radius;
  final double gap;
  final double bottomPad;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Container(
      // No clip: nothing inside reaches the rounded corners, and clipping a card that
      // holds a video texture costs a GPU layer per card per frame while scrolling.
      clipBehavior: Clip.none,
      padding: EdgeInsets.only(bottom: bottomPad),
      decoration: BoxDecoration(
        color: raised ? t.raised : t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            children[i],
          ],
        ],
      ),
    );
  }
}
