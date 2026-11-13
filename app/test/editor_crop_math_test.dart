// The crop box geometry: moving, resizing, keeping a shape, and never leaving the picture or getting smaller than the server allows.

import 'package:flutter_test/flutter_test.dart';

import 'package:forest_app/features/editor/crop_math.dart';
import 'package:forest_app/features/editor/recipe.dart';

void main() {
  group('CropRect', () {
    test('no crop is the whole picture, and the whole picture is stored as no crop', () {
      expect(CropRect.fromCrop(null).isFull, isTrue);
      expect(CropRect.full.toCrop(), isNull);
      expect(const CropRect(0.001, 0, 1, 0.999).toCrop(), isNull, reason: 'a hair off is not a crop');
      final c = const CropRect(.1, .2, .6, .9).toCrop()!;
      expect([c.x, c.y, c.w, c.h].map((v) => double.parse(v.toStringAsFixed(3))), [.1, .2, .5, .7]);
      final back = CropRect.fromCrop(const Crop(x: .1, y: .2, w: .5, h: .7));
      expect(back.l, .1);
      expect(back.t, .2);
      expect(back.r, closeTo(.6, 1e-9));
      expect(back.b, closeTo(.9, 1e-9));
    });
  });

  group('fitRatio', () {
    test('a square in a portrait picture is as wide as the picture and centred', () {
      final r = fitRatio(1, 9 / 16);
      expect(r.w, closeTo(1, 1e-9));
      expect(r.h * (16 / 9) * (9 / 16), closeTo(r.h, 1e-9));
      expect(r.w / r.h * (9 / 16), closeTo(1, 1e-9), reason: 'it looks square on screen');
      expect(r.t, closeTo((1 - r.h) / 2, 1e-9));
    });

    test('a wide shape in a wide picture is as tall as the picture', () {
      final r = fitRatio(1, 16 / 9 * 2); // very wide picture, square wanted
      expect(r.h, closeTo(1, 1e-9));
      expect(r.w / r.h * (16 / 9 * 2), closeTo(1, 1e-9));
    });

    test('the shape of the picture itself gives the whole picture', () {
      expect(fitRatio(9 / 16, 9 / 16).isFull, isTrue);
    });
  });

  group('dragBox', () {
    const box = CropRect(.2, .2, .6, .6);

    test('moving keeps the size and stops at the edges', () {
      final r = dragBox(box, CropHandle.move, .1, -.05);
      expect([r.l, r.t].map((v) => double.parse(v.toStringAsFixed(3))), [.3, .15]);
      expect(r.w, closeTo(.4, 1e-9));
      final out = dragBox(box, CropHandle.move, 5, 5);
      expect([out.r, out.b], [1.0, 1.0]);
      final back = dragBox(box, CropHandle.move, -5, -5);
      expect([back.l, back.t], [0.0, 0.0]);
    });

    test('a free corner follows the finger and leaves the opposite corner alone', () {
      final r = dragBox(box, CropHandle.bottomRight, .2, .1);
      expect([r.l, r.t], [.2, .2]);
      expect(r.r, closeTo(.8, 1e-9));
      expect(r.b, closeTo(.7, 1e-9));
      final tl = dragBox(box, CropHandle.topLeft, -.1, -.1);
      expect([tl.l, tl.t].map((v) => double.parse(v.toStringAsFixed(3))), [.1, .1]);
      expect([tl.r, tl.b], [.6, .6]);
    });

    test('a corner cannot pass the picture edge or squash the box under the minimum', () {
      final big = dragBox(box, CropHandle.bottomRight, 5, 5);
      expect([big.r, big.b], [1.0, 1.0]);
      final tiny = dragBox(box, CropHandle.bottomRight, -5, -5);
      expect(tiny.w, closeTo(kMinCrop, 1e-9));
      expect(tiny.h, closeTo(kMinCrop, 1e-9));
      expect([tiny.l, tiny.t], [.2, .2]);
    });

    test('free edges move one side at a time', () {
      expect(dragBox(box, CropHandle.left, -.1, 9).l, closeTo(.1, 1e-9));
      expect(dragBox(box, CropHandle.right, .1, 9).r, closeTo(.7, 1e-9));
      expect(dragBox(box, CropHandle.top, 9, -.1).t, closeTo(.1, 1e-9));
      expect(dragBox(box, CropHandle.bottom, 9, .1).b, closeTo(.7, 1e-9));
      expect(dragBox(box, CropHandle.right, -5, 0).w, closeTo(kMinCrop, 1e-9));
    });

    test('with a shape to keep, edges do nothing and corners keep the shape', () {
      const sourceAspect = 9 / 16;
      final start = fitRatio(1, sourceAspect); // a square
      expect(dragBox(start, CropHandle.left, -.1, 0, ratio: 1, sourceAspect: sourceAspect), start);
      final small = dragBox(start, CropHandle.bottomRight, -.4, -.4, ratio: 1, sourceAspect: sourceAspect);
      expect(small.w / small.h * sourceAspect, closeTo(1, 1e-6), reason: 'still square on screen');
      expect(small.w, lessThan(start.w));
      expect([small.l, small.t].map((v) => double.parse(v.toStringAsFixed(6))), [double.parse(start.l.toStringAsFixed(6)), double.parse(start.t.toStringAsFixed(6))], reason: 'the top left corner stayed');
    });

    test('a locked shape never leaves the picture, whichever way it is pulled', () {
      for (final ratio in [1.0, 4 / 5, 9 / 16, 16 / 9]) {
        for (final aspect in [9 / 16, 16 / 9, 1.0]) {
          var b = fitRatio(ratio, aspect);
          for (final handle in [CropHandle.topLeft, CropHandle.topRight, CropHandle.bottomLeft, CropHandle.bottomRight]) {
            for (final d in [-3.0, -.2, .2, 3.0]) {
              final r = dragBox(b, handle, d, d * .7, ratio: ratio, sourceAspect: aspect);
              expect(r.l, greaterThanOrEqualTo(-1e-9), reason: '$ratio $aspect $handle $d');
              expect(r.t, greaterThanOrEqualTo(-1e-9), reason: '$ratio $aspect $handle $d');
              expect(r.r, lessThanOrEqualTo(1 + 1e-9), reason: '$ratio $aspect $handle $d');
              expect(r.b, lessThanOrEqualTo(1 + 1e-9), reason: '$ratio $aspect $handle $d');
              expect(r.w, greaterThanOrEqualTo(kMinCrop - 1e-9), reason: '$ratio $aspect $handle $d');
              expect(r.h, greaterThanOrEqualTo(kMinCrop - 1e-9), reason: '$ratio $aspect $handle $d');
              expect(r.w / r.h * aspect, closeTo(ratio, 1e-6), reason: '$ratio $aspect $handle $d');
              b = fitRatio(ratio, aspect);
            }
          }
        }
      }
    });
  });

  group('handleAt', () {
    const box = CropRect(.2, .2, .8, .8);
    // a picture 300 x 600 pixels: the box is x 60..240, y 120..480
    CropHandle? at(double x, double y, {bool edges = true}) => handleAt(box, x, y, 300, 600, edges: edges);

    test('corners, then edges, then the inside', () {
      expect(at(62, 125), CropHandle.topLeft);
      expect(at(238, 478), CropHandle.bottomRight);
      expect(at(60, 300), CropHandle.left);
      expect(at(150, 480), CropHandle.bottom);
      expect(at(150, 300), CropHandle.move);
    });

    test('with a locked shape the edges are not handles: they move the box instead', () {
      expect(at(60, 300, edges: false), CropHandle.move);
    });

    test('outside the box takes hold of nothing', () {
      expect(at(5, 5), isNull);
      expect(at(290, 590), isNull);
    });
  });
}
