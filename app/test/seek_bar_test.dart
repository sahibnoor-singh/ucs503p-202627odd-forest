// The draggable progress line under a video: dragging jumps through the video, a tap jumps there, and the video is
// paused while the finger is down and carries on afterwards only if it was playing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:forest_app/ui/seek_bar.dart';

/// A real controller whose platform calls are replaced by records.
class _Recorder extends VideoPlayerController {
  _Recorder() : super.networkUrl(Uri.parse('http://test.invalid/a.mp4'));

  final seeks = <Duration>[];
  int plays = 0;
  int pauses = 0;

  @override
  Future<void> seekTo(Duration position) async {
    seeks.add(position);
    value = value.copyWith(position: position);
  }

  @override
  Future<void> play() async {
    plays++;
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    pauses++;
    value = value.copyWith(isPlaying: false);
  }

  @override
  // ignore: must_call_super — a fake: there is no platform player to release
  Future<void> dispose() async {}
}

Future<_Recorder> _pump(WidgetTester tester, {required bool playing}) async {
  final c = _Recorder();
  c.value = c.value.copyWith(isInitialized: true, duration: const Duration(seconds: 60), isPlaying: playing);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(width: 400, child: SeekBar(controller: c)),
      ),
    ),
  ));
  return c;
}

void main() {
  testWidgets('dragging along the line jumps through the video and shows the time', (tester) async {
    final c = await _pump(tester, playing: true);
    final box = tester.getRect(find.byType(SeekBar));
    final y = box.bottom - 5;

    final gesture = await tester.startGesture(Offset(box.left + 40, y)); // 10 %
    await tester.pump();
    await gesture.moveTo(Offset(box.left + 200, y)); // 50 %
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('/ 1:00'), findsOneWidget, reason: 'a time label shows while dragging');
    expect(find.text('0:30 / 1:00'), findsOneWidget);
    await gesture.moveTo(Offset(box.left + 300, y)); // 75 %
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump();

    expect(c.seeks, isNotEmpty);
    expect(c.seeks.last.inSeconds, inInclusiveRange(44, 46), reason: 'ends at about 75 % of 60 s');
    expect(c.pauses, 1, reason: 'paused while dragging');
    expect(c.plays, 1, reason: 'and it carries on afterwards');
    expect(find.textContaining('/ 1:00'), findsNothing, reason: 'the label goes away');
  });

  testWidgets('a video that was paused stays paused after dragging', (tester) async {
    final c = await _pump(tester, playing: false);
    final box = tester.getRect(find.byType(SeekBar));
    final gesture = await tester.startGesture(Offset(box.left + 100, box.bottom - 5));
    await tester.pump();
    await gesture.moveTo(Offset(box.left + 300, box.bottom - 5));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump();
    expect(c.seeks, isNotEmpty);
    expect(c.pauses, 0);
    expect(c.plays, 0);
  });

  testWidgets('a tap jumps to that point', (tester) async {
    final c = await _pump(tester, playing: true);
    final box = tester.getRect(find.byType(SeekBar));
    await tester.tapAt(Offset(box.left + 100, box.bottom - 5)); // 25 %
    await tester.pump();
    expect(c.seeks.single.inSeconds, inInclusiveRange(14, 16));
    expect(c.pauses, 0, reason: 'a tap does not pause');
  });

  testWidgets('the touch area is taller than the line, so a thumb can find it', (tester) async {
    await _pump(tester, playing: true);
    expect(tester.getSize(find.byType(SeekBar)).height, greaterThanOrEqualTo(26));
  });
}
