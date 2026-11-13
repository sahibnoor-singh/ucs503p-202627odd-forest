import 'dart:math' as math;

import 'recipe.dart' show Crop;

/// The geometry of the crop box, kept apart from the widgets so it can be tested without a screen.
/// Everything is in fractions of the whole picture: 0 is the left / top edge, 1 the right / bottom edge.

/// The smallest a crop may be, across and down (the server refuses less).
const double kMinCrop = 0.1;

class CropRect {
  const CropRect(this.l, this.t, this.r, this.b);

  final double l, t, r, b;

  static const CropRect full = CropRect(0, 0, 1, 1);

  factory CropRect.fromCrop(Crop? c) => c == null ? full : CropRect(c.x, c.y, c.x + c.w, c.y + c.h);

  double get w => r - l;
  double get h => b - t;

  /// Nothing is cut off (give or take the width of a finger).
  bool get isFull => l <= 0.002 && t <= 0.002 && r >= 0.998 && b >= 0.998;

  /// What the recipe stores: null when nothing is cut off.
  Crop? toCrop() => isFull ? null : Crop(x: l, y: t, w: w, h: h);
}

/// Which part of the box a finger took hold of.
enum CropHandle { move, topLeft, topRight, bottomLeft, bottomRight, left, right, top, bottom }

/// The biggest box with the shape [ratio] (width / height as seen on screen) that fits in a picture whose own shape is
/// [sourceAspect], centred.
CropRect fitRatio(double ratio, double sourceAspect) {
  // as seen on screen, a box of w x h (fractions) has the shape (w / h) * sourceAspect
  var w = 1.0;
  var h = sourceAspect / ratio;
  if (h > 1) {
    h = 1;
    w = ratio / sourceAspect;
  }
  return CropRect((1 - w) / 2, (1 - h) / 2, (1 + w) / 2, (1 + h) / 2);
}

double _clamp(double v, double lo, double hi) => math.max(lo, math.min(hi, v));

/// The box after a finger that took hold of [handle] when the box was [start] has moved by ([dx], [dy]) (fractions of the
/// picture). With [ratio] (the shape to keep, width / height as seen on screen) the corners resize it in that shape and the
/// edges do nothing; without, any side can move on its own.
CropRect dragBox(CropRect start, CropHandle handle, double dx, double dy, {double? ratio, double sourceAspect = 1}) {
  if (handle == CropHandle.move) {
    final l = _clamp(start.l + dx, 0, 1 - start.w);
    final t = _clamp(start.t + dy, 0, 1 - start.h);
    return CropRect(l, t, l + start.w, t + start.h);
  }

  switch (handle) {
    case CropHandle.left:
      return ratio != null ? start : CropRect(_clamp(start.l + dx, 0, start.r - kMinCrop), start.t, start.r, start.b);
    case CropHandle.right:
      return ratio != null ? start : CropRect(start.l, start.t, _clamp(start.r + dx, start.l + kMinCrop, 1), start.b);
    case CropHandle.top:
      return ratio != null ? start : CropRect(start.l, _clamp(start.t + dy, 0, start.b - kMinCrop), start.r, start.b);
    case CropHandle.bottom:
      return ratio != null ? start : CropRect(start.l, start.t, start.r, _clamp(start.b + dy, start.t + kMinCrop, 1));
    default:
      break;
  }

  // a corner: the opposite corner stays where it is
  final right = handle == CropHandle.topRight || handle == CropHandle.bottomRight;
  final down = handle == CropHandle.bottomLeft || handle == CropHandle.bottomRight;
  final fx = right ? start.l : start.r;
  final fy = down ? start.t : start.b;
  final mx = _clamp((right ? start.r : start.l) + dx, 0, 1);
  final my = _clamp((down ? start.b : start.t) + dy, 0, 1);

  double w;
  double h;
  if (ratio == null) {
    // how far the finger is from the fixed corner, in the direction the box grows (never negative: it cannot flip over)
    w = math.max(right ? mx - fx : fx - mx, kMinCrop);
    h = math.max(down ? my - fy : fy - my, kMinCrop);
    w = math.min(w, right ? 1 - fx : fx);
    h = math.min(h, down ? 1 - fy : fy);
  } else {
    final hPerW = sourceAspect / ratio; // how many heights a width of 1 is worth
    w = math.max(right ? mx - fx : fx - mx, 0);
    w = math.min(w, math.min(right ? 1 - fx : fx, (down ? 1 - fy : fy) / hPerW));
    w = math.max(w, math.max(kMinCrop, kMinCrop / hPerW));
    h = w * hPerW;
  }
  final l = right ? fx : fx - w;
  final t = down ? fy : fy - h;
  return CropRect(l, t, l + w, t + h);
}

/// Which handle a finger at ([x], [y]) (logical pixels from the picture's top left) would take hold of, or null when it is
/// outside the box. [slop] is how close to a corner or an edge counts as on it.
CropHandle? handleAt(CropRect box, double x, double y, double width, double height, {required bool edges, double slop = 30}) {
  final l = box.l * width, r = box.r * width, t = box.t * height, b = box.b * height;
  bool near(double a, double b) => (a - b).abs() <= slop;
  final nearL = near(x, l), nearR = near(x, r), nearT = near(y, t), nearB = near(y, b);
  if (nearL && nearT) return CropHandle.topLeft;
  if (nearR && nearT) return CropHandle.topRight;
  if (nearL && nearB) return CropHandle.bottomLeft;
  if (nearR && nearB) return CropHandle.bottomRight;
  final insideX = x > l - slop && x < r + slop;
  final insideY = y > t - slop && y < b + slop;
  if (edges) {
    final edgeSlop = slop * 0.7;
    bool onEdge(double a, double b) => (a - b).abs() <= edgeSlop;
    if (onEdge(x, l) && insideY) return CropHandle.left;
    if (onEdge(x, r) && insideY) return CropHandle.right;
    if (onEdge(y, t) && insideX) return CropHandle.top;
    if (onEdge(y, b) && insideX) return CropHandle.bottom;
  }
  if (x >= l && x <= r && y >= t && y <= b) return CropHandle.move;
  return null;
}
