import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/post.dart';
import '../../models/user.dart';
import '../../theme/forest_theme.dart';
import '../home/feed_controller.dart';
import 'editor_controller.dart';
import 'editor_panels.dart';
import 'editor_panels_frame.dart';
import 'editor_panels_more.dart';
import 'editor_pickers.dart';
import 'photo_post_preview.dart';
import 'post_attachment.dart';
import 'video_post_preview.dart';
import 'recipe.dart';
import 'text_post_preview.dart';

/// Opens the editor full screen. Resolves true when a post was sent (it is then being made on the server).
///
/// [parent] makes it a reply. [videoPath] / [videoSeconds] start a VIDEO post with that file; [photos] start a PHOTOS post.
Future<bool?> openEditor(
  BuildContext context, {
  required EditorMode mode,
  Post? parent,
  User? parentAuthor,
  String? videoPath,
  double? videoSeconds,
  List<String> photos = const [],
  bool pickOnOpen = false,
  EditorPickers? pickers,
  PostAttachment? attach,
}) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      fullscreenDialog: true,
      builder: (_) => ChangeNotifierProvider<EditorController>(
        create: (_) {
          final c = EditorController(mode: mode, parent: parent, parentAuthor: parentAuthor, videoPath: videoPath, videoSeconds: videoSeconds, pickers: pickers, attach: attach);
          if (photos.isNotEmpty) c.addPhotos(photos);
          return c;
        },
        child: Theme(data: ForestTheme.dark, child: EditorScreen(pickOnOpen: pickOnOpen)),
      ),
    ),
  );
}

enum EditorTool {
  background('Backdrop', Icons.palette_outlined),
  text('Text', Icons.title_rounded),
  motion('Motion', Icons.auto_awesome_outlined),
  trim('Trim', Icons.content_cut_rounded),
  sound('Sound', Icons.volume_up_outlined),
  crop('Crop', Icons.crop_rounded),
  cover('Cover', Icons.image_outlined),
  overlay('Add text', Icons.text_fields_rounded),
  look('Look', Icons.tune_rounded),
  music('Music', Icons.music_note_outlined),
  photos('Photos', Icons.photo_library_outlined),
  timing('Timing', Icons.timer_outlined),
  details('Details', Icons.edit_note_rounded);

  const EditorTool(this.label, this.icon);
  final String label;
  final IconData icon;
}

