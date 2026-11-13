import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack, kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/post.dart';
import '../../models/user.dart';
import '../../services/api_client.dart';
import '../../theme/forest_theme.dart';
import '../../ui/forest_icon.dart';
import '../../ui/forest_sheet.dart';
import '../../ui/text_limits.dart';
import '../home/feed_controller.dart';
import '../post/post_menu.dart';
import '../editor/editor_pickers.dart' show videoLength;
import '../editor/editor_screen.dart';
import '../editor/record_page.dart';
import '../editor/recipe.dart';

/// `↩ Reply`: reply to [parent] with a video (record or gallery) or text.
/// Resolves true when a reply was posted.
Future<bool?> showReplySheet(
  BuildContext context, {
  required Post parent,
  required User author,
  bool startWithText = false,
}) {
  return showForestSheet<bool>(
    context,
    builder: (_) => ReplySheet(parent: parent, author: author, startWithText: startWithText),
  );
}

enum _View { chooser, text }

class ReplySheet extends StatefulWidget {
  const ReplySheet({
    super.key,
    required this.parent,
    required this.author,
    this.startWithText = false,
  });

  final Post parent;
  final User author;
  final bool startWithText;

  @override
  State<ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends State<ReplySheet> {
  late _View _view = widget.startWithText ? _View.text : _View.chooser;
  final _text = TextEditingController();
  bool _showOptions = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Opens the editor to make the reply (a video, photos or a text card); closes this sheet once it was sent.
  Future<void> _openEditor(EditorMode mode, {bool pick = false, bool record = false}) async {
    String? videoPath;
    double? videoSeconds;
    if (record) {
      final path = await recordVideo(context);
      if (path == null || !mounted) return;
      final seconds = await videoLength(path);
      if (!mounted) return;
      if (seconds == null) {
        setState(() => _error = 'Could not read that recording. Try again.');
        return;
      }
      videoPath = path;
      videoSeconds = seconds;
    }
    setState(() => _error = null);
    final sent = await openEditor(
      context,
      mode: mode,
      parent: widget.parent,
      parentAuthor: widget.author,
      videoPath: videoPath,
      videoSeconds: videoSeconds,
      pickOnOpen: pick,
    );
    if (sent == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _post() async {
    final controller = context.read<FeedController>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await controller.replyText(widget.parent, _text.text);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('reply failed: $e');
        debugPrintStack(stackTrace: st);
      }
      if (mounted) setState(() => _error = 'Could not post your reply. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final isText = _view == _View.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Reply to @${widget.author.username}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _ModePill(
              icon: isText ? Icn.cam : null,
              label: isText ? 'Video' : 'Text',
              boldPrefix: isText ? null : 'Aa',
              onTap: _busy
                  ? null
                  : () => setState(() {
                        _error = null;
                        _view = isText ? _View.chooser : _View.text;
                      }),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SheetContext(snippetOf(widget.parent)),
        const SizedBox(height: 14),
        switch (_view) {
          _View.chooser => _chooser(t),
          _View.text => _textView(t),
        },
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, style: TextStyle(fontSize: 13, color: t.like)),
          ),
      ],
    );
  }

  Widget _chooser(ForestTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: t.accent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _showOptions = !_showOptions),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(color: Color(0x33FFFFFF), shape: BoxShape.circle),
                    child: const Center(child: ForestIcon(Icn.upload, size: 24, color: Colors.white)),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Upload video',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Record now or pick one from your gallery',
                          style: TextStyle(color: Color(0xD9FFFFFF), fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_showOptions) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Option(
                  icon: Icn.cam,
                  title: 'Record',
                  subtitle: 'Open camera',
                  onTap: () => _openEditor(EditorMode.video, record: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Option(
                  icon: Icn.image,
                  title: 'Gallery',
                  subtitle: 'Choose a video',
                  onTap: () => _openEditor(EditorMode.video, pick: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Option(
                  icon: Icn.image,
                  title: 'Photos',
                  subtitle: 'A slideshow',
                  onTap: () => _openEditor(EditorMode.photos, pick: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Option(
                  icon: Icn.cam,
                  title: 'Text card',
                  subtitle: 'Words with motion',
                  onTap: () => _openEditor(EditorMode.text),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'Video replies are the heart of FOREST. Tap Text if you just want to write.',
          style: TextStyle(fontSize: 12.5, color: t.fg2),
        ),
      ],
    );
  }

  Widget _textView(ForestTokens t) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _text,
      builder: (context, value, _) {
        final n = runeCount(value.text);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _text,
              autofocus: true,
              minLines: 4,
              maxLines: 6,
              style: const TextStyle(fontSize: 16),
              inputFormatters: const [RuneLimitFormatter(maxReplyChars)],
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Make your point in 280 characters',
                hintStyle: TextStyle(color: t.fg2),
                filled: true,
                fillColor: t.surface,
                contentPadding: const EdgeInsets.all(12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: t.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: t.accent, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Gemini will classify your stance',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: t.fg2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$n/$maxReplyChars',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: n >= 260 ? FontWeight.w700 : FontWeight.w400,
                    color: n >= 260 ? t.like : t.fg2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _PrimaryButton(
              label: 'Post reply',
              busy: _busy,
              onPressed: (_busy || value.text.trim().isEmpty) ? null : _post,
            ),
          ],
        );
      },
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({this.icon, required this.label, this.boldPrefix, required this.onTap});

  final String? icon;
  final String label;

  /// "Aa" in the Text pill, drawn bold like the prototype's `<b>Aa</b> Text`.
  final String? boldPrefix;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Material(
      color: t.surface,
      shape: StadiumBorder(side: BorderSide(color: t.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[ForestIcon(icon!, size: 17), const SizedBox(width: 6)],
              if (boldPrefix != null) ...[
                Text(boldPrefix!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
              ],
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Material(
      color: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: t.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          child: Column(
            children: [
              ForestIcon(icon, size: 28),
              const SizedBox(height: 4),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(subtitle, style: TextStyle(fontSize: 12, color: t.fg2)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.busy, required this.onPressed});

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        backgroundColor: t.accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: t.accent.withValues(alpha: 0.4),
        disabledForegroundColor: Colors.white70,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
            )
          : Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
    );
  }
}
