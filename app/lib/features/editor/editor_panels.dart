import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/forest_theme.dart';
import 'editor_controller.dart';
import 'editor_palette.dart';
import 'editor_widgets.dart';
import 'record_page.dart';
import 'editor_pickers.dart';
import 'recipe.dart';

/// The tools under the picture. Each panel reads and changes the [EditorController].

/// Background of a TEXT post: gradients, a plain colour, or two colours of your own.
class BackgroundPanel extends StatelessWidget {
  const BackgroundPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EditorController>();
    final t = context.forest;
    final bg = c.recipe.background;
    void set(Background b) => c.update((r) => r.copyWith(background: b));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const PanelLabel('Gradients'),
        SizedBox(
          height: 62,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: EditorPalette.gradients.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final g = EditorPalette.gradients[i];
              final on = bg.isGradient && bg.from == g.from && bg.to == g.to;
              return Semantics(
                button: true,
                selected: on,
                label: '${g.name} gradient',
                child: GestureDetector(
                  onTap: () => set(Background.gradient(g.from, g.to, angle: g.angle)),
                  child: Container(
                    width: 46,
                    height: 62,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: on ? t.fg : t.border, width: on ? 2.5 : 1),
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [g.from, g.to]),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const PanelLabel('Plain colour'),
        ColorDots(colors: EditorPalette.backgrounds, selected: bg.isGradient ? null : bg.from, onPick: (col) => set(Background.solid(col))),
        if (bg.isGradient) ...[
          const PanelLabel('Make your own'),
          Row(children: [
            Text('From', style: TextStyle(fontSize: 12, color: t.fg2)),
            const SizedBox(width: 10),
            Expanded(child: ColorDots(colors: EditorPalette.backgrounds, selected: bg.from, size: 24, onPick: (col) => set(Background.gradient(col, bg.to!, angle: bg.angle)))),
          ]),
          Row(children: [
            Text('To     ', style: TextStyle(fontSize: 12, color: t.fg2)),
            const SizedBox(width: 10),
            Expanded(child: ColorDots(colors: EditorPalette.backgrounds, selected: bg.to, size: 24, onPick: (col) => set(Background.gradient(bg.from, col, angle: bg.angle)))),
          ]),
          LabeledSlider(label: 'Direction', value: bg.angle, min: 0, max: 360, display: (v) => '${v.round()}°', onChanged: (v) => set(Background.gradient(bg.from, bg.to!, angle: v.roundToDouble()))),
        ],
      ],
    );
  }
}

/// The words of a TEXT post and how they look.
class TextPanel extends StatefulWidget {
  const TextPanel({super.key});

  @override
  State<TextPanel> createState() => _TextPanelState();
}

class _TextPanelState extends State<TextPanel> {
  late final TextEditingController _field;

  @override
  void initState() {
    super.initState();
    _field = TextEditingController(text: context.read<EditorController>().recipe.text.content);
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EditorController>();
    final t = context.forest;
    final spec = c.recipe.text;
    void set(TextSpec s) => c.update((r) => r.copyWith(text: s));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _field,
          maxLines: 3,
          minLines: 2,
          maxLength: EditorLimits.maxTextChars,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (v) => set(spec.copyWith(content: v)),
          style: TextStyle(color: t.fg),
          decoration: InputDecoration(
            hintText: 'Say it in a few words',
            hintStyle: TextStyle(color: t.fg2),
            counterStyle: TextStyle(color: t.fg2),
            filled: true,
            fillColor: t.bg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.border)),
          ),
        ),
        LettersNote(spec.content),
        const PanelLabel('Colour'),
        ColorDots(colors: EditorPalette.textColors, selected: spec.color, onPick: (col) => set(spec.copyWith(color: col))),
        const PanelLabel('Style'),
        Row(
          children: [
            Expanded(
              child: ChoicePills<EditorFont>(values: EditorFont.values, selected: spec.font, label: (f) => f.label, onPick: (f) => set(spec.copyWith(font: f))),
            ),
            const SizedBox(width: 8),
            for (final a in TextAlignment.values) ...[
              IconChoice(
                icon: switch (a) {
                  TextAlignment.left => Icons.format_align_left,
                  TextAlignment.center => Icons.format_align_center,
                  TextAlignment.right => Icons.format_align_right,
                },
                label: 'Align ${a.wire}',
                on: spec.align == a,
                onTap: () => set(spec.copyWith(align: a)),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
        LabeledSlider(label: 'Size', value: spec.size, min: 32, max: 120, display: (v) => '${v.round()}', onChanged: (v) => set(spec.copyWith(size: v.roundToDouble()))),
      ],
    );
  }
}

