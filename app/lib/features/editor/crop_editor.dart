import 'package:flutter/material.dart';

import 'crop_math.dart';
import 'recipe.dart';

/// Shows only the [crop] part of [child], scaled up to fill this widget. [child] is the whole picture; this widget must be given
/// the shape of the cropped part (e.g. by an [AspectRatio]), so the part fills it exactly.
class CropWindow extends StatelessWidget {
  const CropWindow({super.key, required this.crop, required this.child});

  final Crop? crop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = crop;
    if (c == null || c.isFull) return child;
    return LayoutBuilder(
      builder: (context, box) {
        final fullW = box.maxWidth / c.w;
        final fullH = box.maxHeight / c.h;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: fullW,
            maxWidth: fullW,
            minHeight: fullH,
            maxHeight: fullH,
            child: Transform.translate(offset: Offset(-c.x * fullW, -c.y * fullH), child: child),
          ),
        );
      },
    );
  }
}

/// The box drawn over a picture to choose what to keep: drag inside it to move it, drag a corner to resize it (and an edge
/// too, when no [ratio] is held). Everything outside the box is dimmed. Give it the same size as the picture it covers.
class CropEditor extends StatefulWidget {
  const CropEditor({super.key, required this.crop, required this.sourceAspect, required this.ratio, required this.onChanged});

  /// The crop now, null for none.
  final Crop? crop;

  /// Width / height of the whole picture.
  final double sourceAspect;

  /// A shape to keep while resizing (width / height as seen on screen), or null for free. Choosing a new one re-fits the box.
  final double? ratio;
  final ValueChanged<Crop?> onChanged;

  @override
  State<CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<CropEditor> {
  late CropRect _box = CropRect.fromCrop(widget.crop);
  CropHandle? _handle;
  CropRect _start = CropRect.full;
  Offset _from = Offset.zero;

  @override
  void initState() {
    super.initState();
    final ratio = widget.ratio;
    // opened with a shape held but no crop yet (the shape was chosen earlier): start from it
    if (ratio != null && widget.crop == null) _box = fitRatio(ratio, widget.sourceAspect);
  }

  @override
  void didUpdateWidget(CropEditor old) {
    super.didUpdateWidget(old);
    if (_handle != null) return; // a finger is on it: it is the one deciding
    final ratio = widget.ratio;
    if (ratio != null && ratio != old.ratio) {
      _box = fitRatio(ratio, widget.sourceAspect);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onChanged(_box.toCrop());
      });
    } else {
      _box = CropRect.fromCrop(widget.crop); // changed from outside, e.g. Reset
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return Semantics(
          label: 'Crop box. Drag it to move, drag a corner to resize.',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) {
              final p = d.localPosition;
              final handle = handleAt(_box, p.dx, p.dy, size.width, size.height, edges: widget.ratio == null);
              if (handle == null) return;
              _handle = handle;
              _start = _box;
              _from = p;
            },
            onPanUpdate: (d) {
              final handle = _handle;
              if (handle == null) return;
              final dx = (d.localPosition.dx - _from.dx) / size.width;
              final dy = (d.localPosition.dy - _from.dy) / size.height;
              setState(() => _box = dragBox(_start, handle, dx, dy, ratio: widget.ratio, sourceAspect: widget.sourceAspect));
              widget.onChanged(_box.toCrop());
            },
            onPanEnd: (_) => _handle = null,
            onPanCancel: () => _handle = null,
            child: CustomPaint(key: const Key('crop-box'), size: size, painter: _CropPainter(_box, widget.ratio == null)),
          ),
        );
      },
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.box, this.showEdges);

  final CropRect box;
  final bool showEdges;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(box.l * size.width, box.t * size.height, box.r * size.width, box.b * size.height);
    final scrim = Path()
      ..addRect(Offset.zero & size)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(scrim, Paint()..color = const Color(0x99000000));

    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(rect, line);

    final thin = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 1;
    for (var i = 1; i <= 2; i++) {
      canvas.drawLine(Offset(rect.left + rect.width * i / 3, rect.top), Offset(rect.left + rect.width * i / 3, rect.bottom), thin);
      canvas.drawLine(Offset(rect.left, rect.top + rect.height * i / 3), Offset(rect.right, rect.top + rect.height * i / 3), thin);
    }

    // thick corners, so it is clear where to take hold
    final corner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.square;
    final len = (rect.shortestSide / 3).clamp(10.0, 26.0);
    for (final (x, dx) in [(rect.left, 1.0), (rect.right, -1.0)]) {
      for (final (y, dy) in [(rect.top, 1.0), (rect.bottom, -1.0)]) {
        canvas.drawLine(Offset(x, y), Offset(x + dx * len, y), corner);
        canvas.drawLine(Offset(x, y), Offset(x, y + dy * len), corner);
      }
    }
    if (showEdges) {
      final mid = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      final half = (rect.shortestSide / 8).clamp(6.0, 14.0);
      canvas.drawLine(Offset(rect.center.dx - half, rect.top), Offset(rect.center.dx + half, rect.top), mid);
      canvas.drawLine(Offset(rect.center.dx - half, rect.bottom), Offset(rect.center.dx + half, rect.bottom), mid);
      canvas.drawLine(Offset(rect.left, rect.center.dy - half), Offset(rect.left, rect.center.dy + half), mid);
      canvas.drawLine(Offset(rect.right, rect.center.dy - half), Offset(rect.right, rect.center.dy + half), mid);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.box != box || old.showEdges != showEdges;
}

/// Works out the shape of a picture from its file, then builds [builder] with it (null until it is known).
class ImageShape extends StatefulWidget {
  const ImageShape({super.key, required this.image, required this.builder});

  final ImageProvider image;
  final Widget Function(BuildContext context, Size? size) builder;

  @override
  State<ImageShape> createState() => _ImageShapeState();
}

class _ImageShapeState extends State<ImageShape> {
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener(
    (info, _) {
      final size = Size(info.image.width.toDouble(), info.image.height.toDouble());
      if (mounted && size != _size) setState(() => _size = size);
    },
    onError: (_, _) {},
  );
  Size? _size;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(ImageShape old) {
    super.didUpdateWidget(old);
    if (old.image != widget.image) {
      _size = null;
      _resolve();
    }
  }

  void _resolve() {
    final next = widget.image.resolve(createLocalImageConfiguration(context));
    if (next.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = next..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _size);
}
