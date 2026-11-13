import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../models/caption_cue.dart';
import '../services/caption_service.dart';
import '../theme/forest_theme.dart';
import 'forest_sheet.dart';

/// The subtitles of one post, in the language the viewer chose: fetches the lines (once per language) and shows the one
/// for the video's current position. Nothing is drawn while subtitles are off. Put it in a [Stack] above the video.
class PostCaptions extends StatefulWidget {
  const PostCaptions({
    super.key,
    required this.postId,
    required this.controller,
    this.bottom = 36,
    this.leftInset = 12,
    this.rightInset = 12,
  });

  final String postId;
  final VideoPlayerController controller;
  final double bottom;
  final double leftInset;
  final double rightInset;

  @override
  State<PostCaptions> createState() => _PostCaptionsState();
}

class _PostCaptionsState extends State<PostCaptions> {
  CaptionService? _service;
  CaptionTrack? _track;
  String? _key; // postId:language of the lines being shown or loaded

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _service = Provider.of<CaptionService?>(context);
    _load();
  }

  @override
  void didUpdateWidget(PostCaptions old) {
    super.didUpdateWidget(old);
    if (old.postId != widget.postId) {
      _track = null;
      _key = null;
    }
    _load();
  }

  void _load() {
    final service = _service;
    if (service == null || !service.enabled) return;
    final key = '${widget.postId}:${service.language}';
    if (key == _key) return;
    _key = key;
    service.trackFor(widget.postId).then((track) {
      if (mounted && _key == key) setState(() => _track = track);
    });
  }

  @override
  Widget build(BuildContext context) {
    final track = _track;
    if (_service == null || !_service!.enabled || track == null || track.cues.isEmpty) return const SizedBox.shrink();
    return CaptionOverlay(
      controller: widget.controller,
      cues: track.cues,
      bottom: widget.bottom,
      leftInset: widget.leftInset,
      rightInset: widget.rightInset,
    );
  }
}

/// "Subtitles": Off, the language spoken in the video, English and the other languages. The choice applies to every video.
Future<void> showCaptionPicker(BuildContext context, {required String postId}) {
  final service = context.read<CaptionService>();
  return showForestSheet<void>(
    context,
    builder: (sheet) {
      final t = sheet.forest;
      final spoken = service.spokenLanguage(postId);
      final original = spoken == null ? 'Original' : 'Original (${captionLanguageName(spoken)})';
      final options = <(String?, String)>[
        (null, 'Off'),
        ('original', original),
        ('en', 'English'),
        for (final l in kCaptionLanguages)
          if (l.code != 'en' && l.code != spoken) (l.code, l.label),
      ];
      return ListenableBuilder(
        listenable: service,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Subtitles', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final (code, label) in options)
                      InkWell(
                        onTap: () {
                          service.select(code);
                          Navigator.of(sheet).pop();
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.border))),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: t.fg)),
                              ),
                              if (code == null ? !service.enabled : service.enabled && service.language == code)
                                Icon(Icons.check_rounded, size: 20, color: t.fg),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// The subtitle line for the video's current position, centred near the bottom of the nearest [Stack].
/// Put it above the video and below the controls. It never takes touches.
class CaptionOverlay extends StatelessWidget {
  const CaptionOverlay({
    super.key,
    required this.controller,
    required this.cues,
    this.bottom = 36,
    this.leftInset = 12,
    this.rightInset = 12,
  });

  final VideoPlayerController controller;

  /// Sorted by start (see [CaptionCue.listFrom]).
  final List<CaptionCue> cues;

  /// Space between the bottom of the video area and the line, and from each side.
  final double bottom;
  final double leftInset;
  final double rightInset;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final cue = CaptionCue.at(cues, value.position);
            if (cue == null) return const SizedBox.shrink();
            return Padding(
              padding: EdgeInsets.fromLTRB(leftInset, 0, rightInset, bottom),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xB3000000),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      cue.text,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The round "CC" switch next to the mute button.
class CaptionButton extends StatelessWidget {
  const CaptionButton({super.key, required this.enabled, required this.onTap, this.size = 30});

  final bool enabled;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Semantics(
        button: true,
        toggled: enabled,
        label: enabled ? 'Turn subtitles off' : 'Turn subtitles on',
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: enabled ? 0.65 : 0.45),
            shape: BoxShape.circle,
            border: Border.all(color: enabled ? Colors.white : Colors.white38, width: 1.4),
          ),
          child: ExcludeSemantics(
            child: Text(
              'CC',
              style: TextStyle(
                color: enabled ? Colors.white : Colors.white60,
                fontSize: size * 0.34,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
