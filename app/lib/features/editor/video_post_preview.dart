import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'adjust_filter.dart';
import 'crop_editor.dart';
import 'overlay_layer.dart';
import 'recipe.dart';

/// The picked video as it will be posted: only the trimmed part, looping, with the sound on or off and any text laid over it.
/// Moving a trim handle jumps the picture to that moment. Tap to pause and play.
class VideoPostPreview extends StatefulWidget {
  const VideoPostPreview({
    super.key,
    required this.path,
    required this.recipe,
    this.onChoose,
    this.onRecord,
    this.onOverlayMoved,
    this.onOverlayTap,
    this.selectedOverlay,
    this.cropping = false,
    this.cropRatio,
    this.onCrop,
    this.coverAt,
  });

  final String? path;
  final Recipe recipe;

  /// Shown when there is no video yet.
  final VoidCallback? onChoose;
  final VoidCallback? onRecord;
  final void Function(int index, double x, double y)? onOverlayMoved;
  final void Function(int index)? onOverlayTap;
  final int? selectedOverlay;

  /// The Crop tool is open: show the whole picture with the crop box over it (and hold still).
  final bool cropping;

  /// The shape the crop box keeps while it is resized, or null for free.
  final double? cropRatio;
  final ValueChanged<Crop?>? onCrop;

  /// The Cover tool is open: hold still on this moment (seconds into the kept part) of the video.
  final double? coverAt;

  @override
  State<VideoPostPreview> createState() => _VideoPostPreviewState();
}

class _VideoPostPreviewState extends State<VideoPostPreview> {
  VideoPlayerController? _video;
  bool _failed = false;

  Trim? get _trim => widget.recipe.trim;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(VideoPostPreview old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _close();
      _open();
      return;
    }
    final v = _video;
    if (v == null) return;
    if (old.recipe.muteOriginal != widget.recipe.muteOriginal) v.setVolume(widget.recipe.muteOriginal ? 0 : 1);
    final was = old.cropping || old.coverAt != null;
    final holding = widget.cropping || widget.coverAt != null;
    if (holding && !was) v.pause();
    if (!holding && was) {
      _seek(_at(_trim?.startSec ?? 0));
      v.play();
    }
    if (widget.coverAt != null && widget.coverAt != old.coverAt) {
      v.pause();
      _seek(_at((_trim?.startSec ?? 0) + widget.coverAt!));
      return;
    }
    final a = old.recipe.trim;
    final b = widget.recipe.trim;
    if (a != null && b != null) {
      // a handle was moved: show the frame it points at, and wait there until the person lets go and presses play
      if (a.startSec != b.startSec) {
        v.pause();
        _seek(_at(b.startSec));
      } else if (a.endSec != b.endSec) {
        v.pause();
        _seek(_at(b.endSec - 0.2));
      }
    }
  }

  Duration _at(double seconds) => Duration(milliseconds: (seconds.clamp(0, 36000) * 1000).round());

  bool _seeking = false;
  Duration? _seekNext;

  /// Jumps to [to]. While a jump is still going on, only the latest wish is kept (dragging a slider asks for dozens a second, and a
  /// queue of stale ones would leave the picture behind the finger).
  Future<void> _seek(Duration to) async {
    final v = _video;
    if (v == null) return;
    if (_seeking) {
      _seekNext = to;
      return;
    }
    _seeking = true;
    try {
      await v.seekTo(to);
    } on Object {
      // the player was closed under us; nothing to show
    }
    _seeking = false;
    final next = _seekNext;
    _seekNext = null;
    if (next != null && mounted && _video == v) await _seek(next);
  }

  Future<void> _open() async {
    final path = widget.path;
    if (path == null) return;
    final controller = VideoPlayerController.file(File(path));
    _video = controller;
    _failed = false;
    try {
      await controller.initialize();
      if (!mounted || _video != controller) return;
      await controller.setVolume(widget.recipe.muteOriginal ? 0 : 1);
      controller.addListener(_loop);
      final cover = widget.coverAt;
      await controller.seekTo(_at((_trim?.startSec ?? 0) + (cover ?? 0)));
      if (!widget.cropping && cover == null) await controller.play();
      if (mounted) setState(() {});
    } on Object {
      if (mounted && _video == controller) setState(() => _failed = true);
    }
  }

  /// Plays only the trimmed part: at its end, go back to its start.
  void _loop() {
    final v = _video;
    if (v == null || !v.value.isInitialized || !v.value.isPlaying) return;
    final end = _trim?.endSec ?? v.value.duration.inMilliseconds / 1000;
    if (v.value.position.inMilliseconds / 1000 >= end - 0.05) v.seekTo(_at(_trim?.startSec ?? 0));
  }

  void _close() {
    final v = _video;
    _video = null;
    v?.removeListener(_loop);
    v?.dispose();
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;
    if (widget.path == null) return _empty(context);
    if (_failed) {
      return const AspectRatio(
        aspectRatio: 9 / 16,
        child: ColoredBox(color: Colors.black, child: Center(child: Text('This video cannot be played here.', style: TextStyle(color: Colors.white70)))),
      );
    }
    if (v == null || !v.value.isInitialized) {
      return const AspectRatio(aspectRatio: 9 / 16, child: ColoredBox(color: Colors.black, child: Center(child: CircularProgressIndicator(color: Colors.white54))));
    }
    final whole = v.value.aspectRatio <= 0 ? 9 / 16 : v.value.aspectRatio;
    final crop = widget.cropping ? null : widget.recipe.crop;
    return AspectRatio(
      aspectRatio: crop == null ? whole : whole * crop.w / crop.h,
      child: LayoutBuilder(builder: (context, box) {
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.cropping ? null : () => setState(() => v.value.isPlaying ? v.pause() : v.play()),
                child: CropWindow(
                  crop: crop,
                  child: AdjustedPicture(adjust: widget.recipe.adjust, pictureWidth: box.maxWidth, child: VideoPlayer(v)),
                ),
              ),
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: v,
                builder: (context, value, _) => value.isPlaying || widget.cropping || widget.coverAt != null
                    ? const SizedBox.shrink()
                    : const IgnorePointer(child: Center(child: Icon(Icons.play_circle_fill_rounded, size: 64, color: Colors.white70))),
              ),
              if (widget.cropping)
                CropEditor(crop: widget.recipe.crop, sourceAspect: whole, ratio: widget.cropRatio, onChanged: widget.onCrop ?? (_) {})
              else
                OverlayLayer(
                  overlays: widget.recipe.overlays,
                  size: Size(box.maxWidth, box.maxHeight),
                  selected: widget.selectedOverlay,
                  onMoved: widget.onOverlayMoved,
                  onTap: widget.onOverlayTap,
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _empty(BuildContext context) {
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_outlined, color: Colors.white54, size: 40),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: widget.onRecord, icon: const Icon(Icons.fiber_manual_record, size: 16), label: const Text('Record')),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: widget.onChoose, icon: const Icon(Icons.video_library_outlined, size: 18), label: const Text('Choose a video')),
            ],
          ),
        ),
      ),
    );
  }
}
