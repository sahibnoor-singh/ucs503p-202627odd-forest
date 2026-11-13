import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

/// The old "grounded forest" palette from Website/frontend/css/style.css.
/// The app no longer uses it for chrome (see [ForestTokens]); it stays so
/// in-flight Discover work that still references these constants compiles.
class ForestColors {
  ForestColors._();

  static const bgPrimaryDark = Color(0xFF12181F);
  static const bgSecondaryDark = Color(0xFF1A232E);
  static const bgCardDark = Color(0xD91A232E);
  static const borderGlassDark = Color(0x1FFFFFFF);
  static const textPrimaryDark = Color(0xFFF3F4F6);
  static const textSecondaryDark = Color(0xFF94A3B8);
  static const textMutedDark = Color(0xFF64748B);

  static const bgPrimaryLight = Color(0xFFF7F9FA);
  static const bgSecondaryLight = Color(0xFFFFFFFF);
  static const bgCardLight = Color(0xFFFFFFFF);
  static const borderGlassLight = Color(0xFFCBD5E1);
  static const textPrimaryLight = Color(0xFF0F172A);
  static const textSecondaryLight = Color(0xFF475569);
  static const textMutedLight = Color(0xFF64748B);

  static const forestPine = Color(0xFF2E7D5B);
  static const sageGreen = Color(0xFF3E9E74);
  static const racingGreen = Color(0xFF1B5E3C);
  static const accentPurple = Color(0xFF7C69A5);
  static const accentRed = Color(0xFFD9534F);
  static const accentGold = Color(0xFFEAB308);

  static Color forStance(String stance) {
    switch (stance) {
      case 'FOR':
        return sageGreen;
      case 'AGAINST':
        return accentRed;
      case 'UNRESOLVED':
        return accentPurple;
      default:
        return accentGold;
    }
  }
}

/// Instagram-style monochrome (PHASE1_HOME_PLAN.md §3, values copied from
/// docs/design/home_prototype.html). Colour is for meaning only: stance
/// chips, the like heart, errors, and the blue accent for links and primary
/// buttons.
@immutable
class ForestTokens extends ThemeExtension<ForestTokens> {
  const ForestTokens({
    required this.bg,
    required this.backdrop,
    required this.surface,
    required this.raised,
    required this.border,
    required this.fg,
    required this.fg2,
    required this.accent,
    required this.like,
    required this.forStance,
    required this.againstStance,
    required this.unresolvedStance,
    required this.scrim,
  });

  final Color bg;

  /// The page behind the Home cards: a different tone from the cards themselves, so the gap between two cards can be seen.
  final Color backdrop;
  final Color surface;
  final Color raised;
  final Color border;
  final Color fg;
  final Color fg2;
  final Color accent;
  final Color like;
  final Color forStance;
  final Color againstStance;
  final Color unresolvedStance;
  final Color scrim;

  static const dark = ForestTokens(
    bg: Color(0xFF121212),
    backdrop: Color(0xFF000000),
    surface: Color(0xFF1C1C1E),
    raised: Color(0xFF262628),
    border: Color(0xFF2C2C2E),
    fg: Color(0xFFF5F5F5),
    fg2: Color(0xFFA8A8A8),
    accent: Color(0xFF0095F6),
    like: Color(0xFFFF3040),
    forStance: Color(0xFF5FBF7F),
    againstStance: Color(0xFFE5645F),
    unresolvedStance: Color(0xFFA78BFA),
    scrim: Color(0x99000000),
  );

