import 'package:flutter/material.dart';

import 'recipe.dart';

/// The server draws text with libass, whose \`size\` is the height of a whole line, not of the letters: letters come out about 85 % of
/// the size, with lines packed at about 97 % of it. Measured on real renders (see docs/EDITOR_PLAN.md), so the preview matches.
const double kServerLetterScale = 0.855;
const double kServerLineHeight = 1.14;

/// The server's renderer only breaks lines at spaces; Flutter also breaks after a hyphen. A word joiner after each hyphen stops that,
/// so "open-book" wraps the same way in the preview as in the posted video.
final String _wordJoiner = String.fromCharCode(0x2060); // zero width, and no line break next to it
String serverWrap(String text) => text.replaceAllMapped(RegExp(r'-(?=\S)'), (m) => '-$_wordJoiner');

/// The narrowest width that keeps [text] on as many lines as it takes in [maxWidth]. The server's renderer (libass "smart
/// wrapping") evens the lines out instead of filling each one as far as it goes, so "Exams should / be open-book" rather than
/// "Exams should be / open-book"; laying the preview text out in this width gives the same breaks.
double balancedWidth(BuildContext context, String text, TextStyle style, double maxWidth) {
  TextPainter painter(double width) => TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: width);
  final full = painter(maxWidth);
  final lines = full.computeLineMetrics().length;
  if (lines < 2) return full.width.clamp(0, maxWidth) + 1;
  var low = 0.0;
  var high = maxWidth;
  for (var i = 0; i < 18; i++) {
    final mid = (low + high) / 2;
    if (painter(mid).computeLineMetrics().length <= lines) {
      high = mid;
    } else {
      low = mid;
    }
  }
  return high + 1;
}

/// Gives [child] (the text itself) the width [balancedWidth] works out for [text] inside whatever space it is offered.
class BalancedBox extends StatelessWidget {
  const BalancedBox({super.key, required this.text, required this.style, required this.child});

  final String text;
  final TextStyle style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth.isFinite ? SizedBox(width: balancedWidth(context, text, style, box.maxWidth), child: child) : child,
    );
  }
}

/// The black edge and soft shadow the server gives every piece of text.
List<Shadow> serverTextShadows(double scale) => [
      Shadow(blurRadius: 3 * scale, color: const Color(0xCC000000)),
      Shadow(offset: Offset(0, 1.5 * scale), blurRadius: 2 * scale, color: const Color(0x99000000)),
    ];

/// A piece of text laid over a picture.
class OverlayText extends StatelessWidget {
  const OverlayText({super.key, required this.overlay, required this.scale, required this.maxWidth, this.selected = false});

  final TextOverlay overlay;
  final double scale;
  final double maxWidth;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final text = serverWrap(overlay.text);
    final style = TextStyle(
      color: overlay.color,
      fontSize: overlay.size * kServerLetterScale * scale,
      fontFamily: overlay.font.family,
      fontWeight: FontWeight.w700,
      height: kServerLineHeight,
      shadows: serverTextShadows(scale),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: selected ? BoxDecoration(border: Border.all(color: Colors.white70), borderRadius: BorderRadius.circular(6)) : null,
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: BalancedBox(
        text: text,
        style: style,
        child: Text(text, textAlign: TextAlign.center, style: style),
      ),
    );
  }
}

/// All the text laid over a picture, draggable. Put it in a [Stack] that is as big as the picture.
class OverlayLayer extends StatelessWidget {
  const OverlayLayer({
    super.key,
    required this.overlays,
    required this.size,
    this.selected,
    this.onMoved,
    this.onTap,
  });

  final List<TextOverlay> overlays;

  /// The size of the picture on screen; text sizes are given for a 720-pixel-wide picture and scaled to it.
  final Size size;
  final int? selected;

  /// A piece of text was dragged: its new centre, as fractions of the picture.
  final void Function(int index, double x, double y)? onMoved;
  final void Function(int index)? onTap;

  @override
  Widget build(BuildContext context) {
    final scale = size.width / 720;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = 0; i < overlays.length; i++)
          Positioned(
            left: overlays[i].x * size.width,
            top: overlays[i].y * size.height,
            child: FractionalTranslation(
              translation: const Offset(-.5, -.5),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap == null ? null : () => onTap!(i),
                onPanUpdate: onMoved == null
                    ? null
                    : (d) => onMoved!(
                          i,
                          (overlays[i].x + d.delta.dx / size.width).clamp(0.0, 1.0),
                          (overlays[i].y + d.delta.dy / size.height).clamp(0.0, 1.0),
                        ),
                child: OverlayText(overlay: overlays[i], scale: scale, maxWidth: size.width * .85, selected: selected == i),
              ),
            ),
          ),
      ],
    );
  }
}
