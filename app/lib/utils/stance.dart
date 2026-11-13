import 'package:flutter/material.dart';

/// Stance badge colors and theme helpers matching the clean design in the screenshots.
class StanceColors {
  StanceColors._();

  // FOR: Crisp mint/green
  static const forBg = Color(0xFFEAF7EE);
  static const forText = Color(0xFF16A34A);
  static const forBorder = Color(0xFFBBF7D0);

  // AGAINST: Clean coral/red
  static const againstBg = Color(0xFFFEECEB);
  static const againstText = Color(0xFFDC2626);
  static const againstBorder = Color(0xFFFECACA);

  // UNRESOLVED: Soft lavender/purple
  static const unresolvedBg = Color(0xFFF3E8FF);
  static const unresolvedText = Color(0xFF7C3AED);
  static const unresolvedBorder = Color(0xFFDDD6FE);

  // OPINION / ROOT: Neutral slate/grey
  static const opinionBg = Color(0xFFF3F4F6);
  static const opinionText = Color(0xFF4B5563);
  static const opinionBorder = Color(0xFFE5E7EB);
}

Color stanceTextColor(String stance) {
  switch (stance.toUpperCase()) {
    case 'FOR':
      return StanceColors.forText;
    case 'AGAINST':
      return StanceColors.againstText;
    case 'UNRESOLVED':
      return StanceColors.unresolvedText;
    default:
      return StanceColors.opinionText;
  }
}

Color stanceBgColor(String stance) {
  switch (stance.toUpperCase()) {
    case 'FOR':
      return StanceColors.forBg;
    case 'AGAINST':
      return StanceColors.againstBg;
    case 'UNRESOLVED':
      return StanceColors.unresolvedBg;
    default:
      return StanceColors.opinionBg;
  }
}

Color stanceBorderColor(String stance) {
  switch (stance.toUpperCase()) {
    case 'FOR':
      return StanceColors.forBorder;
    case 'AGAINST':
      return StanceColors.againstBorder;
    case 'UNRESOLVED':
      return StanceColors.unresolvedBorder;
    default:
      return StanceColors.opinionBorder;
  }
}

String stanceLabel(String stance, String role) {
  if (role.toUpperCase() != 'CHILD') return 'OPINION';
  return stance.toUpperCase();
}

IconData stanceIcon(String stance) {
  switch (stance.toUpperCase()) {
    case 'FOR':
      return Icons.thumb_up_alt_outlined;
    case 'AGAINST':
      return Icons.thumb_down_alt_outlined;
    case 'UNRESOLVED':
      return Icons.help_outline_rounded;
    default:
      return Icons.record_voice_over_outlined;
  }
}

/// Reusable Stance Badge matching the exact pill design from the screenshots.
class StanceBadge extends StatelessWidget {
  const StanceBadge({
    super.key,
    required this.stance,
    this.role = 'PARENT',
    this.customLabel,
  });

  final String stance;
  final String role;
  final String? customLabel;

  @override
  Widget build(BuildContext context) {
    final label = customLabel ?? stanceLabel(stance, role);
    final bg = stanceBgColor(stance);
    final textCol = stanceTextColor(stance);
    final borderCol = stanceBorderColor(stance);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderCol, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textCol,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