  static const light = ForestTokens(
    bg: Color(0xFFFFFFFF),
    backdrop: Color(0xFFE6E9ED),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFFAFAFA),
    border: Color(0xFFDBDBDB),
    fg: Color(0xFF000000),
    fg2: Color(0xFF737373),
    accent: Color(0xFF0095F6),
    like: Color(0xFFFF3040),
    forStance: Color(0xFF1E7B3F),
    againstStance: Color(0xFFC0392B),
    unresolvedStance: Color(0xFF6D4AC9),
    scrim: Color(0x73000000),
  );

  /// Colour for a stance's wire name (`FOR`, `AGAINST`, `UNRESOLVED`);
  /// anything else (a root opinion) is neutral.
  Color stance(String wire) {
    switch (wire) {
      case 'FOR':
        return forStance;
      case 'AGAINST':
        return againstStance;
      case 'UNRESOLVED':
        return unresolvedStance;
      default:
        return fg2;
    }
  }

  @override
  ForestTokens copyWith({
    Color? bg,
    Color? backdrop,
    Color? surface,
    Color? raised,
    Color? border,
    Color? fg,
    Color? fg2,
    Color? accent,
    Color? like,
    Color? forStance,
    Color? againstStance,
    Color? unresolvedStance,
    Color? scrim,
  }) =>
      ForestTokens(
        bg: bg ?? this.bg,
        backdrop: backdrop ?? this.backdrop,
        surface: surface ?? this.surface,
        raised: raised ?? this.raised,
        border: border ?? this.border,
        fg: fg ?? this.fg,
        fg2: fg2 ?? this.fg2,
        accent: accent ?? this.accent,
        like: like ?? this.like,
        forStance: forStance ?? this.forStance,
        againstStance: againstStance ?? this.againstStance,
        unresolvedStance: unresolvedStance ?? this.unresolvedStance,
        scrim: scrim ?? this.scrim,
      );

  @override
  ForestTokens lerp(ThemeExtension<ForestTokens>? other, double t) {
    if (other is! ForestTokens) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return ForestTokens(
      bg: mix(bg, other.bg),
      backdrop: mix(backdrop, other.backdrop),
      surface: mix(surface, other.surface),
      raised: mix(raised, other.raised),
      border: mix(border, other.border),
      fg: mix(fg, other.fg),
      fg2: mix(fg2, other.fg2),
      accent: mix(accent, other.accent),
      like: mix(like, other.like),
      forStance: mix(forStance, other.forStance),
      againstStance: mix(againstStance, other.againstStance),
      unresolvedStance: mix(unresolvedStance, other.unresolvedStance),
      scrim: mix(scrim, other.scrim),
    );
  }
}

extension ForestContext on BuildContext {
  /// The tokens for the current theme. Falls back to the matching built-in
  /// set when the app is wrapped in a plain `ThemeData` (some tests do that).
  ForestTokens get forest {
    final theme = Theme.of(this);
    return theme.extension<ForestTokens>() ??
        (theme.brightness == Brightness.dark ? ForestTokens.dark : ForestTokens.light);
  }
}

class ForestTheme {
  ForestTheme._();

  /// The prototype's font stack ends in Roboto, so Android ships it (bundled in
  /// assets/fonts). Asking OxygenOS for a system family rendered everything in a
  /// serif face. iOS uses its system font (null).
  static String? get _fontFamily => defaultTargetPlatform == TargetPlatform.iOS ? null : 'Roboto';

  static ThemeData get dark => _build(ForestTokens.dark, Brightness.dark);
  static ThemeData get light => _build(ForestTokens.light, Brightness.light);

  static ThemeData _build(ForestTokens t, Brightness brightness) {
    final base = ThemeData(brightness: brightness, useMaterial3: true, fontFamily: _fontFamily);
    final scheme = (brightness == Brightness.dark
            ? const ColorScheme.dark()
            : const ColorScheme.light())
        .copyWith(
      primary: t.accent,
      onPrimary: Colors.white,
      secondary: t.fg2,
      onSecondary: t.bg,
      error: t.like,
      onError: Colors.white,
      surface: t.surface,
      onSurface: t.fg,
      surfaceContainerHighest: t.raised,
      outline: t.border,
      outlineVariant: t.border,
    );

    // The prototype's body is 15px with a 1.35 line height; everything else
    // sets only a size and inherits that line height.
    final applied = base.textTheme.apply(bodyColor: t.fg, displayColor: t.fg);
    final text = applied.copyWith(
      bodyLarge: applied.bodyLarge?.copyWith(fontSize: 15, height: 1.35, letterSpacing: 0),
      bodyMedium: applied.bodyMedium?.copyWith(fontSize: 15, height: 1.35, letterSpacing: 0),
      bodySmall: applied.bodySmall?.copyWith(color: t.fg2, fontSize: 12, height: 1.35, letterSpacing: 0),
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: t.bg,
      cardColor: t.surface,
      dividerColor: t.border,
      textTheme: text,
      extensions: [t],
      appBarTheme: AppBarTheme(
        backgroundColor: t.bg,
        foregroundColor: t.fg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(color: t.border, space: 1, thickness: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.raised,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: t.raised,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: t.fg,
        contentTextStyle: TextStyle(color: t.bg, fontSize: 13.5, fontWeight: FontWeight.w600),
        actionTextColor: t.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: t.bg,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        elevation: 0,
        height: 58,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected) ? t.fg : t.fg2,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected) ? t.fg : t.fg2,
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: t.fg2),
    );
  }
}
