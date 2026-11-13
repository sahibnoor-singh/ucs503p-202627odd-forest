import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'format.dart';

/// The thin progress line along the bottom of a video, which can be dragged (or tapped) to jump to any moment.
///
/// The line is a few pixels tall, but the touch area is [height] so a thumb can find it. While a finger is on it the line
/// grows, a dot shows where you are and a small label shows the time. The video is paused while dragging and carries on
/// afterwards if it was playing. Put it at the bottom of a [Stack] above the video.
class SeekBar extends StatefulWidget {
  const SeekBar({
    super.key,
    required this.controller,
    this.playedColor = Colors.white,
    this.height = 30,
  });

  final VideoPlayerController controller;
  final Color playedColor;

  /// Height of the touch area.
  final double height;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  /// Where the finger is, 0.0 to 1.0, while it is down; null otherwise.
  double? _drag;
  bool _wasPlaying = false;
  DateTime _lastSeek = DateTime.fromMillisecondsSinceEpoch(0);

  double _fractionAt(double dx, double width) => width <= 0 ? 0 : (dx / width).clamp(0.0, 1.0);

  void _seekTo(double fraction, {bool force = false}) {
    final total = widget.controller.value.duration;
    if (total <= Duration.zero) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastSeek) < const Duration(milliseconds: 70)) return; // do not flood the player
    _lastSeek = now;
    widget.controller.seekTo(Duration(milliseconds: (total.inMilliseconds * fraction).round()));
  }

  void _start(double dx, double width) {
    _wasPlaying = widget.controller.value.isPlaying;
    if (_wasPlaying) widget.controller.pause(); // no stuttering sound while the picture jumps about
    final f = _fractionAt(dx, width);
    setState(() => _drag = f);
    _seekTo(f, force: true);
  }

  void _update(double dx, double width) {
    final f = _fractionAt(dx, width);
    setState(() => _drag = f);
    _seekTo(f);
  }

  void _end() {
    final f = _drag;
    if (f != null) _seekTo(f, force: true);
    if (_wasPlaying) widget.controller.play();
    _wasPlaying = false;
    if (mounted) setState(() => _drag = null);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        return SizedBox(
          height: widget.height,
          width: double.infinity,
          child: Semantics(
            slider: true,
            label: 'Video position',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _seekTo(_fractionAt(d.localPosition.dx, width), force: true), // a tap jumps there
              onHorizontalDragStart: (d) => _start(d.localPosition.dx, width),
              onHorizontalDragUpdate: (d) => _update(d.localPosition.dx, width),
              onHorizontalDragEnd: (_) => _end(),
              onHorizontalDragCancel: _end,
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: widget.controller,
                builder: (context, value, _) {
                  final total = value.duration.inMilliseconds;
                  final played = total <= 0 ? 0.0 : (value.position.inMilliseconds / total).clamp(0.0, 1.0);
                  final buffered = total <= 0 || value.buffered.isEmpty
                      ? 0.0
                      : (value.buffered.last.end.inMilliseconds / total).clamp(0.0, 1.0);
                  final fraction = _drag ?? played;
                  final active = _drag != null;
                  final line = active ? 6.0 : 3.0;
                  return Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.bottomLeft,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: line,
                        child: Stack(
                          children: [
                            const ColoredBox(color: Color(0x47FFFFFF), child: SizedBox.expand()),
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: buffered,
                              child: const ColoredBox(color: Color(0x40FFFFFF), child: SizedBox.expand()),
                            ),
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: fraction,
                              child: ColoredBox(color: widget.playedColor, child: const SizedBox.expand()),
                            ),
                          ],
                        ),
                      ),
                      if (active) ...[
                        Positioned(
                          left: (width * fraction - 7).clamp(0.0, width - 14),
                          bottom: line / 2 - 7,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(color: widget.playedColor, shape: BoxShape.circle),
                          ),
                        ),
                        Positioned(
                          left: (width * fraction - 40).clamp(4.0, (width - 84).clamp(4.0, width)),
                          bottom: line + 14,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: const Color(0xB3000000), borderRadius: BorderRadius.circular(99)),
                            child: Text(
                              '${durationLabel(Duration(milliseconds: (total * fraction).round()))} / ${durationLabel(value.duration)}',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
