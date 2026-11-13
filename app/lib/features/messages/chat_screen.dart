import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user.dart';
import '../../models/video.dart';
import '../../services/api_client.dart';
import '../../theme/forest_theme.dart';
import '../../ui/chips.dart';
import '../../ui/forest_avatar.dart';
import '../reels/open_video.dart';
import '../safety/safety_actions.dart';
import '../reels/reels_repository.dart';
import 'messages_repository.dart';
import 'unread_controller.dart';

/// The videos one friend sent you (and you sent them), oldest at the top. Tap one to watch it. Press and hold, or tap the smiley under
/// it, to react with an emoji; the sender is told. There is nothing to type: only videos and reactions. Looks for new ones every few
/// seconds while it is open.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.person, this.repository, this.reels, this.pollEvery = const Duration(seconds: 4)});

  final User person;
  final MessagesRepository? repository;

  /// For tests; the app uses the shared one.
  final ReelsRepository? reels;
  final Duration pollEvery;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  late final MessagesRepository _repository = widget.repository ?? context.read<MessagesRepository>();
  UnreadController? _unread;
  final ScrollController _scroll = ScrollController();

  List<Message> _messages = const [];
  bool _loaded = false;
  bool _hasMore = false;
  bool _loadingOlder = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _unread = context.read<UnreadController?>();
    _scroll.addListener(_maybeLoadOlder);
    _load();
    _timer = Timer.periodic(widget.pollEvery, (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(quiet: true);
  }

  /// The newest videos, merged into what is already shown (older ones that were loaded stay).
  Future<void> _load({bool quiet = false}) async {
    try {
      final page = await _repository.thread(widget.person.id);
      if (!mounted) return;
      final hadNew = page.messages.any((m) => !m.fromMe && !_messages.any((o) => o.id == m.id));
      setState(() {
        final firstNew = page.messages.isEmpty ? null : page.messages.first.createdAt;
        final inPage = {for (final m in page.messages) m.id};
        final older = firstNew == null ? _messages : _messages.where((m) => m.createdAt.isBefore(firstNew) && !inPage.contains(m.id)).toList();
        _messages = [...older, ...page.messages];
        if (!_loaded) _hasMore = page.hasMore;
        _loaded = true;
        _error = null;
      });
      if (hadNew || !quiet) _markRead();
      _fillScreen();
    } on Object catch (e) {
      if (!mounted || quiet) return;
      if (!_loaded) setState(() => _error = e is ApiException ? e.message : 'Could not load this conversation. Check your connection and try again.');
    }
  }

  void _markRead() {
    unawaited(_repository.markRead(widget.person.id).then((_) => _unread?.refresh()));
  }

  /// A page of videos that does not fill the screen can never be scrolled, so older ones are fetched until it does (or there are none).
  void _fillScreen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _hasMore && _scroll.hasClients && _scroll.position.extentAfter < 300) unawaited(_loadOlder());
    });
  }

  void _maybeLoadOlder() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 300) _loadOlder(); // the list is reversed: "after" is the top
  }

  Future<void> _loadOlder() async {
    if (!_hasMore || _loadingOlder || _messages.isEmpty) return;
    _loadingOlder = true;
    try {
      final page = await _repository.thread(widget.person.id, before: _messages.first.id);
      if (!mounted) return;
      setState(() {
        final have = {for (final m in _messages) m.id};
        _messages = [...page.messages.where((m) => !have.contains(m.id)), ..._messages];
        _hasMore = page.hasMore;
      });
      _fillScreen();
    } on Object {
      // the next scroll tries again
    } finally {
      _loadingOlder = false;
    }
  }

  /// Sets (or, with null, clears) my reaction to [message], shown at once and put back if the server refuses.
  Future<void> _react(Message message, String? emoji) async {
    final before = message.reactions;
    _replace(message.id, (m) => m.withReactions(Reactions(mine: emoji, theirs: before.theirs)));
    try {
      final now = emoji == null ? await _repository.unreact(message.id) : await _repository.react(message.id, emoji);
      _replace(message.id, (m) => m.withReactions(now));
    } on Object catch (e) {
      _replace(message.id, (m) => m.withReactions(before));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : 'Could not react. Try again.')));
    }
  }

  void _replace(String id, Message Function(Message) change) {
    if (!mounted) return;
    setState(() => _messages = [for (final m in _messages) m.id == id ? change(m) : m]);
  }

  Future<void> _pickReaction(Message message) async {
    final t = context.forest;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: t.raised,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final e in messageReactions)
                    InkResponse(
                      key: ValueKey('react-$e'),
                      radius: 28,
                      onTap: () => Navigator.of(sheet).pop(e),
                      child: Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: message.reactions.mine == e ? t.border : null),
                        child: Text(e, style: const TextStyle(fontSize: 28)),
                      ),
                    ),
                ],
              ),
              if (message.reactions.mine != null)
                TextButton(key: const Key('remove-reaction'), onPressed: () => Navigator.of(sheet).pop(''), child: Text('Remove my reaction', style: TextStyle(color: t.like))),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    await _react(message, picked.isEmpty ? null : picked);
  }

  /// Blocks this person and leaves the conversation (it disappears from both inboxes once the server has it).
  Future<void> _blockPerson() async {
    final blocked = await blockPersonFlow(context, userId: widget.person.id, username: widget.person.username);
    if (blocked && mounted) Navigator.of(context).maybePop();
  }

  /// What can be done about one received video: report it, or block the person who sent it.
  Future<void> _moreAbout(Message message) async {
    final t = context.forest;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: t.raised,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            if (message.video != null)
              ListTile(key: const Key('report-video'), leading: Icon(Icons.flag_outlined, color: t.like), title: Text('Report this video', style: TextStyle(color: t.like)), onTap: () => Navigator.of(sheet).pop('report')),
            ListTile(key: const Key('block-person'), leading: Icon(Icons.block_rounded, color: t.like), title: Text('Block @${widget.person.username}', style: TextStyle(color: t.like)), onTap: () => Navigator.of(sheet).pop('block')),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'report' && message.video != null) {
      await reportPostFlow(context, postId: message.video!.id);
    } else if (choice == 'block') {
      await _blockPerson();
    }
  }

  Future<void> _openVideo(Message message) async {
    final video = message.video;
    if (video == null) return;
    if (!message.fromMe) unawaited(_repository.markOpened(message.id));
    final reels = widget.reels ?? context.read<ReelsRepository>();
    await openVideoInReels(context, reels, video);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final person = widget.person;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        leading: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).maybePop()),
        title: Row(
          children: [
            ForestAvatar(user: person, size: 36),
            const SizedBox(width: 10),
            Flexible(child: Text(person.username, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
            if (person.isBot) ...[const SizedBox(width: 6), const BotTag()],
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            key: const Key('chat-menu'),
            tooltip: 'More',
            onSelected: (_) => _blockPerson(),
            itemBuilder: (_) => [PopupMenuItem<String>(key: const Key('menu-block'), value: 'block', child: Text('Block @${person.username}'))],
          ),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: t.border)),
      ),
      body: _body(t),
    );
  }

  Widget _body(ForestTokens t) {
    if (!_loaded && _error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: t.fg2, fontSize: 15)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Try again')),
          ]),
        ),
      );
    }
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ForestAvatar(user: widget.person, size: 72),
            const SizedBox(height: 12),
            Text(widget.person.username, style: TextStyle(color: t.fg, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('No videos yet. Send one with the paper-plane on any post.', textAlign: TextAlign.center, style: TextStyle(color: t.fg2, fontSize: 14)),
          ]),
        ),
      );
    }

    final items = _messages;
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final index = items.length - 1 - i; // newest first, because the list is reversed
        final m = items[index];
        final previous = index > 0 ? items[index - 1] : null;
        final stamp = previous == null || m.createdAt.difference(previous.createdAt) > const Duration(hours: 1);
        return Column(
          key: ValueKey('msg-${m.id}'),
          children: [
            if (stamp) _TimeStamp(m.createdAt),
            _SentVideo(
              message: m,
              coverUrl: m.video == null ? null : _repository.coverUrl(m.video!),
              onOpen: () => _openVideo(m),
              onPickReaction: () => _pickReaction(m),
              onMore: m.fromMe ? null : () => _moreAbout(m),
            ),
          ],
        );
      },
    );
  }
}

