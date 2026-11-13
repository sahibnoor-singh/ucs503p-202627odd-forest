import 'package:flutter/material.dart';

import '../../theme/forest_theme.dart';
import 'letters.dart';

/// Small controls the editor's panels share.

/// Seconds as m:ss.t, e.g. 1:05.5.
String clockText(double seconds) {
  final s = seconds.clamp(0, 359999).toDouble();
  final m = s ~/ 60;
  final rest = (s - m * 60).toStringAsFixed(1).padLeft(4, '0');
  return '$m:$rest';
}

/// Under a text field whose words go on the picture: says when a letter cannot be drawn there (red) or that emoji lose their
/// colour (grey). Nothing at all for ordinary text.
class LettersNote extends StatelessWidget {
  const LettersNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final check = checkLetters(text);
    final message = check.message;
    if (message == null) return const SizedBox.shrink();
    final t = context.forest;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Text(message, style: TextStyle(fontSize: 12, color: check.unsupported ? t.againstStance : t.fg2)),
    );
  }
}

class PanelLabel extends StatelessWidget {
  const PanelLabel(this.text, {super.key, this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Row(
        children: [
          Text(text.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: t.fg2)),
          const Spacer(),
          if (trailing != null) Text(trailing!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.fg)),
        ],
      ),
    );
  }
}

/// A row of colour dots; the picked one has a ring.
class ColorDots extends StatelessWidget {
  const ColorDots({super.key, required this.colors, required this.selected, required this.onPick, this.size = 30});

  final List<Color> colors;
  final Color? selected;
  final ValueChanged<Color> onPick;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return SizedBox(
      height: size + 8,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: colors.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final c = colors[i];
          final on = selected != null && selected!.toARGB32() == c.toARGB32();
          return Semantics(
            button: true,
            selected: on,
            label: 'Colour ${i + 1}',
            child: GestureDetector(
              onTap: () => onPick(c),
              child: Container(
                width: size,
                height: size,
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(color: on ? t.fg : t.border, width: on ? 2.5 : 1),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One choice out of several, drawn as a pill.
class ChoicePills<T> extends StatelessWidget {
  const ChoicePills({super.key, required this.values, required this.selected, required this.label, required this.onPick});

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    // Wrap, not a scrolling row: every choice stays visible (and reachable) without hunting for it.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in values)
          GestureDetector(
            onTap: () => onPick(v),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: v == selected ? t.fg : Colors.transparent,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: v == selected ? t.fg : t.border),
              ),
              // widthFactor: 1 keeps the pill as wide as its words (a plain Center would fill the whole row)
              child: Center(
                widthFactor: 1,
                child: Text(label(v), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: v == selected ? t.bg : t.fg)),
              ),
            ),
          ),
      ],
    );
  }
}

/// A slider with a name on the left and its value on the right.
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.display,
    this.divisions,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String Function(double)? display;
  final int? divisions;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Row(
      children: [
        SizedBox(width: 78, child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.fg2))),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8), overlayShape: SliderComponentShape.noOverlay),
            child: Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, onChanged: onChanged, activeColor: t.fg, inactiveColor: t.border),
          ),
        ),
        SizedBox(width: 54, child: Text(display?.call(value) ?? value.toStringAsFixed(1), textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.fg))),
      ],
    );
  }
}

/// A square icon button with a label under it, for rows of choices (alignment, transition ...).
class IconChoice extends StatelessWidget {
  const IconChoice({super.key, required this.icon, required this.on, required this.onTap, this.label});

  final IconData icon;
  final bool on;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Semantics(
      button: true,
      selected: on,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 40,
          decoration: BoxDecoration(
            color: on ? t.fg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: on ? t.fg : t.border),
          ),
          child: Icon(icon, size: 20, color: on ? t.bg : t.fg),
        ),
      ),
    );
  }
}
