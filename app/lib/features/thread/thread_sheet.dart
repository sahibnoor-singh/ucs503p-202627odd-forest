import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack, kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/feed_item.dart';
import '../../models/post.dart';
import '../../models/user.dart';
import '../../services/api_client.dart';
import '../../theme/forest_theme.dart';
import '../../ui/chips.dart';
import '../../ui/forest_avatar.dart';
import '../../ui/forest_icon.dart';
import '../../ui/forest_sheet.dart';
import '../../ui/format.dart';
import '../../ui/text_limits.dart';
import '../home/feed_controller.dart';
import '../home/feed_item_card.dart';
import '../post/post_menu.dart';
import '../reply/reply_sheet.dart';

/// `💬`: every reply under [postId], as a tree, with a composer at the bottom.
Future<void> showThreadSheet(
  BuildContext context, {
  required String postId,
  required CardActions actions,
}) {
  return showForestSheet<void>(
    context,
    tall: true,
    builder: (_) => ThreadSheet(postId: postId, actions: actions, hostContext: context),
  );
}

class ThreadSheet extends StatefulWidget {
  const ThreadSheet({
    super.key,
    required this.postId,
    required this.actions,
    required this.hostContext,
  });

  final String postId;
  final CardActions actions;

  /// A context under the Home screen, used to open the reply sheet and viewer
  /// above this sheet.
  final BuildContext hostContext;

  @override
  State<ThreadSheet> createState() => _ThreadSheetState();
}

class _ThreadSheetState extends State<ThreadSheet> {
  late Future<ThreadResponse> _future;
  final _input = TextEditingController();
  Post? _replyTo; // null = the post this thread belongs to
  User? _replyToAuthor;
  bool _posting = false;
  String? _error;

  FeedController get _c => context.read<FeedController>();

  @override
  void initState() {
    super.initState();
    _future = _c.loadThread(widget.postId);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  // a block, not an arrow: setState must not be handed a callback that returns the Future (Flutter's debug check throws, which
  // made a reply that WAS posted look like "Could not post your reply")
  void _reload() {
    setState(() {
      _future = _c.loadThread(widget.postId);
    });
  }

  Future<void> _send(ThreadResponse thread) async {
    final text = _input.text.trim();
    if (text.isEmpty || _posting) return;
    final target = _replyTo ?? thread.item.post;
    setState(() {
      _posting = true;
      _error = null;
    });
    try {
      await _c.replyText(target, text);
      if (!mounted) return;
      _input.clear();
      setState(() {
        _replyTo = null;
        _replyToAuthor = null;
      });
      _reload();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('reply failed: $e');
        debugPrintStack(stackTrace: st);
      }
      if (mounted) setState(() => _error = 'Could not post your reply. Try again.');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _replyWithVideo(ThreadResponse thread) async {
    final target = _replyTo ?? thread.item.post;
    final author = _replyToAuthor ?? thread.item.actor;
    await showReplySheet(widget.hostContext, parent: target, author: author);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return FutureBuilder<ThreadResponse>(
      future: _future,
      builder: (context, snapshot) {
        final thread = snapshot.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Replies', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                  _IconButton34(
                    tooltip: 'Close',
                    icon: Icn.close,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            if (thread != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SheetContext('@${thread.item.actor.username}: ${snippetOf(thread.item.post)}'),
              ),
            Expanded(child: _body(context, snapshot, thread)),
            if (thread != null) _composer(t, thread),
          ],
        );
      },
    );
  }