/// How the words come in, and for how long the post lasts.
class MotionPanel extends StatelessWidget {
  const MotionPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EditorController>();
    final spec = c.recipe.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const PanelLabel('How the words appear'),
        ChoicePills<TextAnimation>(
          values: TextAnimation.values,
          selected: spec.animation,
          label: (a) => a.label,
          onPick: (a) => c.update((r) => r.copyWith(text: r.text.copyWith(animation: a))),
        ),
        const SizedBox(height: 6),
        LabeledSlider(
          label: 'Lasts',
          value: c.recipe.durationSec,
          min: EditorLimits.minTextSeconds,
          max: 30,
          divisions: 27,
          display: (v) => '${v.round()} s',
          onChanged: (v) => c.update((r) => r.copyWith(durationSec: v.roundToDouble())),
        ),
      ],
    );
  }
}

/// The question (for a new opinion) and a caption.
class DetailsPanel extends StatefulWidget {
  const DetailsPanel({super.key});

  @override
  State<DetailsPanel> createState() => _DetailsPanelState();
}

class _DetailsPanelState extends State<DetailsPanel> {
  late final TextEditingController _title;
  late final TextEditingController _caption;

  @override
  void initState() {
    super.initState();
    final c = context.read<EditorController>();
    _title = TextEditingController(text: c.title);
    _caption = TextEditingController(text: c.caption);
  }

  @override
  void dispose() {
    _title.dispose();
    _caption.dispose();
    super.dispose();
  }

  InputDecoration _decoration(BuildContext context, String hint) {
    final t = context.forest;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: t.fg2),
      counterStyle: TextStyle(color: t.fg2),
      filled: true,
      fillColor: t.bg,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.border)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.read<EditorController>();
    final t = context.forest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!c.isReply) ...[
          const PanelLabel('The question for the debate'),
          TextField(
            controller: _title,
            maxLength: EditorLimits.maxTitleChars,
            style: TextStyle(color: t.fg),
            decoration: _decoration(context, 'Optional. We write one from what you say if you leave it empty.'),
            onChanged: c.setTitle,
          ),
        ],
        const PanelLabel('Caption'),
        TextField(
          controller: _caption,
          maxLength: EditorLimits.maxCaptionChars,
          maxLines: 2,
          minLines: 1,
          style: TextStyle(color: t.fg),
          decoration: _decoration(context, 'Optional. We write one from what you say if you leave it empty.'),
          onChanged: c.setCaption,
        ),
      ],
    );
  }
}

/// The photos of a PHOTOS post: add, reorder (hold and drag) and remove.
class PhotosPanel extends StatelessWidget {
  const PhotosPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EditorController>();
    final t = context.forest;
    final photos = c.photos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: PanelLabel('Photos', trailing: '${photos.length} / ${EditorLimits.maxPhotos}')),
          ],
        ),
        if (photos.isEmpty)
          Text('Pick up to ${EditorLimits.maxPhotos} photos. They play one after another.', style: TextStyle(fontSize: 13, color: t.fg2))
        else
          SizedBox(
            height: 104,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              onReorderItem: c.movePhoto,
              proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
              itemBuilder: (context, i) {
                final path = photos[i];
                final same = photos.sublist(0, i).where((p) => p == path).length;
                return Container(
                  key: ValueKey('$path#$same'),
                  width: 66,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: t.border)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.file(File(path), fit: BoxFit.cover, cacheWidth: 200, errorBuilder: (_, _, _) => ColoredBox(color: t.border)),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Semantics(
                          button: true,
                          label: 'Remove photo ${i + 1}',
                          child: GestureDetector(
                            onTap: () => c.removePhoto(i),
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: const BoxDecoration(color: Color(0xB3000000), shape: BoxShape.circle),
                              child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 4,
                        bottom: 3,
                        child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, shadows: [Shadow(blurRadius: 3, color: Colors.black)])),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton.tonalIcon(
              onPressed: photos.length >= EditorLimits.maxPhotos ? null : c.pickMorePhotos,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('Add photos'),
            ),
            const SizedBox(width: 10),
            if (photos.length > 1) Expanded(child: Text('Hold a photo and drag to reorder.', style: TextStyle(fontSize: 12, color: t.fg2))),
          ],
        ),
      ],
    );
  }
}

