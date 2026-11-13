import 'package:flutter/material.dart';

import '../features/editor/editor_pickers.dart' show videoLength;
import '../features/editor/editor_screen.dart';
import '../features/editor/post_attachment.dart';
import '../features/editor/record_page.dart';
import '../features/editor/recipe.dart';
import '../theme/forest_theme.dart';
import 'home_feed_screen.dart' show DefaultTabNavigator;

/// The Upload tab: what do you want to post? Each choice opens the editor (lib/features/editor).
///
/// With [attach] it is the same page opened for a purpose (answering the day's question, arguing in a room): see [openUploadFor].
class UploadScreen extends StatelessWidget {
  const UploadScreen({super.key, this.attach});

  final PostAttachment? attach;

  Future<void> _open(BuildContext context, EditorMode mode, {bool pickOnOpen = false}) async {
    final goTo = DefaultTabNavigator.of(context);
    final navigator = Navigator.of(context);
    final sent = await openEditor(context, mode: mode, pickOnOpen: pickOnOpen, attach: attach);
    if (sent != true) return;
    if (attach != null && navigator.canPop()) navigator.pop(true); // back to where the person came from, which says what happened
    goTo?.call(0); // show Home, where the new post appears once it is made
  }

  Future<void> _record(BuildContext context) async {
    final goTo = DefaultTabNavigator.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final path = await recordVideo(context);
    if (path == null || !context.mounted) return;
    final seconds = await videoLength(path);
    if (!context.mounted) return;
    if (seconds == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not read that recording. Try again.')));
      return;
    }
    final sent = await openEditor(context, mode: EditorMode.video, videoPath: path, videoSeconds: seconds, attach: attach);
    if (sent != true) return;
    if (attach != null && navigator.canPop()) navigator.pop(true);
    goTo?.call(0);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          Text(attach?.label ?? 'Create', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: t.fg)),
          const SizedBox(height: 6),
          Text(
            attach == null ? 'Start a debate with your opinion, then let others answer it.' : 'Choose how to make your video.',
            style: TextStyle(fontSize: 14, color: t.fg2),
          ),
          const SizedBox(height: 22),
          _Tile(
            icon: Icons.videocam_outlined,
            title: 'Record a video',
            subtitle: 'Up to 60 seconds, then trim it',
            onTap: () => _record(context),
          ),
          _Tile(
            icon: Icons.video_library_outlined,
            title: 'Choose a video',
            subtitle: 'From your gallery, then trim it',
            onTap: () => _open(context, EditorMode.video, pickOnOpen: true),
          ),
          _Tile(
            icon: Icons.title_rounded,
            title: 'Text post',
            subtitle: 'Words on a colour or gradient, with motion',
            onTap: () => _open(context, EditorMode.text),
          ),
          _Tile(
            icon: Icons.photo_library_outlined,
            title: 'Photo post',
            subtitle: 'Up to 10 photos as a slideshow, with music',
            onTap: () => _open(context, EditorMode.photos, pickOnOpen: true),
          ),
        ],
      ),
    );
  }
}

/// Opens the Upload choices as their own page for a purpose (a question to answer, a room to argue in). Resolves true when a post was sent.
Future<bool?> openUploadFor(BuildContext context, PostAttachment attach) {
  return Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
    builder: (_) => Scaffold(
      appBar: AppBar(elevation: 0, scrolledUnderElevation: 0),
      body: UploadScreen(attach: attach),
    ),
  ));
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: t.raised,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: t.border)),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(color: t.accent.withValues(alpha: .14), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: t.accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: t.fg)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: TextStyle(fontSize: 13, color: t.fg2)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: t.fg2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
