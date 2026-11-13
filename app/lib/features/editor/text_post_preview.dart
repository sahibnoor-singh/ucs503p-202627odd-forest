import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'adjust_filter.dart';
import 'overlay_layer.dart';
import 'recipe.dart';

/// The picture of a post that has no video of its own, as near as the phone can draw what the server will render: the
/// background, the big text with its animation (looping), and any text laid over it. The proportions are those of the
/// finished video (9:16); sizes are given for a 720-pixel-wide picture and scaled to fit.
class TextPostPreview extends StatefulWidget {
  const TextPostPreview({super.key, required this.recipe, this.onOverlayMoved, this.onOverlayTap, this.selectedOverlay});

  final Recipe recipe;

  /// A piece of text on the picture was dragged: its new centre, as fractions of the picture.
  final void Function(int index, double x, double y)? onOverlayMoved;
  final void Function(int index)? onOverlayTap;
  final int? selectedOverlay;

  @override
  State<TextPostPreview> createState() => _TextPostPreviewState();
}

class _TextPostPreviewState extends State<TextPostPreview> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: _loopLength(widget.recipe));

  /// The animation plays once over the first seconds, then the picture rests for a moment before it starts again.
  static Duration _loopLength(Recipe r) =>
      Duration(milliseconds: ((r.text.animation == TextAnimation.none ? 1.0 : (r.durationSec.clamp(3.0, 12.0)) + 1.0) * 1000).round());

  @override
  void initState() {
    super.initState();
    _clock.repeat();
  }

  @override
  void didUpdateWidget(TextPostPreview old) {
    super.didUpdateWidget(old);
    final length = _loopLength(widget.recipe);
    if (length != _clock.duration) {
      _clock.duration = length;
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  /// Where the gradient starts or ends for an angle in degrees: 0 = `from` at the top, 90 = `from` at the left.
  static Alignment _from(double angle, {required bool end}) {
    final a = angle * math.pi / 180;
    final dx = math.sin(a);
    final dy = math.cos(a);
    return end ? Alignment(dx, dy) : Alignment(-dx, -dy);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.recipe;
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: LayoutBuilder(builder: (context, box) {
        final scale = box.maxWidth / 720;
        final bg = r.background;
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              AdjustedPicture(
                adjust: r.adjust,
                pictureWidth: box.maxWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: bg.isGradient ? null : bg.from,
                    gradient: bg.isGradient
                        ? LinearGradient(begin: _from(bg.angle, end: false), end: _from(bg.angle, end: true), colors: [bg.from, bg.to!])
                        : null,
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _clock,
                builder: (context, _) => _BigText(
                  spec: r.text,
                  seconds: _clock.value * (_clock.duration!.inMilliseconds / 1000),
                  scale: scale,
                  durationSec: r.durationSec,
                ),
              ),
              OverlayLayer(
                overlays: r.overlays,
                size: Size(box.maxWidth, box.maxHeight),
                selected: widget.selectedOverlay,
                onMoved: widget.onOverlayMoved,
                onTap: widget.onOverlayTap,
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _BigText extends StatelessWidget {
  const _BigText({required this.spec, required this.seconds, required this.scale, required this.durationSec});

  final TextSpec spec;
  final double seconds;
  final double scale;
  final double durationSec;

  // compose/ass.js: a 0.7 s fade (and a 90 px rise for "slide up"); typewriter 0.06 s per letter and word by word 0.35 s per
  // word, both squeezed to fit in 60 % of the post's length when the text is long
  static const _fadeSeconds = .7;
  static const _riseOutputPixels = 90.0;

  @override
  Widget build(BuildContext context) {
    final raw = spec.content.isEmpty ? 'Your words appear here' : serverWrap(spec.content);
    final placeholder = spec.content.isEmpty;
    final style = TextStyle(
      color: placeholder ? spec.color.withValues(alpha: .35) : spec.color,
      fontSize: spec.size * kServerLetterScale * scale,
      fontFamily: spec.font.family,
      fontWeight: FontWeight.w700,
      height: kServerLineHeight,
      shadows: serverTextShadows(scale),
    );
    final show = placeholder ? TextAnimation.none : spec.animation;

    double opacity = 1;
    double lift = 0;
    var text = raw;
    switch (show) {
      case TextAnimation.none:
        break;
      case TextAnimation.fade:
        opacity = (seconds / _fadeSeconds).clamp(0.0, 1.0);
      case TextAnimation.slideUp:
        final p = (seconds / _fadeSeconds).clamp(0.0, 1.0);
        opacity = p;
        lift = (1 - p) * _riseOutputPixels * scale;
      case TextAnimation.typewriter:
        break;
      case TextAnimation.wordByWord:
        break;
    }

    Widget body;
    if (show == TextAnimation.typewriter || show == TextAnimation.wordByWord) {
      // keep the whole text in place (hidden part transparent) so the lines do not jump as it appears
      final letters = raw.characters.length; // letters as people see them: a Hindi conjunct or an emoji counts once
      final words = raw.trim().split(RegExp(r'\s+')).length;
      final letterStep = math.min(0.06, durationSec * 0.6 / math.max(1, letters));
      final wordStep = math.min(0.35, durationSec * 0.6 / math.max(1, words));
      final shown = show == TextAnimation.typewriter
          ? raw.characters.take((seconds / letterStep).floor().clamp(0, letters)).string.length
          : _charsOfWords(raw, (seconds / wordStep).floor() + 1);
      body = RichText(
        textAlign: spec.align.align,
        text: TextSpan(style: style, children: [
          TextSpan(text: raw.substring(0, shown)),
          TextSpan(text: raw.substring(shown), style: const TextStyle(color: Colors.transparent)),
        ]),
      );
    } else {
      body = Text(text, textAlign: spec.align.align, style: style);
    }
    body = BalancedBox(text: raw, style: style, child: body);
    return Padding(
      padding: EdgeInsets.fromLTRB((spec.align == TextAlignment.left ? 70 : 60) * scale, 0, (spec.align == TextAlignment.right ? 70 : 60) * scale, 0),
      child: Align(
        alignment: Alignment.center,
        child: Transform.translate(offset: Offset(0, lift), child: Opacity(opacity: opacity, child: body)),
      ),
    );
  }

  /// How many characters the first [words] words of [text] take (with the spaces before them).
  static int _charsOfWords(String text, int words) {
    var count = 0;
    var i = 0;
    while (i < text.length && count < words) {
      while (i < text.length && text[i].trim().isEmpty) {
        i++;
      }
      if (i >= text.length) break;
      while (i < text.length && text[i].trim().isNotEmpty) {
        i++;
      }
      count++;
    }
    return i;
  }
}