/// How long each photo stays, and how one gives way to the next.
class TimingPanel extends StatelessWidget {
  const TimingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EditorController>();
    final t = context.forest;
    final r = c.recipe;
    final total = c.length;
    final tooLong = total > EditorLimits.maxSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const PanelLabel('Each photo shows for'),
        LabeledSlider(
          label: 'Time',
          value: r.slideSeconds,
          min: 1,
          max: 8,
          divisions: 14,
          display: (v) => '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)} s',
          onChanged: (v) => c.update((x) => x.copyWith(slideSeconds: (v * 2).round() / 2)),
        ),
        const PanelLabel('Between photos'),
        ChoicePills<PhotoTransition>(values: PhotoTransition.values, selected: r.transition, label: (v) => v.label, onPick: (v) => c.update((x) => x.copyWith(transition: v))),
        const SizedBox(height: 10),
        Text(
          c.photos.isEmpty ? 'No photos yet.' : 'The post lasts ${total.toStringAsFixed(1)} seconds.${tooLong ? ' That is over the 60 second limit: show each photo for less time, or use fewer photos.' : ''}',
          style: TextStyle(fontSize: 12.5, color: tooLong ? t.againstStance : t.fg2),
        ),
      ],
    );
  }
}

String _clock(double seconds) => clockText(seconds);

/// Records a video (or takes one from the gallery) into the editor.
Future<void> recordIntoEditor(BuildContext context) async {
  final c = context.read<EditorController>();
  final path = await recordVideo(context);
  if (path == null) return;
  final seconds = await videoLength(path);
  if (seconds == null) {
    c.say('Could not read that recording. Try again.');
    return;
  }
  c.useVideo(path, seconds);
}

/// Which part of the video to keep.
class TrimPanel extends StatelessWidget {
  const TrimPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EditorController>();
    final t = context.forest;
    final total = c.videoSeconds;
    final trim = c.recipe.trim;
    if (c.videoPath == null || total == null || trim == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const PanelLabel('Video'),
          Text('Record a video or choose one from your gallery.', style: TextStyle(fontSize: 13, color: t.fg2)),
          const SizedBox(height: 10),
          _sourceButtons(context, c),
        ],
      );
    }
    final tooLong = total > EditorLimits.maxSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        PanelLabel('Keep this part', trailing: '${trim.length.toStringAsFixed(1)} s'),
        RangeSlider(
          values: RangeValues(trim.startSec.clamp(0, total).toDouble(), trim.endSec.clamp(0, total).toDouble()),
          min: 0,
          max: total,
          activeColor: t.accent,
          inactiveColor: t.border,
          onChanged: (v) {
            // the slider reports both handles; whichever moved is the one the person is dragging
            if ((v.start - trim.startSec).abs() > (v.end - trim.endSec).abs()) {
              c.setTrim(start: v.start);
            } else {
              c.setTrim(end: v.end);
            }
          },
        ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 14,
          runSpacing: 2,
          children: [
            Text('From ${_clock(trim.startSec)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.fg)),
            Text('of ${_clock(total)}', style: TextStyle(fontSize: 12, color: t.fg2)),
            Text('To ${_clock(trim.endSec)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.fg)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          tooLong ? 'Your video is ${_clock(total)} long. Posts can be 60 seconds at most, so pick the part you want.' : 'Drag the ends to cut the start and the finish.',
          style: TextStyle(fontSize: 12.5, color: tooLong ? t.fg : t.fg2),
        ),
        const SizedBox(height: 10),
        _sourceButtons(context, c),
      ],
    );
  }

  Widget _sourceButtons(BuildContext context, EditorController c) {
    // Wrap: two buttons do not fit side by side on a narrow phone
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(onPressed: () => recordIntoEditor(context), icon: const Icon(Icons.fiber_manual_record, size: 14), label: Text(c.videoPath == null ? 'Record' : 'Record again')),
        OutlinedButton.icon(onPressed: c.pickGalleryVideo, icon: const Icon(Icons.video_library_outlined, size: 18), label: Text(c.videoPath == null ? 'Choose a video' : 'Choose another')),
      ],
    );
  }
}

/// The video's own sound.
class SoundPanel extends StatelessWidget {
  const SoundPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EditorController>();
    final t = context.forest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const PanelLabel('Original sound'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: !c.recipe.muteOriginal,
          onChanged: (on) => c.update((r) => r.copyWith(muteOriginal: !on)),
          title: Text(c.recipe.muteOriginal ? 'Muted' : 'On', style: TextStyle(fontWeight: FontWeight.w700, color: t.fg)),
          subtitle: Text(
            c.recipe.muteOriginal ? 'The post will have no voice, so the AI reads only your text and caption.' : 'The AI listens to what you say to write the captions and place your reply.',
            style: TextStyle(fontSize: 12.5, color: t.fg2),
          ),
        ),
      ],
    );
  }
}
