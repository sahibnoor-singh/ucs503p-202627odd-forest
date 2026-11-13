import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The "recipe" the editor sends with its files to `POST /api/posts/compose` (docs/api.md → "Editor posts"). The server renders
/// it into one MP4. This file is the app's copy of that contract: the same names, ranges and limits, so a mistake is caught on
/// the phone with a friendly message instead of as a 400 from the server.

enum EditorMode {
  video('VIDEO'),
  text('TEXT'),
  photos('PHOTOS');

  const EditorMode(this.wire);
  final String wire;
}

/// The limits the server enforces (src/compose/recipe.js, upload.js).
class EditorLimits {
  static const maxSeconds = 60;
  static const minVideoSeconds = 0.5;
  static const maxPhotos = 10;
  static const maxOverlays = 5;
  static const maxTextChars = 280;
  static const maxOverlayChars = 120;
  static const maxTitleChars = 120;
  static const maxCaptionChars = 280;
  static const maxVideoBytes = 50 * 1024 * 1024;
  static const maxMusicBytes = 15 * 1024 * 1024;
  static const maxPhotoBytes = 10 * 1024 * 1024;
  static const minTextSeconds = 3.0;
  static const defaultTextSeconds = 8.0;
}

/// `#rrggbb`, as the server wants colours.
String hexOf(Color c) {
  String two(double v) => (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${two(c.r)}${two(c.g)}${two(c.b)}';
}

Color colorOf(String hex) => Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));

double _round(double v, [int places = 3]) {
  final f = _pow10(places);
  return (v * f).round() / f;
}

double _pow10(int n) => n == 0 ? 1 : 10 * _pow10(n - 1);

/// Colour corrections applied to the whole picture. The defaults change nothing.
class Adjust {
  const Adjust({this.brightness = 0, this.contrast = 1, this.saturation = 1, this.hue = 0, this.blur = 0});

  final double brightness; // -0.5 .. 0.5
  final double contrast; // 0.5 .. 2
  final double saturation; // 0 .. 3
  final double hue; // -180 .. 180
  final double blur; // 0 .. 10

  bool get isDefault => brightness == 0 && contrast == 1 && saturation == 1 && hue == 0 && blur == 0;

  Adjust copyWith({double? brightness, double? contrast, double? saturation, double? hue, double? blur}) => Adjust(
        brightness: brightness ?? this.brightness,
        contrast: contrast ?? this.contrast,
        saturation: saturation ?? this.saturation,
        hue: hue ?? this.hue,
        blur: blur ?? this.blur,
      );

  Map<String, Object?> toJson() => {
        if (brightness != 0) 'brightness': _round(brightness),
        if (contrast != 1) 'contrast': _round(contrast),
        if (saturation != 1) 'saturation': _round(saturation),
        if (hue != 0) 'hue': _round(hue, 1),
        if (blur != 0) 'blur': _round(blur, 1),
      };
}

/// A piece of text drawn over the picture for part of the time.
class TextOverlay {
  const TextOverlay({
    required this.text,
    this.x = .5,
    this.y = .5,
    this.size = 56,
    this.color = Colors.white,
    this.font = EditorFont.sans,
    this.startSec = 0,
    this.endSec,
  });

  final String text;
  final double x; // 0..1, centre of the text as a fraction of the picture
  final double y;
  final double size; // 20..120
  final Color color;
  final EditorFont font;
  final double startSec;
  final double? endSec; // null = until the end

  TextOverlay copyWith({String? text, double? x, double? y, double? size, Color? color, EditorFont? font, double? startSec, double? endSec, bool clearEnd = false}) =>
      TextOverlay(
        text: text ?? this.text,
        x: x ?? this.x,
        y: y ?? this.y,
        size: size ?? this.size,
        color: color ?? this.color,
        font: font ?? this.font,
        startSec: startSec ?? this.startSec,
        endSec: clearEnd ? null : (endSec ?? this.endSec),
      );

  Map<String, Object?> toJson({required double totalSeconds}) {
    // inside the finished video, and always ending after it starts (the server rejects anything else)
    final start = startSec.clamp(0.0, math.max(0.0, totalSeconds - 0.1)).toDouble();
    final end = (endSec ?? totalSeconds).clamp(start + 0.1, math.max(start + 0.1, totalSeconds)).toDouble();
    return {
      'text': text,
      'x': _round(x),
      'y': _round(y),
      'size': size.round(),
      'color': hexOf(color),
      'font': font.wire,
      'startSec': _round(start, 2),
      'endSec': _round(end, 2),
    };
  }
}

enum EditorFont {
  sans('sans', 'Sans'),
  serif('serif', 'Serif'),
  mono('mono', 'Mono');

  const EditorFont(this.wire, this.label);
  final String wire;
  final String label;

  /// The nearest font on the phone, for the live preview (the server draws its own).
  String? get family => switch (this) { EditorFont.sans => null, EditorFont.serif => 'serif', EditorFont.mono => 'monospace' };
}

enum TextAlignment {
  left('left', TextAlign.left),
  center('center', TextAlign.center),
  right('right', TextAlign.right);

