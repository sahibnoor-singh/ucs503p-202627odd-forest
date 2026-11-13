import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/forest_theme.dart';

/// Names of the prototype's own icons in `assets/icons/`. The path data is
/// copied verbatim from `docs/design/home_prototype.html` (the `I` object plus
/// the inline icons); line icons are drawn 1.9 wide with round caps and joins
/// and no fill, like the prototype's `.ic`.
abstract final class Icn {
  static const heart = 'heart';
  static const heartFilled = 'heart_filled';
  static const heartBurst = 'heart_burst';
  static const comment = 'comment';
  static const reply = 'reply';
  static const send = 'send'; // the paper plane: share link
  static const more = 'more';
  static const play = 'play';
  static const muted = 'muted';
  static const sound = 'sound';
  static const upload = 'upload';
  static const image = 'image';
  static const cam = 'cam';
  static const check = 'check';
  static const back = 'back';
  static const close = 'close';
  static const avatar = 'avatar';
  static const navHome = 'nav_home';
  static const navDiscover = 'nav_discover';
  static const navUpload = 'nav_upload';
  static const navAccount = 'nav_account';
}

/// One of the prototype's icons, drawn in [color] (the theme's text colour
/// when not given).
class ForestIcon extends StatelessWidget {
  const ForestIcon(this.name, {super.key, this.size = 18, this.color});

  final String name;
  final double size;
  final Color? color;

  /// Every icon, for [precacheIcons].
  static const all = [
    Icn.heart, Icn.heartFilled, Icn.heartBurst, Icn.comment, Icn.reply, Icn.send,
    Icn.more, Icn.play, Icn.muted, Icn.sound, Icn.upload, Icn.image, Icn.cam,
    Icn.check, Icn.back, Icn.close, Icn.avatar, Icn.navHome, Icn.navDiscover,
    Icn.navUpload, Icn.navAccount, 'nav_home_active', 'nav_discover_active',
    'nav_upload_active', 'nav_account_active',
  ];

  /// Compiles every icon in the colours the app draws it in, ahead of time, so
  /// cards that scroll into view draw them at once instead of parsing SVG.
  /// (The colour is part of the cached copy, which is much cheaper to paint than
  /// recolouring each icon with a colour filter, a GPU layer per icon.)
  static Future<void> precacheIcons() async {
    final colors = <Color>{Colors.white};
    for (final t in [ForestTokens.dark, ForestTokens.light]) {
      colors.addAll([t.fg, t.fg2, t.like, t.fg2.withValues(alpha: 0.85)]);
    }
    var n = 0;
    for (final name in all) {
      for (final color in colors) {
        try {
          await _loader(name, color).loadBytes(null);
        } on Object {
          // A missing icon will show up when it is drawn.
        }
        if (++n % 12 == 0) await Future<void>.delayed(Duration.zero); // stay out of the way of frames
      }
    }
  }

  static SvgAssetLoader _loader(String name, Color color) =>
      SvgAssetLoader('assets/icons/$name.svg', theme: SvgTheme(currentColor: color));

  @override
  Widget build(BuildContext context) {
    return SvgPicture(
      _loader(name, color ?? context.forest.fg),
      width: size,
      height: size,
    );
  }
}
