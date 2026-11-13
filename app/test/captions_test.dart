// Subtitles: reading the server's lines, picking the line for a video position, the on/off setting, and the overlay.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'package:forest_app/models/caption_cue.dart';
import 'package:forest_app/models/video.dart';
import 'package:forest_app/services/api_client.dart';
import 'package:forest_app/services/caption_service.dart';
import 'package:forest_app/theme/forest_theme.dart';
import 'package:forest_app/ui/caption_overlay.dart';

Duration ms(int v) => Duration(milliseconds: v);

void main() {
  group('CaptionCue', () {
    test('reads good lines (seconds), sorts them and skips unusable ones', () {
      final cues = CaptionCue.listFrom([
        {'start': 2, 'end': 4.5, 'text': ' second '},
        {'start': 0, 'end': 1.25, 'text': 'first'},
        {'start': 'x', 'end': 3, 'text': 'bad start'},
        {'start': 5, 'end': 5, 'text': 'empty span'},
        {'start': 6, 'end': 7, 'text': '   '},
        'not a map',
        null,
      ]);
      expect(cues.map((c) => c.text), ['first', 'second']);
      expect(cues[0].start, Duration.zero);
      expect(cues[0].end, ms(1250));
      expect(cues[1].start, ms(2000));
      expect(CaptionCue.listFrom(null), isEmpty);
      expect(CaptionCue.listFrom('nope'), isEmpty);
    });

    test('at() finds the line for a position and is empty in the gaps', () {
      final cues = CaptionCue.listFrom([
        {'start': 0, 'end': 2, 'text': 'a'},
        {'start': 3, 'end': 5, 'text': 'b'},
        {'start': 5, 'end': 6, 'text': 'c'},
      ]);
      expect(CaptionCue.at(cues, ms(0))!.text, 'a');
      expect(CaptionCue.at(cues, ms(1999))!.text, 'a');
      expect(CaptionCue.at(cues, ms(2000)), isNull);
      expect(CaptionCue.at(cues, ms(2500)), isNull);
      expect(CaptionCue.at(cues, ms(3000))!.text, 'b');
      expect(CaptionCue.at(cues, ms(5000))!.text, 'c');
      expect(CaptionCue.at(cues, ms(6000)), isNull);
      expect(CaptionCue.at(const [], ms(10)), isNull);
    });

    test('a Video from the feed carries the captions that come inside its analysis', () {
      final v = Video.fromJson({
        'id': 'v1',
        'filename': 'a.mp4',
        'transcript': {
          'overallSummary': 's',
          'captions': [
            {'start': 0, 'end': 1, 'text': 'hello'}
          ],
        },
      });
      expect(v.captions.single.text, 'hello');
      expect(Video.fromJson({'id': 'v2', 'filename': 'b.mp4', 'transcript': 'plain text'}).captions, isEmpty);
      expect(v.copyWith(title: 'x').captions.single.text, 'hello');
    });
  });

  group('CaptionService', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    ApiClient apiWith(Future<http.Response> Function(http.Request) handler, List<String> log) => ApiClient(
          baseUrl: 'http://test.invalid',
          devUser: '',
          client: MockClient((req) {
            log.add('${req.method} ${req.url.path}');
            return handler(req);
          }),
        );

    test("fetches a post's lines once per language and keeps them", () async {
      final log = <String>[];
      final service = CaptionService(
        apiWith((req) async => http.Response('{"language":"hi","captions":[{"start":0,"end":2,"text":"hi"}]}', 200), log),
        restore: false,
      );
      final a = await service.trackFor('p1');
      final b = await service.trackFor('p1');
      expect(a!.cues.single.text, 'hi');
      expect(b!.cues.single.text, 'hi');
      expect(service.spokenLanguage('p1'), 'hi');
      expect(log, ['GET /api/posts/p1/captions']);
      await service.trackFor('p1', language: 'pa');
      await service.trackFor('p1', language: 'pa');
      expect(log.length, 2, reason: 'a second language is a second request, kept after that');
    });

    test('asks the server for the chosen language', () async {
      final asked = <String?>[];
      final service = CaptionService(
        apiWith((req) async {
          asked.add(req.url.queryParameters['lang']);
          return http.Response('{"captions":[]}', 200);
        }, []),
        restore: false,
      );
      await service.trackFor('p1'); // English is the default
      await service.select('original');
      await service.trackFor('p1');
      await service.select('hi');
      await service.trackFor('p1');
      expect(asked, ['en', 'original', 'hi']);
    });

    test('a failed request gives null and is tried again next time', () async {
      final log = <String>[];
      var fail = true;
      final service = CaptionService(
        apiWith((_) async => fail ? http.Response('{"error":"x"}', 500) : http.Response('{"captions":[{"start":0,"end":1,"text":"ok"}]}', 200), log),
        restore: false,
      );
      expect(await service.trackFor('p1'), isNull);
      fail = false;
      expect((await service.trackFor('p1'))!.cues.single.text, 'ok');
      expect(log.length, 2);
    });

    test('is on in English by default; off, on and the language are remembered', () async {
      final api = apiWith((_) async => http.Response('{}', 200), []);
      final service = CaptionService(api, restore: false);
      expect(service.enabled, isTrue);
      expect(service.language, 'en');
      var notified = 0;
      service.addListener(() => notified++);
      await service.select(null);
      expect(service.enabled, isFalse);
      expect(notified, 1);
      expect((await SharedPreferences.getInstance()).getBool('forest.captions.on'), isFalse);

      final off = CaptionService(api); // a new launch
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(off.enabled, isFalse);

      await service.select('pa');
      expect(service.enabled, isTrue);
      expect(service.language, 'pa');
      final back = CaptionService(api);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(back.enabled, isTrue);
      expect(back.language, 'pa');
    });
  });

  group('overlay', () {
    testWidgets('shows the line for the current position and hides it in gaps', (tester) async {
      final controller = VideoPlayerController.networkUrl(Uri.parse('http://test.invalid/a.mp4'));
      addTearDown(controller.dispose);
      final cues = CaptionCue.listFrom([
        {'start': 0, 'end': 2, 'text': 'namaste dosto'},
        {'start': 3, 'end': 5, 'text': 'second line'},
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Stack(children: [CaptionOverlay(controller: controller, cues: cues)]),
      ));
      expect(find.text('namaste dosto'), findsOneWidget);

      controller.value = controller.value.copyWith(position: ms(2500));
      await tester.pump();
      expect(find.text('namaste dosto'), findsNothing);
      expect(find.text('second line'), findsNothing);

      controller.value = controller.value.copyWith(position: ms(3200));
      await tester.pump();
      expect(find.text('second line'), findsOneWidget);
    });

    testWidgets('the CC button reports taps and its state to screen readers', (tester) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Center(child: CaptionButton(enabled: true, onTap: () => taps++)),
      ));
      expect(find.text('CC'), findsOneWidget);
      expect(find.bySemanticsLabel('Turn subtitles off'), findsOneWidget);
      await tester.tap(find.text('CC'));
      expect(taps, 1);
      semantics.dispose();
    });
  });

  group('languages', () {
    test('names and labels', () {
      expect(captionLanguageName('hi'), 'Hindi');
      expect(captionLanguageName('ur'), 'Urdu');
      expect(captionLanguageName('zz'), 'ZZ');
      expect(captionLanguageName(null), '');
      expect(kCaptionLanguages.firstWhere((l) => l.code == 'hi').label, 'हिन्दी (Hindi)');
      expect(kCaptionLanguages.first.label, 'English');
    });

    test('a track reads the language the server says is spoken', () {
      final t = CaptionTrack.fromJson({
        'language': 'pa',
        'captions': [
          {'start': 0, 'end': 1, 'text': 'sat sri akal'}
        ]
      });
      expect(t.language, 'pa');
      expect(t.cues.single.text, 'sat sri akal');
      expect(CaptionTrack.fromJson('nope').cues, isEmpty);
    });
  });

  testWidgets('the picker lists Off, the spoken language, English and the others, and the choice sticks', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = CaptionService(
      ApiClient(
        baseUrl: 'http://test.invalid',
        devUser: '',
        client: MockClient((_) async => http.Response('{"language":"hi","captions":[{"start":0,"end":1,"text":"x"}]}', 200)),
      ),
      restore: false,
    );
    await service.trackFor('p1', language: 'original'); // learns that Hindi is spoken
    await tester.pumpWidget(ChangeNotifierProvider<CaptionService>.value(
      value: service,
      child: MaterialApp(
        theme: ForestTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(child: TextButton(onPressed: () => showCaptionPicker(context, postId: 'p1'), child: const Text('open'))),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Subtitles'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Original (Hindi)'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('ਪੰਜਾਬੀ (Punjabi)'), findsOneWidget);
    expect(find.text('हिन्दी (Hindi)'), findsNothing, reason: 'the spoken language is the "Original" row');

    await tester.tap(find.text('ਪੰਜਾਬੀ (Punjabi)'));
    await tester.pumpAndSettle();
    expect(service.enabled, isTrue);
    expect(service.language, 'pa');
    expect(find.text('Subtitles'), findsNothing, reason: 'the sheet closed');
  });
}