  const TextAlignment(this.wire, this.align);
  final String wire;
  final TextAlign align;
}

enum TextAnimation {
  none('none', 'Still'),
  fade('fade', 'Fade in'),
  slideUp('slideUp', 'Slide up'),
  typewriter('typewriter', 'Typewriter'),
  wordByWord('wordByWord', 'Word by word');

  const TextAnimation(this.wire, this.label);
  final String wire;
  final String label;
}

/// The big text of a TEXT post.
class TextSpec {
  const TextSpec({
    this.content = '',
    this.color = Colors.white,
    this.font = EditorFont.sans,
    this.size = 64,
    this.align = TextAlignment.center,
    this.animation = TextAnimation.fade,
  });

  final String content;
  final Color color;
  final EditorFont font;
  final double size; // 32..120
  final TextAlignment align;
  final TextAnimation animation;

  TextSpec copyWith({String? content, Color? color, EditorFont? font, double? size, TextAlignment? align, TextAnimation? animation}) => TextSpec(
        content: content ?? this.content,
        color: color ?? this.color,
        font: font ?? this.font,
        size: size ?? this.size,
        align: align ?? this.align,
        animation: animation ?? this.animation,
      );

  Map<String, Object?> toJson() => {
        'content': content.trim(),
        'color': hexOf(color),
        'font': font.wire,
        'size': size.round(),
        'align': align.wire,
        'animation': animation.wire,
      };
}

/// Solid colour or a two-colour gradient behind a TEXT post.
class Background {
  const Background.solid(this.from)
      : to = null,
        angle = 0;
  const Background.gradient(this.from, Color this.to, {this.angle = 160});

  final Color from;
  final Color? to; // null = solid
  final double angle; // 0 = `from` at the top, 90 = `from` at the left

  bool get isGradient => to != null;

  Map<String, Object?> toJson() => isGradient
      ? {'type': 'gradient', 'from': hexOf(from), 'to': hexOf(to!), 'angle': angle.round() % 360}
      : {'type': 'solid', 'color': hexOf(from)};
}

class Trim {
  const Trim(this.startSec, this.endSec);
  final double startSec;
  final double endSec;
  double get length => endSec - startSec;
  Map<String, Object?> toJson() => {'startSec': _round(startSec, 2), 'endSec': _round(endSec, 2)};
}

class Crop {
  const Crop({this.x = 0, this.y = 0, this.w = 1, this.h = 1});
  final double x, y, w, h; // fractions of the picture
  bool get isFull => x == 0 && y == 0 && w == 1 && h == 1;
  Map<String, Object?> toJson() => {'x': _round(x), 'y': _round(y), 'w': _round(w), 'h': _round(h)};
}

class MusicSpec {
  const MusicSpec({this.volume = .8, this.startSec = 0});
  final double volume; // 0..1
  final double startSec;
  MusicSpec copyWith({double? volume, double? startSec}) => MusicSpec(volume: volume ?? this.volume, startSec: startSec ?? this.startSec);
  Map<String, Object?> toJson() => {'volume': _round(volume, 2), 'startSec': _round(startSec, 2)};
}

enum PhotoTransition {
  none('none', 'Cut'),
  fade('fade', 'Fade');

  const PhotoTransition(this.wire, this.label);
  final String wire;
  final String label;
}

/// What to render. Build one per post; [toJson] is the `recipe` form field.
class Recipe {
  const Recipe({
    required this.mode,
    this.adjust = const Adjust(),
    this.overlays = const [],
    this.music,
    // VIDEO
    this.trim,
    this.muteOriginal = false,
    this.crop,
    this.coverSec,
    // TEXT
    this.durationSec = EditorLimits.defaultTextSeconds,
    this.text = const TextSpec(),
    this.background = const Background.solid(Color(0xFF16201C)),
    // PHOTOS
    this.photoCount = 0,
    this.photoOrder,
    this.slideSeconds = 3,
    this.transition = PhotoTransition.fade,
  });

  final EditorMode mode;
  final Adjust adjust;
  final List<TextOverlay> overlays;
  final MusicSpec? music;

  final Trim? trim;
  final bool muteOriginal;
  final Crop? crop;

  /// The moment of the finished video (seconds into the kept part) whose picture is shown before it plays. Null: the server
  /// picks (the first picture of a video).
  final double? coverSec;

  final double durationSec;
  final TextSpec text;
  final Background background;

  /// How many photos are being uploaded (PHOTOS). Not sent: the server counts the files.
  final int photoCount;
  final List<int>? photoOrder;
  final double slideSeconds;
  final PhotoTransition transition;

  /// How long the finished video is, as far as the editor can tell.
  double lengthSeconds({double? videoSeconds}) {
    switch (mode) {
      case EditorMode.video:
        final t = trim;
        if (t != null) return t.length;
        return (videoSeconds ?? EditorLimits.maxSeconds.toDouble()).clamp(0, EditorLimits.maxSeconds.toDouble());
      case EditorMode.text:
        return durationSec;
      case EditorMode.photos:
        final n = photoOrder?.length ?? photoCount;
        // each photo is shown for slideSeconds; a fade overlaps neighbours by half a second
        final overlap = transition == PhotoTransition.fade && n > 1 ? (n - 1) * 0.5 : 0;
        return n * slideSeconds - overlap;
    }
  }

