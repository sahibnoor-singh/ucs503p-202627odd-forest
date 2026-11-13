import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/user.dart';
import '../theme/forest_theme.dart';
import 'chips.dart';

/// `username [BOT] text`, clamped to two lines with an inline `… more` that
/// expands in place (prototype's `.cline`). There is no separate summary block.
class CaptionLine extends StatefulWidget {
  const CaptionLine({super.key, required this.user, required this.text});

  final User user;
  final String text;

  @override
  State<CaptionLine> createState() => _CaptionLineState();
}

class _CaptionLineState extends State<CaptionLine> {
  static const _maxLines = 2;
  static const _botGap = 4.0;

  bool _open = false;
  Size _bot = Size.zero; // measured BOT tag, set each build
  String? _cacheKey;
  String? _cacheText;

  TextStyle _base(BuildContext context) =>
      TextStyle(fontSize: 14, height: 1.3, color: context.forest.fg);

  InlineSpan _span(BuildContext context, String text, {required bool withMore}) {
    final t = context.forest;
    return TextSpan(
      style: _base(context),
      children: [
        TextSpan(
          text: widget.user.username,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (widget.user.isBot)
          const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: _botGap),
              child: BotTag(),
            ),
          )
        else
          const TextSpan(text: ' '),
        TextSpan(text: text),
        if (withMore)
          TextSpan(
            text: '… more',
            style: TextStyle(color: t.fg2, fontWeight: FontWeight.w600),
          ),
      ],
    );
  }

  TextPainter _layout(BuildContext context, String text, bool withMore, double width) {
    final painter = TextPainter(
      text: _span(context, text, withMore: withMore),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: _maxLines,
    );
    if (widget.user.isBot) {
      painter.setPlaceholderDimensions([
        PlaceholderDimensions(
          size: Size(_bot.width + _botGap * 2, _bot.height),
          alignment: PlaceholderAlignment.middle,
        ),
      ]);
    }
    painter.layout(maxWidth: width);
    return painter;
  }

  /// Where the second line ends once room is left for `… more`: one layout of
  /// the whole text and one hit-test, instead of searching. A good first guess
  /// (it is corrected below), or null when the text is not longer than two lines.
  int? _guessCut(BuildContext context, String text, double width) {
    final style = DefaultTextStyle.of(context).style;
    final painter = TextPainter(
      text: _span(context, text, withMore: false),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    );
    if (widget.user.isBot) {
      painter.setPlaceholderDimensions([
        PlaceholderDimensions(
          size: Size(_bot.width + _botGap * 2, _bot.height),
          alignment: PlaceholderAlignment.middle,
        ),
      ]);
    }
    painter.layout(maxWidth: width);
    final lines = painter.computeLineMetrics();
    if (lines.length <= _maxLines) return null;
    final more = TextPainter(
      text: TextSpan(text: '… more', style: style.merge(const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    var y = 0.0;
    for (var i = 0; i < _maxLines - 1; i++) {
      y += lines[i].height;
    }
    y += lines[_maxLines - 1].height / 2;
    final offset = painter.getPositionForOffset(Offset(math.max(0, width - more.width), y)).offset;
    final prefixLength = painter.text!.toPlainText().length - text.length;
    return offset - prefixLength;
  }

  /// The longest prefix of [text] that fits in two lines together with `… more`.
  String _fit(BuildContext context, String text, double width) {
    final key = '$width|${widget.user.isBot}|$text';
    if (_cacheKey == key) return _cacheText!;
    var cut = (_guessCut(context, text, width) ?? text.length).clamp(0, text.length);
    // Step back until it really fits (usually zero or one step).
    var steps = 0;
    while (cut > 0 &&
        _layout(context, text.substring(0, cut).trimRight(), true, width).didExceedMaxLines) {
      cut = math.max(0, cut - (steps < 6 ? 2 : 8));
      if (++steps > 40) break;
    }
    _cacheKey = key;
    _cacheText = text.substring(0, cut).trimRight();
    return _cacheText!;
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text.trim();
    _bot = BotTag.measure(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final overflows =
            _layout(context, text, false, width).didExceedMaxLines;
        if (_open || !overflows) {
          return Text.rich(_span(context, text, withMore: false));
        }
        final shown = _fit(context, text, width);
        return GestureDetector(
          onTap: () => setState(() => _open = true),
          child: Text.rich(
            _span(context, shown, withMore: true),
            maxLines: _maxLines,
            overflow: TextOverflow.clip,
          ),
        );
      },
    );
  }
}
