import 'package:flutter/material.dart';

/// Colours the editor offers. Plain lists, so the panels and the tests use the same ones.
class EditorPalette {
  /// For text.
  static const textColors = <Color>[
    Color(0xFFFFFFFF),
    Color(0xFF111111),
    Color(0xFFFFE066),
    Color(0xFFFF8A5B),
    Color(0xFFFF5C7A),
    Color(0xFFB794F6),
    Color(0xFF63B3FF),
    Color(0xFF5EE0B4),
    Color(0xFF9AE66E),
    Color(0xFFF5F0E6),
  ];

  /// Colours for a solid background, and the pick-your-own gradient ends.
  static const backgrounds = <Color>[
    Color(0xFF111111),
    Color(0xFF16201C),
    Color(0xFF0F2027),
    Color(0xFF1F2A5C),
    Color(0xFF4A1D6B),
    Color(0xFF7A1F3D),
    Color(0xFFB4442D),
    Color(0xFFE3A72F),
    Color(0xFF1F7A5C),
    Color(0xFF2C5364),
    Color(0xFF3B82F6),
    Color(0xFFF8FAFC),
  ];

  /// Ready-made gradients: from, to, angle (0 = `from` at the top, 90 = at the left).
  static const gradients = <GradientPreset>[
    GradientPreset('Night', Color(0xFF0F2027), Color(0xFF2C5364), 180),
    GradientPreset('Forest', Color(0xFF134E4A), Color(0xFF16A34A), 160),
    GradientPreset('Dusk', Color(0xFF2B1055), Color(0xFFD53369), 150),
    GradientPreset('Ember', Color(0xFF7A1F3D), Color(0xFFF59E0B), 160),
    GradientPreset('Ocean', Color(0xFF1E3A8A), Color(0xFF22D3EE), 170),
    GradientPreset('Mint', Color(0xFF0F766E), Color(0xFFA7F3D0), 140),
    GradientPreset('Plum', Color(0xFF3B0764), Color(0xFF6366F1), 180),
    GradientPreset('Sand', Color(0xFFB45309), Color(0xFFFDE68A), 150),
    GradientPreset('Slate', Color(0xFF0F172A), Color(0xFF475569), 175),
    GradientPreset('Berry', Color(0xFF831843), Color(0xFFF472B6), 135),
  ];
}

class GradientPreset {
  const GradientPreset(this.name, this.from, this.to, this.angle);
  final String name;
  final Color from;
  final Color to;
  final double angle;
}