  Recipe copyWith({
    Adjust? adjust,
    List<TextOverlay>? overlays,
    MusicSpec? music,
    bool clearMusic = false,
    Trim? trim,
    bool clearTrim = false,
    bool? muteOriginal,
    Crop? crop,
    bool clearCrop = false,
    double? coverSec,
    bool clearCover = false,
    double? durationSec,
    TextSpec? text,
    Background? background,
    int? photoCount,
    List<int>? photoOrder,
    double? slideSeconds,
    PhotoTransition? transition,
  }) =>
      Recipe(
        mode: mode,
        adjust: adjust ?? this.adjust,
        overlays: overlays ?? this.overlays,
        music: clearMusic ? null : (music ?? this.music),
        trim: clearTrim ? null : (trim ?? this.trim),
        muteOriginal: muteOriginal ?? this.muteOriginal,
        crop: clearCrop ? null : (crop ?? this.crop),
        coverSec: clearCover ? null : (coverSec ?? this.coverSec),
        durationSec: durationSec ?? this.durationSec,
        text: text ?? this.text,
        background: background ?? this.background,
        photoCount: photoCount ?? this.photoCount,
        photoOrder: photoOrder ?? this.photoOrder,
        slideSeconds: slideSeconds ?? this.slideSeconds,
        transition: transition ?? this.transition,
      );

  /// The first thing wrong with this recipe, in words for the person, or null when it is fine to send.
  /// [videoSeconds] is the length of the picked video, when known.
  String? problem({double? videoSeconds}) {
    final total = lengthSeconds(videoSeconds: videoSeconds);
    switch (mode) {
      case EditorMode.text:
        if (text.content.trim().isEmpty) return 'Write something first.';
        if (text.content.trim().length > EditorLimits.maxTextChars) return 'Text can be at most ${EditorLimits.maxTextChars} characters.';
        if (durationSec < EditorLimits.minTextSeconds || durationSec > EditorLimits.maxSeconds) {
          return 'A text post lasts ${EditorLimits.minTextSeconds.round()} to ${EditorLimits.maxSeconds} seconds.';
        }
      case EditorMode.photos:
        if (photoCount < 1) return 'Pick at least one photo.';
        if (photoCount > EditorLimits.maxPhotos) return 'You can use up to ${EditorLimits.maxPhotos} photos.';
        if (total > EditorLimits.maxSeconds) {
          return 'That is ${total.toStringAsFixed(0)} seconds. Show each photo for less time, or use fewer photos (60 seconds at most).';
        }
      case EditorMode.video:
        final t = trim;
        if (t != null && t.length < EditorLimits.minVideoSeconds) return 'Keep at least half a second of the video.';
        if (total > EditorLimits.maxSeconds) return 'Videos can be 60 seconds at most. Trim it shorter.';
        final c = crop;
        if (c != null && (c.w < .1 || c.h < .1 || c.x + c.w > 1.0001 || c.y + c.h > 1.0001)) return 'The crop has to stay inside the picture.';
    }
    if (overlays.length > EditorLimits.maxOverlays) return 'You can add up to ${EditorLimits.maxOverlays} pieces of text.';
    for (final o in overlays) {
      if (o.text.trim().isEmpty) return 'A piece of text on the picture is empty.';
      if (o.text.length > EditorLimits.maxOverlayChars) return 'Text on the picture can be at most ${EditorLimits.maxOverlayChars} characters.';
    }
    return null;
  }

  /// The `recipe` form field.
  Map<String, Object?> toJson({double? videoSeconds}) {
    final total = lengthSeconds(videoSeconds: videoSeconds);
    return {
      'mode': mode.wire,
      if (!adjust.isDefault) 'adjust': adjust.toJson(),
      if (overlays.isNotEmpty) 'overlays': [for (final o in overlays) o.toJson(totalSeconds: total)],
      if (music != null) 'music': music!.toJson(),
      if (mode == EditorMode.video) ...{
        if (trim != null) 'trim': trim!.toJson(),
        if (muteOriginal) 'muteOriginal': true,
        if (crop != null && !crop!.isFull) 'crop': crop!.toJson(),
        if (coverSec != null) 'coverSec': _round(coverSec!.clamp(0.0, total).toDouble(), 2),
      },
      if (mode == EditorMode.text) ...{
        'durationSec': _round(durationSec, 1),
        'text': text.toJson(),
        'background': background.toJson(),
      },
      if (mode == EditorMode.photos) ...{
        if (photoOrder != null) 'photoOrder': photoOrder,
        'slideSeconds': _round(slideSeconds, 1),
        'transition': transition.wire,
        if (crop != null && !crop!.isFull) 'crop': crop!.toJson(),
      },
    };
  }
}