  Widget _body(BuildContext context, AsyncSnapshot<ThreadResponse> snapshot, ThreadResponse? thread) {
    final t = context.forest;
    if (snapshot.hasError) {
      final message = snapshot.error is ApiException
          ? (snapshot.error! as ApiException).message
          : 'Could not load the replies.';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center, style: TextStyle(color: t.fg2)),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: _reload, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (thread == null) return const Center(child: CircularProgressIndicator());

    final c = context.watch<FeedController>();
    final byParent = <String, List<ThreadReply>>{};
    for (final r in thread.replies) {
      if (r.post.parentId != null) (byParent[r.post.parentId!] ??= []).add(r);
    }
    final top = byParent[thread.item.post.id] ?? const <ThreadReply>[];
    if (top.isEmpty) {
      return Center(
        child: Text('No replies yet. Start the debate.', style: TextStyle(color: t.fg2)),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      children: [
        for (var i = 0; i < top.length; i++)
          _node(context, c, top[i], byParent, isKid: false, isLast: i == top.length - 1),
        if (thread.total > thread.replies.length)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Showing ${thread.replies.length} of ${thread.total} replies.',
              style: TextStyle(fontSize: 12.5, color: t.fg2),
            ),
          ),
      ],
    );
  }

  Widget _node(
    BuildContext context,
    FeedController c,
    ThreadReply reply,
    Map<String, List<ThreadReply>> byParent, {
    required bool isKid,
    required bool isLast,
  }) {
    final t = context.forest;
    final kids = byParent[reply.post.id] ?? const <ThreadReply>[];
    final post = c.resolve(reply.post);
    final line = t.fg2.withValues(alpha: 0.45);

    final row = Stack(
      children: [
        if (kids.isNotEmpty)
          Positioned(left: 14, top: 46, bottom: 0, width: 2, child: ColoredBox(color: line)),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ForestAvatar(user: reply.actor),
              const SizedBox(width: 10),
              Expanded(child: _content(context, reply, post)),
              _LikeColumn(post: post, onTap: () => c.toggleLike(post)),
            ],
          ),
        ),
      ],
    );

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        if (kids.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Padding(
              padding: const EdgeInsets.only(left: 18),
              child: Column(
                children: [
                  for (var i = 0; i < kids.length; i++)
                    _node(context, c, kids[i], byParent, isKid: true, isLast: i == kids.length - 1),
                ],
              ),
            ),
          ),
      ],
    );
    if (!isKid) return column;

    // Elbow from the parent's line into this node, and the line continuing
    // down to the next sibling.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        column,
        Positioned(
          left: -18,
          top: 0,
          width: 17,
          height: 25,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: line, width: 2),
                bottom: BorderSide(color: line, width: 2),
              ),
              borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(10)),
            ),
          ),
        ),
        if (!isLast) Positioned(left: -18, top: 25, bottom: 0, width: 2, child: ColoredBox(color: line)),
      ],
    );
  }

  Widget _content(BuildContext context, ThreadReply reply, Post post) {
    final t = context.forest;
    final isVideo = post.kind == PostKind.video;
    final playable = isVideo && post.status == PostStatus.ready && post.mediaUrl != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            Text(reply.actor.username, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            if (reply.actor.isBot) const BotTag(),
            Text('· ${relativeTime(post.createdAt)}', style: TextStyle(fontSize: 13, color: t.fg2)),
            StanceChip(stance: post.stance),
          ],
        ),
        const SizedBox(height: 3),
        if (isVideo)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: playable && widget.actions.openViewer != null
                ? () => widget.actions.openViewer!(post, reply.actor)
                : null,
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42 * 16 / 9,
                  decoration: BoxDecoration(
                    color: const Color(0xFF222222),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: playable
                        ? const ForestIcon(Icn.play, size: 14, color: Colors.white)
                        : const Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 16),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    (post.body?.trim().isNotEmpty ?? false) ? post.body!.trim() : 'Video reply',
                    style: const TextStyle(fontSize: 14.5),
                  ),
                ),
              ],
            ),
          )
        else
          Text(post.body ?? '', style: const TextStyle(fontSize: 14.5)),
        TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 2),
            minimumSize: const Size(0, 28),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            alignment: Alignment.centerLeft,
          ),
          onPressed: () => setState(() {
            _replyTo = post;
            _replyToAuthor = reply.actor;
          }),
          child: Text(
            'Reply',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: t.fg2),
          ),
        ),
      ],
    );
  }

  Widget _composer(ForestTokens t, ThreadResponse thread) {
    final target = _replyToAuthor ?? thread.item.actor;
    final me = context.read<FeedController>().me;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: t.border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 4),
              child: Text(_error!, style: TextStyle(fontSize: 12.5, color: t.like)),
            ),
          Row(
            children: [
              if (me != null) ...[ForestAvatar(user: me), const SizedBox(width: 8)],
              Expanded(
                child: TextField(
                  controller: _input,
                  enabled: !_posting,
                  inputFormatters: const [RuneLimitFormatter(maxReplyChars)],
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(thread),
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Reply to @${target.username}…',
                    hintStyle: TextStyle(color: t.fg2),
                    filled: true,
                    fillColor: t.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide(color: t.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide(color: t.accent, width: 2),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide(color: t.border),
                    ),
                  ),
                ),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _input,
                builder: (context, value, _) {
                  final n = runeCount(value.text);
                  return Row(
                    children: [
                      if (n >= 200)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            '$n/$maxReplyChars',
                            style: TextStyle(fontSize: 11.5, color: n >= 260 ? t.like : t.fg2),
                          ),
                        ),
                      TextButton(
                        onPressed: (_posting || value.text.trim().isEmpty) ? null : () => _send(thread),
                        child: Text(
                          'Post',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: (_posting || value.text.trim().isEmpty)
                                ? t.accent.withValues(alpha: 0.4)
                                : t.accent,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              _IconButton34(
                tooltip: 'Reply with video',
                icon: Icn.cam,
                onTap: _posting ? null : () => _replyWithVideo(thread),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Prototype `.ib`: a 34px round icon button.
class _IconButton34 extends StatelessWidget {
  const _IconButton34({required this.tooltip, required this.icon, required this.onTap});

  final String tooltip;
  final String icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Center(
            child: ForestIcon(icon, size: 18, color: onTap == null ? t.fg2 : t.fg),
          ),
        ),
      ),
    );
  }
}

class _LikeColumn extends StatelessWidget {
  const _LikeColumn({required this.post, required this.onTap});

  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final liked = post.likedByMe;
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.only(top: 4, left: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ForestIcon(liked ? Icn.heartFilled : Icn.heart, size: 19, color: liked ? t.like : t.fg2),
            Text(
              '${post.likeCount}',
              style: TextStyle(fontSize: 12, color: liked ? t.like : t.fg2),
            ),
          ],
        ),
      ),
    );
  }
}
