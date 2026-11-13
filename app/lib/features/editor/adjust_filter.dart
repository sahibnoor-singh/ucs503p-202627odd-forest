import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'recipe.dart';

/// The picture's colour look as it will be rendered by the server (ffmpeg `eq`, `hue` and `boxblur`). Only the picture is
/// changed: text laid over it is drawn afterwards by the server, so [AdjustedPicture] is put around the picture alone.

/// A 5x5 colour matrix (row-major) for [Adjust], in the order the server applies things: saturation, then contrast and
/// brightness, then hue. Returned as the 20 numbers Flutter's [ColorFilter.matrix] wants (offsets in 0-255).
List<double> adjustMatrix(Adjust a) {
  // 5x5 identity
  List<List<double>> id() => [for (var i = 0; i < 5; i++) [for (var j = 0; j < 5; j++) i == j ? 1.0 : 0.0]];
  List<List<double>> mul(List<List<double>> x, List<List<double>> y) => [
        for (var i = 0; i < 5; i++)
          [
            for (var j = 0; j < 5; j++) [for (var k = 0; k < 5; k++) x[i][k] * y[k][j]].reduce((p, q) => p + q),
          ],
      ];

  // saturation (BT.709 luma)
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final s = a.saturation;
  final sat = id()
    ..[0] = [lr + (1 - lr) * s, lg * (1 - s), lb * (1 - s), 0, 0]
    ..[1] = [lr * (1 - s), lg + (1 - lg) * s, lb * (1 - s), 0, 0]
    ..[2] = [lr * (1 - s), lg * (1 - s), lb + (1 - lb) * s, 0, 0];

  // contrast around mid-grey, then brightness (both on 0..1 values, offset scaled to 0..255 at the end)
  final c = a.contrast;
  final cb = id()
    ..[0] = [c, 0, 0, 0, 0.5 * (1 - c) + a.brightness]
    ..[1] = [0, c, 0, 0, 0.5 * (1 - c) + a.brightness]
    ..[2] = [0, 0, c, 0, 0.5 * (1 - c) + a.brightness];

  // hue rotation around the grey axis
  final h = a.hue * math.pi / 180;
  final cosH = math.cos(h), sinH = math.sin(h);
  final hue = id()
    ..[0] = [lr + cosH * (1 - lr) + sinH * -lr, lg + cosH * -lg + sinH * -lg, lb + cosH * -lb + sinH * (1 - lb), 0, 0]
    ..[1] = [lr + cosH * -lr + sinH * 0.143, lg + cosH * (1 - lg) + sinH * 0.140, lb + cosH * -lb + sinH * -0.283, 0, 0]
    ..[2] = [lr + cosH * -lr + sinH * -(1 - lr), lg + cosH * -lg + sinH * lg, lb + cosH * (1 - lb) + sinH * lb, 0, 0];

  final m = mul(hue, mul(cb, sat));
  return [
    for (var i = 0; i < 4; i++) ...[m[i][0], m[i][1], m[i][2], m[i][3], m[i][4] * (i < 3 ? 255 : 1)],
  ];
}

/// Puts [child] (the picture, not the text) through the colour look in [adjust]. Does nothing when [adjust] changes nothing.
/// [pictureWidth] is the width of the picture on screen, to scale the blur (the server blurs a 720-pixel-wide picture).
class AdjustedPicture extends StatelessWidget {
  const AdjustedPicture({super.key, required this.adjust, required this.child, required this.pictureWidth});

  final Adjust adjust;
  final Widget child;
  final double pictureWidth;

  @override
  Widget build(BuildContext context) {
    if (adjust.isDefault) return child;
    Widget out = child;
    if (adjust.brightness != 0 || adjust.contrast != 1 || adjust.saturation != 1 || adjust.hue != 0) {
      out = ColorFiltered(colorFilter: ColorFilter.matrix(adjustMatrix(adjust)), child: out);
    }
    if (adjust.blur > 0) {
      final sigma = adjust.blur * 0.6 * pictureWidth / 720;
      out = ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp), child: out);
    }
    return out;
  }
}

/// Ready-made looks, as values of [Adjust].
class LookPreset {
  const LookPreset(this.name, this.adjust);
  final String name;
  final Adjust adjust;

  static const all = <LookPreset>[
    LookPreset('Original', Adjust()),
    LookPreset('Vivid', Adjust(saturation: 1.5, contrast: 1.15)),
    LookPreset('Warm', Adjust(hue: -10, saturation: 1.1, brightness: 0.03)),
    LookPreset('Cool', Adjust(hue: 12, saturation: 0.95)),
    LookPreset('Mono', Adjust(saturation: 0)),
    LookPreset('Fade', Adjust(contrast: 0.8, brightness: 0.06, saturation: 0.85)),
    LookPreset('Drama', Adjust(contrast: 1.4, saturation: 0.9, brightness: -0.05)),
  ];

  bool matches(Adjust a) =>
      (a.brightness - adjust.brightness).abs() < .001 &&
      (a.contrast - adjust.contrast).abs() < .001 &&
      (a.saturation - adjust.saturation).abs() < .001 &&
      (a.hue - adjust.hue).abs() < .1 &&
      (a.blur - adjust.blur).abs() < .01;
}
