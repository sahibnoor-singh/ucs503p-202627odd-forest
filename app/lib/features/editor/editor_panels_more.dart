import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../theme/forest_theme.dart';
import 'adjust_filter.dart';
import 'editor_controller.dart';
import 'editor_palette.dart';
import 'editor_pickers.dart';
import 'editor_widgets.dart';
import 'recipe.dart';

/// More tools under the picture: text laid over it, its colour look, and music.

/// Pieces of text laid over the picture (up to five), each with its own look and the time it is shown.
class OverlayPanel extends StatelessWidget {
  const OverlayPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EditorController>();
    final t = context.forest;
    final overlays = c.recipe.overlays;
    final sel = c.selectedOverlay;
    final length = c.length;

    String short(String s) => s.length <= 12 ? s : '${s.substring(0, 11)}…';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        PanelLabel('Text on the picture', trailing: '${overlays.length} / ${EditorLimits.maxOverlays}'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < overlays.length; i++)
              GestureDetector(
                onTap: () => c.selectOverlay(i),
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: sel == i ? t.fg : Colors.transparent,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: sel == i ? t.fg : t.border),
                  ),
                  child: Center(widthFactor: 1, child: Text(short(overlays[i].text), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: sel == i ? t.bg : t.fg))),
                ),
              ),
            if (overlays.length < EditorLimits.maxOverlays)
              GestureDetector(
                onTap: () => c.addOverlay(TextOverlay(text: 'Your text', y: 0.3 + 0.12 * overlays.length)),
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), border: Border.all(color: t.accent)),
                  child: Center(widthFactor: 1, child: Text('+ Add text', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.accent))),
                ),
              ),
          ],
        ),
        if (sel == null || sel >= overlays.length)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(overlays.isEmpty ? 'Add text, then drag it where you want it.' : 'Pick a piece of text above, or tap it on the picture.', style: TextStyle(fontSize: 13, color: t.fg2)),
          )
        else
          _Editing(index: sel, overlay: overlays[sel], length: length),
      ],
    );
  }
}

class _Editing extends StatelessWidget {
  const _Editing({required this.index, required this.overlay, required this.length});

  final int index;
  final TextOverlay overlay;
  final double length;

  @override
  Widget build(BuildContext context) {
    final c = context.read<EditorController>();
    final t = context.forest;
    void set(TextOverlay o) => c.changeOverlay(index, o);
    final start = overlay.startSec.clamp(0.0, length).toDouble();
    final end = (overlay.endSec ?? length).clamp(start, length).toDouble();
    String s(double v) => '${v.toStringAsFixed(1)} s';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 10),
        TextFormField(
          key: ValueKey('overlay-text-$index'),
          initialValue: overlay.text,
          maxLength: EditorLimits.maxOverlayChars,
          style: TextStyle(color: t.fg),
          decoration: InputDecoration(
            hintText: 'What should it say?',
            hintStyle: TextStyle(color: t.fg2),
            counterStyle: TextStyle(color: t.fg2),
            filled: true,
            fillColor: t.bg,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.border)),
          ),
          onChanged: (v) => set(overlay.copyWith(text: v)),
        ),
        LettersNote(overlay.text),
        const PanelLabel('Colour'),
        ColorDots(colors: EditorPalette.textColors, selected: overlay.color, size: 26, onPick: (col) => set(overlay.copyWith(color: col))),
        const PanelLabel('Style'),
        ChoicePills<EditorFont>(values: EditorFont.values, selected: overlay.font, label: (f) => f.label, onPick: (f) => set(overlay.copyWith(font: f))),
        LabeledSlider(label: 'Size', value: overlay.size, min: 20, max: 120, display: (v) => '${v.round()}', onChanged: (v) => set(overlay.copyWith(size: v.roundToDouble()))),
        LabeledSlider(
          label: 'Shows from',
          value: start,
          min: 0,
          max: (length - 0.1).clamp(0.1, 3600).toDouble(),
          display: s,
          onChanged: (v) => set(overlay.copyWith(startSec: (v * 10).round() / 10, endSec: end <= v ? v + 0.1 : end)),
        ),
        LabeledSlider(
          label: 'Until',
          value: end,
          min: (start + 0.1).clamp(0.1, 3600).toDouble(),
          max: length.clamp(0.2, 3600).toDouble(),
          display: s,
          onChanged: (v) => set(overlay.copyWith(endSec: (v * 10).round() / 10)),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => c.removeOverlay(index),
            icon: Icon(Icons.delete_outline_rounded, size: 18, color: t.againstStance),
            label: Text('Remove this text', style: TextStyle(color: t.againstStance)),
          ),
        ),
      ],
    );
  }
}

