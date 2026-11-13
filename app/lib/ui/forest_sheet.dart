import 'package:flutter/material.dart';

import '../theme/forest_theme.dart';
import 'reel_focus.dart';

/// Opens a bottom sheet in the prototype's style (20px top radius, `raised`
/// fill, grab handle, scrim) and pauses the feed's videos while it is open.
/// A [tall] sheet is 88% of the screen and its [builder] content must size
/// itself (use `Expanded` for the scrolling part).
Future<T?> showForestSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool tall = false,
}) {
  final tokens = context.forest;
  return pauseFeedWhile<T>(
    context,
    () => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: tokens.raised,
      barrierColor: tokens.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _SheetFrame(tall: tall, child: builder(sheetContext)),
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.tall, required this.child});

  final bool tall;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final t = context.forest;
    final handle = Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(color: t.border, borderRadius: BorderRadius.circular(9)),
      ),
    );
    final content = tall
        ? Expanded(child: child)
        : Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
              child: child,
            ),
          );
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: tall ? media.size.height * 0.88 : null,
        child: Column(
          mainAxisSize: tall ? MainAxisSize.max : MainAxisSize.min,
          children: [handle, content],
        ),
      ),
    );
  }
}

/// A tappable row inside a sheet (`.row-btn`).
class SheetRow extends StatelessWidget {
  const SheetRow({super.key, required this.label, required this.onTap, this.danger = false});

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.border))),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: danger ? t.like : t.fg,
          ),
        ),
      ),
    );
  }
}

/// The 2-line quote of what you are replying to (`.ctx`).
class SheetContext extends StatelessWidget {
  const SheetContext(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Container(
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: t.border, width: 2))),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13.5, color: t.fg2),
      ),
    );
  }
}
