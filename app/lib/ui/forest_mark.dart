import 'package:flutter/material.dart';

/// The FOREST mark: three stacked pine tiers and a trunk on a green rounded square. Drawn, not an image, so it is sharp at any size
/// and needs no asset. Same shape as the app icon.
class ForestMark extends StatelessWidget {
  const ForestMark({super.key, this.size = 48});

  final double size;

  static const _green = Color(0xFF1D6B49);
  static const _tree = Color(0xFFF6FAF7);
  static const _trunk = Color(0xFFE8F0EB);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(size * 0.28)),
        child: CustomPaint(painter: _TreePainter()),
      ),
    );
  }
}

class _TreePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.height * 0.62 / 10; // the tree is 10 units tall and fills 62% of the square
    final cx = size.width / 2;
    final top = (size.height - unit * 10) / 2 + size.height * 0.01;
    final tiers = <(double, double, double)>[(0.0, 3.9, 2.35), (2.3, 6.3, 3.35), (4.4, 8.4, 4.4)]; // top, bottom, half width
    final paint = Paint()..color = ForestMark._tree;
    for (final (from, to, half) in tiers) {
      canvas.drawPath(
        Path()
          ..moveTo(cx, top + from * unit)
          ..lineTo(cx - half * unit, top + to * unit)
          ..lineTo(cx + half * unit, top + to * unit)
          ..close(),
        paint,
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(cx - 0.75 * unit, top + 8.3 * unit, 1.5 * unit, 1.6 * unit),
      Paint()..color = ForestMark._trunk,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
