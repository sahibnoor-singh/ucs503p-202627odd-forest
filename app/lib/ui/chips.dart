import 'package:flutter/material.dart';

import '../models/post.dart';
import '../theme/forest_theme.dart';

/// `BOT` label (prototype `.bot`: 9px, weight 800, letter-spacing .08em,
/// padding 2px 5px, 1px outline, radius 4). Bot/seed accounts are always
/// marked wherever their name appears (CLAUDE.md hard rule). It sizes itself to
/// its text, so it can never be clipped.
class BotTag extends StatelessWidget {
  /// [compact] is the small filled pill that sits on a story ring.
  const BotTag({super.key, this.compact = false});

  final bool compact;

  static const _textStyle = TextStyle(
    fontSize: 9,
    height: 1.35,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.72,
  );

  /// The tag's size in [context] (for inline text layout that must reserve room).
  static Size measure(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: 'BOT', style: DefaultTextStyle.of(context).style.merge(_textStyle)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return Size(painter.width + 12, painter.height + 6); // 5+5 padding +2 border, 2+2 +2
  }

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Semantics(
      label: 'Automated account',
      excludeSemantics: true,
      child: Container(
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5)
            : const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: compact ? t.bg : null,
          border: Border.all(color: t.fg2),
          borderRadius: BorderRadius.circular(compact ? 3 : 4),
        ),
        child: Text(
          'BOT',
          style: _textStyle.copyWith(
            color: t.fg2,
            fontSize: compact ? 7.5 : 9,
            height: compact ? 1.2 : 1.35,
            letterSpacing: compact ? 0.4 : 0.72,
          ),
        ),
      ),
    );
  }
}

const _chipText = TextStyle(
  fontSize: 10,
  height: 1.35,
  fontWeight: FontWeight.w700,
  letterSpacing: 0.7,
);

/// FOR / AGAINST / UNRESOLVED pill (prototype `.chip`). Draws nothing for a
/// root opinion.
class StanceChip extends StatelessWidget {
  const StanceChip({super.key, required this.stance});

  final Stance stance;

  @override
  Widget build(BuildContext context) {
    if (stance == Stance.parent) return const SizedBox.shrink();
    final color = context.forest.stance(stance.wire);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(stance.wire, style: _chipText.copyWith(color: color)),
    );
  }
}

/// Outlined, no-fill chip: `OPINION`, `PARENT VIDEO` (`.chip.opinion`).
class OutlineChip extends StatelessWidget {
  const OutlineChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(label, style: _chipText.copyWith(color: t.fg2)),
    );
  }
}