class _TimeStamp extends StatelessWidget {
  const _TimeStamp(this.at);

  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final local = at.toLocal();
    final now = DateTime.now();
    final sameDay = local.year == now.year && local.month == now.month && local.day == now.day;
    final clock = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    final label = sameDay ? clock : '${local.day}/${local.month}  $clock';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(label, style: TextStyle(color: context.forest.fg2, fontSize: 11.5)),
    );
  }
}

/// One sent video: on the right when you sent it, on the left when you were sent it, with the reactions under it.
class _SentVideo extends StatelessWidget {
  const _SentVideo({required this.message, required this.coverUrl, required this.onOpen, required this.onPickReaction, this.onMore});

  final Message message;
  final String? coverUrl;
  final VoidCallback onOpen;
  final VoidCallback onPickReaction;

  /// Report or block, for a video somebody else sent.
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final mine = message.fromMe;
    final reactions = message.reactions;
    final reactionText = [?reactions.mine, ?reactions.theirs].join(' ');
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(behavior: HitTestBehavior.opaque, onLongPress: onPickReaction, child: _VideoCard(video: message.video, coverUrl: coverUrl, onOpen: onOpen)),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (reactionText.isNotEmpty)
                  Container(
                    key: const ValueKey('reactions'),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: t.raised, borderRadius: BorderRadius.circular(14)),
                    child: Text(reactionText, style: const TextStyle(fontSize: 15)),
                  ),
                if (message.video != null)
                  Semantics(
                    button: true,
                    label: 'React',
                    excludeSemantics: true,
                    child: InkResponse(
                      key: const ValueKey('add-reaction'),
                      onTap: onPickReaction,
                      radius: 20,
                      child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.add_reaction_outlined, size: 20, color: t.fg2)),
                    ),
                  ),
                if (onMore != null)
                  Semantics(
                    button: true,
                    label: 'More options',
                    excludeSemantics: true,
                    child: InkResponse(
                      key: const ValueKey('video-more'),
                      onTap: onMore,
                      radius: 20,
                      child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.more_horiz_rounded, size: 20, color: t.fg2)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A video that was sent: its picture, a play mark, who posted it and its title. Tap to watch.
class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.video, required this.coverUrl, required this.onOpen});

  final Video? video;
  final String? coverUrl;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final v = video;
    if (v == null) {
      return Container(
        width: 200,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: t.raised, borderRadius: BorderRadius.circular(18)),
        child: Text('This video is not available any more.', style: TextStyle(color: t.fg2, fontSize: 13.5)),
      );
    }
    final title = (v.title ?? '').trim().isNotEmpty ? v.title!.trim() : v.caption.trim();
    return Semantics(
      button: true,
      label: 'Video${title.isEmpty ? '' : ': $title'} by ${v.userName}. Tap to watch',
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('video-card'),
        onTap: onOpen,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: 200,
            height: 284,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: t.raised),
                if (coverUrl != null) Image.network(coverUrl!, fit: BoxFit.cover, cacheWidth: 400, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                const Positioned(left: 0, right: 0, bottom: 0, height: 110, child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xCC000000)])))),
                const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 52, shadows: [Shadow(blurRadius: 8, color: Colors.black54)])),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (title.isNotEmpty) Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700, height: 1.2, shadows: [Shadow(blurRadius: 3, color: Colors.black54)])),
                      const SizedBox(height: 3),
                      Row(children: [
                        Flexible(child: Text('@${v.userName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11.5, shadows: [Shadow(blurRadius: 3, color: Colors.black54)]))),
                        if (v.isBot) ...[const SizedBox(width: 4), const BotTag(compact: true)],
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