/// The picture's colours: a ready-made look, or sliders.
class LookPanel extends StatelessWidget {
  const LookPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EditorController>();
    final a = c.recipe.adjust;
    void set(Adjust x) => c.update((r) => r.copyWith(adjust: x));
    String two(double v) => v.toStringAsFixed(2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const PanelLabel('Look'),
        ChoicePills<LookPreset>(
          values: LookPreset.all,
          selected: LookPreset.all.firstWhere((p) => p.matches(a), orElse: () => const LookPreset('Custom', Adjust())),
          label: (p) => p.name,
          onPick: (p) => set(p.adjust),
        ),
        const PanelLabel('Fine tune'),
        LabeledSlider(label: 'Brightness', value: a.brightness, min: -0.5, max: 0.5, display: two, onChanged: (v) => set(a.copyWith(brightness: (v * 100).round() / 100))),
        LabeledSlider(label: 'Contrast', value: a.contrast, min: 0.5, max: 2, display: two, onChanged: (v) => set(a.copyWith(contrast: (v * 100).round() / 100))),
        LabeledSlider(label: 'Colour', value: a.saturation, min: 0, max: 3, display: two, onChanged: (v) => set(a.copyWith(saturation: (v * 100).round() / 100))),
        LabeledSlider(label: 'Tint', value: a.hue, min: -180, max: 180, display: (v) => '${v.round()}°', onChanged: (v) => set(a.copyWith(hue: v.roundToDouble()))),
        LabeledSlider(label: 'Blur', value: a.blur, min: 0, max: 10, display: (v) => v.toStringAsFixed(1), onChanged: (v) => set(a.copyWith(blur: (v * 10).round() / 10))),
        if (c.mode == EditorMode.text)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('On a text post this changes the background, not the words.', style: TextStyle(fontSize: 12, color: context.forest.fg2)),
          ),
      ],
    );
  }
}

/// A music file from the phone, mixed in under the post.
class MusicPanel extends StatefulWidget {
  const MusicPanel({super.key});

  @override
  State<MusicPanel> createState() => _MusicPanelState();
}

class _MusicPanelState extends State<MusicPanel> {
  VideoPlayerController? _player; // plays the audio file, so you can hear what you picked
  String? _playerPath;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle(EditorController c) async {
    final path = c.musicPath;
    if (path == null) return;
    if (_playerPath != path) {
      await _player?.dispose();
      final p = VideoPlayerController.file(File(path));
      try {
        await p.initialize();
      } on Object {
        await p.dispose();
        c.say('Could not play that file here.');
        return;
      }
      _player = p;
      _playerPath = path;
    }
    final p = _player!;
    await p.setVolume(c.recipe.music?.volume ?? .8);
    if (p.value.isPlaying) {
      await p.pause();
    } else {
      await p.seekTo(Duration(milliseconds: ((c.recipe.music?.startSec ?? 0) * 1000).round()));
      await p.play();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EditorController>();
    final t = context.forest;
    final music = c.recipe.music;
    if (c.musicPath == null || music == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const PanelLabel('Music'),
          Text('Add a song or sound from your phone. It plays under your post and fades out at the end.', style: TextStyle(fontSize: 13, color: t.fg2)),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(onPressed: c.pickMusic, icon: const Icon(Icons.library_music_outlined, size: 18), label: const Text('Choose music')),
          const SizedBox(height: 8),
          Text('Only use music you have the right to use.', style: TextStyle(fontSize: 12, color: t.fg2)),
        ],
      );
    }
    final playing = _player?.value.isPlaying ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const PanelLabel('Music'),
        Row(
          children: [
            IconButton.filledTonal(onPressed: () => _toggle(c), tooltip: playing ? 'Pause' : 'Play', icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded)),
            const SizedBox(width: 10),
            Expanded(child: Text(c.musicName ?? fileNameOf(c.musicPath!), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: t.fg))),
            IconButton(
              tooltip: 'Remove music',
              onPressed: () {
                _player?.pause();
                c.clearMusic();
              },
              icon: Icon(Icons.close_rounded, color: t.fg2),
            ),
          ],
        ),
        LabeledSlider(label: 'Volume', value: music.volume, min: 0, max: 1, display: (v) => '${(v * 100).round()}%', onChanged: (v) {
          c.update((r) => r.copyWith(music: music.copyWith(volume: (v * 100).round() / 100)));
          _player?.setVolume(v);
        }),
        LabeledSlider(label: 'Starts at', value: music.startSec, min: 0, max: 180, divisions: 180, display: (v) => '${v.round()} s into the song', onChanged: (v) => c.update((r) => r.copyWith(music: music.copyWith(startSec: v.roundToDouble())))),
        TextButton.icon(onPressed: c.pickMusic, icon: const Icon(Icons.swap_horiz_rounded, size: 18), label: const Text('Choose another')),
      ],
    );
  }
}