List<EditorTool> toolsFor(EditorMode mode) => switch (mode) {
      EditorMode.text => [EditorTool.background, EditorTool.text, EditorTool.motion, EditorTool.overlay, EditorTool.look, EditorTool.music, EditorTool.details],
      EditorMode.photos => [EditorTool.photos, EditorTool.timing, EditorTool.crop, EditorTool.overlay, EditorTool.look, EditorTool.music, EditorTool.details],
      EditorMode.video => [EditorTool.trim, EditorTool.sound, EditorTool.crop, EditorTool.cover, EditorTool.overlay, EditorTool.look, EditorTool.music, EditorTool.details],
    };

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, this.pickOnOpen = false});

  /// Ask for photos (PHOTOS) or a gallery video (VIDEO) as soon as the screen is up.
  final bool pickOnOpen;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late EditorTool _tool = toolsFor(context.read<EditorController>().mode).first;

  @override
  void initState() {
    super.initState();
    if (widget.pickOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final c = context.read<EditorController>();
        if (c.mode == EditorMode.photos) c.pickMorePhotos();
        if (c.mode == EditorMode.video) c.pickGalleryVideo();
      });
    }
  }

  /// Shows a message from the controller once ("a photo was too big") and clears it.
  void _showNotice(EditorController c) {
    final text = c.notice;
    if (text == null) return;
    c.clearNotice();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    });
  }

  Future<void> _close() async {
    final c = context.read<EditorController>();
    if (c.posting) return;
    if (!c.hasContent) {
      Navigator.of(context).pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Discard this post?'),
        content: const Text('What you made will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Keep editing')),
          TextButton(onPressed: () => Navigator.of(dialog).pop(true), child: const Text('Discard')),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  /// A piece of text on the picture was tapped: select it and open the tool that edits it.
  void _pickOverlay(int index) {
    context.read<EditorController>().selectOverlay(index);
    setState(() => _tool = EditorTool.overlay);
  }

  Future<void> _post() async {
    final c = context.read<EditorController>();
    final feed = context.read<FeedController>();
    FocusManager.instance.primaryFocus?.unfocus();
    final sent = await c.submit(feed);
    if (sent && mounted) Navigator.of(context).pop(true);
  }

  Widget _preview(EditorController c) {
    switch (c.mode) {
      case EditorMode.text:
        return TextPostPreview(
          recipe: c.recipe,
          selectedOverlay: c.selectedOverlay,
          onOverlayTap: _pickOverlay,
          onOverlayMoved: (i, x, y) => c.changeOverlay(i, c.recipe.overlays[i].copyWith(x: x, y: y)),
        );
      case EditorMode.photos:
        return PhotoPostPreview(
          photos: c.photos,
          recipe: c.recipe,
          onAdd: c.pickMorePhotos,
          cropping: _tool == EditorTool.crop,
          cropRatio: c.cropRatio,
          onCrop: c.setCrop,
          selectedOverlay: c.selectedOverlay,
          onOverlayTap: _pickOverlay,
          onOverlayMoved: (i, x, y) => c.changeOverlay(i, c.recipe.overlays[i].copyWith(x: x, y: y)),
        );
      case EditorMode.video:
        return VideoPostPreview(
          path: c.videoPath,
          recipe: c.recipe,
          onChoose: c.pickGalleryVideo,
          onRecord: () => recordIntoEditor(context),
          cropping: _tool == EditorTool.crop,
          cropRatio: c.cropRatio,
          onCrop: c.setCrop,
          coverAt: _tool == EditorTool.cover ? (c.recipe.coverSec ?? 0) : null,
          selectedOverlay: c.selectedOverlay,
          onOverlayTap: _pickOverlay,
          onOverlayMoved: (i, x, y) => c.changeOverlay(i, c.recipe.overlays[i].copyWith(x: x, y: y)),
        );
    }
  }

  Widget _panel(EditorTool tool) => switch (tool) {
        EditorTool.background => const BackgroundPanel(),
        EditorTool.text => const TextPanel(),
        EditorTool.motion => const MotionPanel(),
        EditorTool.overlay => const OverlayPanel(),
        EditorTool.look => const LookPanel(),
        EditorTool.music => const MusicPanel(),
        EditorTool.trim => const TrimPanel(),
        EditorTool.sound => const SoundPanel(),
        EditorTool.crop => const CropPanel(),
        EditorTool.cover => const CoverPanel(),
        EditorTool.photos => const PhotosPanel(),
        EditorTool.timing => const TimingPanel(),
        EditorTool.details => const DetailsPanel(),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EditorController>();
    final t = context.forest;
    final tools = toolsFor(c.mode);
    final problem = c.problem;
    _showNotice(c);
    final screenHeight = MediaQuery.sizeOf(context).height;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light, // light clock and battery icons on the dark editor
        child: Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
          child: Column(
            children: [
              _TopBar(
                title: c.isReply ? 'Reply to @${c.parentAuthor?.username ?? ''}' : (c.attach?.label ?? 'New opinion'),
                posting: c.posting,
                canPost: c.canPost,
                onClose: _close,
                onPost: _post,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: t.border)),
                      child: ClipRRect(borderRadius: BorderRadius.circular(13), child: _preview(c)),
                    ),
                  ),
                ),
              ),
              if (c.error != null || (problem != null && c.hasContent))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Text(c.error ?? problem!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: c.error != null ? t.againstStance : t.fg2)),
                ),
              Container(
                decoration: BoxDecoration(color: t.raised, border: Border(top: BorderSide(color: t.border))),
                constraints: BoxConstraints(maxHeight: math.min(380, screenHeight * 0.44)),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  // a Material so list tiles and switches inside the coloured panel paint their ink properly
                  child: Material(type: MaterialType.transparency, child: _panel(_tool)),
                ),
              ),
              _ToolBar(tools: tools, selected: _tool, onPick: (tool) => setState(() => _tool = tool)),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.posting, required this.canPost, required this.onClose, required this.onPost});

  final String title;
  final bool posting;
  final bool canPost;
  final VoidCallback onClose;
  final VoidCallback onPost;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          IconButton(tooltip: 'Close', onPressed: posting ? null : onClose, icon: Icon(Icons.close_rounded, color: t.fg)),
          Expanded(child: Text(title, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: t.fg))),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: canPost ? onPost : null,
              style: FilledButton.styleFrom(
                backgroundColor: t.accent,
                disabledBackgroundColor: t.border,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
              ),
              child: posting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Post', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

/// The row of tools under the panel. Up to five share the width, so none is hidden off the edge; more than that scroll, with
/// the next one cut in half at the edge so it is clear there is more.
class _ToolBar extends StatelessWidget {
  const _ToolBar({required this.tools, required this.selected, required this.onPick});

  final List<EditorTool> tools;
  final EditorTool selected;
  final ValueChanged<EditorTool> onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    Widget item(EditorTool tool) {
      final on = tool == selected;
      return Semantics(
        button: true,
        selected: on,
        label: tool.label,
        excludeSemantics: true,
        child: InkWell(
          onTap: () => onPick(tool),
          child: Container(
            constraints: const BoxConstraints(minWidth: 68),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(tool.icon, size: 22, color: on ? t.fg : t.fg2),
                const SizedBox(height: 3),
                Text(tool.label, maxLines: 1, style: TextStyle(fontSize: 11, fontWeight: on ? FontWeight.w800 : FontWeight.w600, color: on ? t.fg : t.fg2)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      color: t.raised,
      height: 58,
      child: tools.length <= 5
          ? Row(children: [for (final tool in tools) Expanded(child: item(tool))])
          : ListView(
              scrollDirection: Axis.horizontal,
              children: [for (final tool in tools) SizedBox(width: MediaQuery.sizeOf(context).width / 5.5, child: item(tool))],
            ),
    );
  }
}
