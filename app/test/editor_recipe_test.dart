// The recipe the editor sends (lib/features/editor/recipe.dart) must match what the server accepts (backend/src/compose/recipe.js).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:forest_app/features/editor/recipe.dart';

void main() {
  group('colours', () {
    test('hexOf and colorOf round-trip #rrggbb', () {
      expect(hexOf(const Color(0xFF16A34A)), '#16a34a');
      expect(hexOf(Colors.white), '#ffffff');
      expect(colorOf('#2d5fa8'), const Color(0xFF2D5FA8));
      expect(hexOf(colorOf('#0f2027')), '#0f2027');
    });
  });

  group('TEXT recipe', () {
    const base = Recipe(mode: EditorMode.text);

    test('is sent the way the server wants it', () {
      final r = base.copyWith(
        durationSec: 10,
        text: const TextSpec(content: '  Exams should be open-book  ', color: Colors.white, size: 72, animation: TextAnimation.typewriter, align: TextAlignment.left),
        background: const Background.gradient(Color(0xFF0F2027), Color(0xFF2C5364), angle: 180),
      );
      expect(r.toJson(), {
        'mode': 'TEXT',
        'durationSec': 10.0,
        'text': {'content': 'Exams should be open-book', 'color': '#ffffff', 'font': 'sans', 'size': 72, 'align': 'left', 'animation': 'typewriter'},
        'background': {'type': 'gradient', 'from': '#0f2027', 'to': '#2c5364', 'angle': 180},
      });
    });

    test('a solid background is sent as solid', () {
      final r = base.copyWith(text: const TextSpec(content: 'x'), background: const Background.solid(Color(0xFF111111)));
      expect((r.toJson()['background'] as Map)['type'], 'solid');
      expect((r.toJson()['background'] as Map)['color'], '#111111');
    });

    test('says what is wrong in plain words', () {
      expect(base.problem(), 'Write something first.');
      expect(base.copyWith(text: const TextSpec(content: '   ')).problem(), 'Write something first.');
      expect(base.copyWith(text: TextSpec(content: 'a' * 281)).problem(), contains('280'));
      expect(base.copyWith(text: const TextSpec(content: 'ok'), durationSec: 2).problem(), contains('3 to 60'));
      expect(base.copyWith(text: const TextSpec(content: 'ok')).problem(), isNull);
    });
  });

  group('PHOTOS recipe', () {
    const base = Recipe(mode: EditorMode.photos);

    test('length counts the fade overlap like the server does', () {
      expect(base.copyWith(photoCount: 4, slideSeconds: 3).lengthSeconds(), 4 * 3 - 3 * 0.5);
      expect(base.copyWith(photoCount: 4, slideSeconds: 3, transition: PhotoTransition.none).lengthSeconds(), 12);
      expect(base.copyWith(photoCount: 1, slideSeconds: 5).lengthSeconds(), 5);
    });

    test('refuses no photos, too many, and more than 60 seconds', () {
      expect(base.problem(), 'Pick at least one photo.');
      expect(base.copyWith(photoCount: 11).problem(), contains('10 photos'));
      expect(base.copyWith(photoCount: 10, slideSeconds: 8, transition: PhotoTransition.none).problem(), contains('60 seconds'));
      expect(base.copyWith(photoCount: 3).problem(), isNull);
    });

    test('is sent with order, seconds and transition', () {
      final r = base.copyWith(photoCount: 3, photoOrder: [2, 0, 1], slideSeconds: 4, transition: PhotoTransition.none);
      expect(r.toJson(), {'mode': 'PHOTOS', 'photoOrder': [2, 0, 1], 'slideSeconds': 4.0, 'transition': 'none'});
    });
  });

  group('VIDEO recipe', () {
    const base = Recipe(mode: EditorMode.video);

    test('no trim means the video itself, up to 60 seconds', () {
      expect(base.lengthSeconds(videoSeconds: 20), 20);
      expect(base.lengthSeconds(videoSeconds: 200), 60);
      expect(base.problem(videoSeconds: 200), isNull, reason: 'the server takes the first 60 seconds of a longer video');
      expect(base.problem(videoSeconds: 20), isNull);
    });

    test('a trim shorter than half a second, or longer than a minute, is refused', () {
      expect(base.copyWith(trim: const Trim(1, 1.2)).problem(videoSeconds: 30), contains('half a second'));
      expect(base.copyWith(trim: const Trim(0, 70)).problem(videoSeconds: 90), contains('60 seconds'));
      expect(base.copyWith(trim: const Trim(10, 40)).problem(videoSeconds: 90), isNull);
    });

    test('sends trim, mute and crop, and leaves out what changes nothing', () {
      expect(base.toJson(), {'mode': 'VIDEO'});
      final r = base.copyWith(trim: const Trim(2, 12.5), muteOriginal: true, crop: const Crop(x: .1, y: 0, w: .8, h: 1));
      expect(r.toJson(), {
        'mode': 'VIDEO',
        'trim': {'startSec': 2.0, 'endSec': 12.5},
        'muteOriginal': true,
        'crop': {'x': .1, 'y': 0.0, 'w': .8, 'h': 1.0},
      });
      expect(base.copyWith(crop: const Crop()).toJson().containsKey('crop'), isFalse, reason: 'a full-picture crop is no crop');
    });

    test('a crop outside the picture is refused', () {
      expect(base.copyWith(crop: const Crop(x: .5, w: .8)).problem(videoSeconds: 10), contains('inside the picture'));
    });
  });

  group('adjust, overlays and music', () {
    test('default colour settings send nothing; changed ones send only what changed', () {
      expect(const Adjust().isDefault, isTrue);
      expect(const Recipe(mode: EditorMode.video).toJson().containsKey('adjust'), isFalse);
      final r = const Recipe(mode: EditorMode.video).copyWith(adjust: const Adjust(contrast: 1.4, blur: 2));
      expect(r.toJson()['adjust'], {'contrast': 1.4, 'blur': 2.0});
    });

    test('an overlay ends inside the video and after it starts', () {
      const o = TextOverlay(text: 'hi', startSec: 9.95, endSec: 50);
      final json = o.toJson(totalSeconds: 10);
      expect(json['startSec'], 9.9, reason: 'pulled back so there is room to show it');
      expect(json['endSec'], 10.0);
      expect(const TextOverlay(text: 'hi').toJson(totalSeconds: 8)['endSec'], 8.0, reason: 'no end = until the end');
      expect(const TextOverlay(text: 'hi', color: Color(0xFFFFCC00), font: EditorFont.mono).toJson(totalSeconds: 8), containsPair('color', '#ffcc00'));
    });

    test('at most 5 overlays, none empty or too long', () {
      var r = const Recipe(mode: EditorMode.text, text: TextSpec(content: 'x'));
      r = r.copyWith(overlays: [for (var i = 0; i < 6; i++) const TextOverlay(text: 'a')]);
      expect(r.problem(), contains('up to 5'));
      expect(r.copyWith(overlays: [const TextOverlay(text: ' ')]).problem(), contains('empty'));
      expect(r.copyWith(overlays: [TextOverlay(text: 'a' * 121)]).problem(), contains('120'));
      expect(r.copyWith(overlays: [const TextOverlay(text: 'fine')]).problem(), isNull);
    });

    test('music settings are sent when there is music, with a volume the server accepts', () {
      final r = const Recipe(mode: EditorMode.text, text: TextSpec(content: 'x')).copyWith(music: const MusicSpec(volume: .35, startSec: 12));
      expect(r.toJson()['music'], {'volume': .35, 'startSec': 12.0});
      expect(r.copyWith(clearMusic: true).toJson().containsKey('music'), isFalse);
    });
  });
}
