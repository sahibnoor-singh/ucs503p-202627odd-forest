import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/feed_repository.dart';
import '../../models/user.dart';
import '../../services/api_client.dart';
import '../../theme/forest_theme.dart';
import '../../ui/chips.dart';
import '../../ui/forest_avatar.dart';
import '../../ui/format.dart';
import '../../screens/home_feed_screen.dart' show DefaultTabNavigator;
import 'chat_screen.dart';
import 'messages_repository.dart';
import 'slide_route.dart';
import 'unread_controller.dart';

/// Opens the messages page from the right.
Future<void> openMessages(BuildContext context) {
  final goToTab = DefaultTabNavigator.of(context); // the page is pushed above the tabs, so it asks for the tab switch through this
  return Navigator.of(context).push<void>(slideFromRight((_) => MessagesScreen(onDiscover: goToTab == null ? null : () => goToTab(1))));
}

/// The inbox: the friends who sent you videos (or reacted to yours), newest first, with the ones that have something new marked. While
/// there are none it explains how it works and suggests people to follow (when they follow back you can send each other videos). Looks
/// for new things every few seconds while it is open.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key, this.repository, this.feed, this.onDiscover, this.pollEvery = const Duration(seconds: 6)});

  /// For tests; the app uses the shared ones.
  final MessagesRepository? repository;
  final FeedRepository? feed;

  /// Leaves this page and shows the Discover tab.
  final VoidCallback? onDiscover;
  final Duration pollEvery;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  late final MessagesRepository _repository = widget.repository ?? context.read<MessagesRepository>();
  late final FeedRepository? _feed = widget.feed ?? context.read<FeedRepository?>();
  UnreadController? _unread;

  List<Conversation>? _conversations;
  List<User> _toFollow = const [];
  final Set<String> _followed = {};
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _unread = context.read<UnreadController?>();
    _load();
    _timer = Timer.periodic(widget.pollEvery, (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    try {
      final list = await _repository.conversations();
      if (!mounted) return;
      setState(() {
        _conversations = list;
        _error = null;
      });
      _unread?.set(list.where((c) => c.unread > 0).length);
      if (list.isEmpty) unawaited(_loadToFollow());
    } on Object catch (e) {
      if (!mounted || quiet) return;
      if (_conversations == null) setState(() => _error = e is ApiException ? e.message : 'Could not load your messages. Check your connection and try again.');
    }
  }

  Future<void> _loadToFollow() async {
    final feed = _feed;
    if (feed == null) return;
    try {
      final people = [for (final s in await feed.suggestedUsers(limit: 8)) s.user];
      if (mounted) setState(() => _toFollow = people);
    } on Object {
      // the empty state still explains itself without them
    }
  }

  Future<void> _openChat(User person) async {
    await Navigator.of(context).push<void>(slideFromRight((_) => ChatScreen(person: person, repository: _repository)));
    if (mounted) unawaited(_load(quiet: true));
  }

  Future<void> _follow(User user) async {
    final feed = _feed;
    if (feed == null || _followed.contains(user.id)) return;
    setState(() => _followed.add(user.id));
    try {
      await feed.setFollowing(user.id, true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _followed.remove(user.id));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : 'Could not follow @${user.username}.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).maybePop()),
        title: const Text('Messages', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: t.border)),
      ),
      body: _body(t),
    );
  }

  Widget _body(ForestTokens t) {
    final list = _conversations;
    if (list == null && _error != null) {
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
    if (list == null) return const Center(child: CircularProgressIndicator());
    if (list.isEmpty) {
      return _Empty(
        toFollow: _toFollow,
        followed: _followed,
        onFollow: _follow,
        onRefresh: _load,
        onDiscover: () {
          Navigator.of(context).maybePop();
          widget.onDiscover?.call();
        },
      );
    }

    return RefreshIndicator(
      color: t.fg,
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: list.length,
        itemBuilder: (context, i) => _ConversationRow(key: ValueKey('chat-${list[i].id}'), conversation: list[i], onTap: () => _openChat(list[i].person)),
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({super.key, required this.conversation, required this.onTap});

  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final unread = conversation.unread > 0;
    final person = conversation.person;
    return Semantics(
      button: true,
      label: '${person.username}, ${unread ? '${conversation.unread} new, ' : ''}${conversation.preview}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              ForestAvatar(user: person, size: 54),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(child: Text(person.username, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: unread ? FontWeight.w800 : FontWeight.w600))),
                      if (person.isBot) ...[const SizedBox(width: 6), const BotTag()],
                    ]),
                    const SizedBox(height: 2),
                    Text(
                      '${conversation.preview} · ${relativeTime(conversation.lastAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, color: unread ? t.fg : t.fg2, fontWeight: unread ? FontWeight.w700 : FontWeight.w400),
                    ),
                  ],
                ),
              ),
              if (unread) Container(key: ValueKey('unread-${conversation.id}'), width: 10, height: 10, decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.toFollow, required this.followed, required this.onFollow, required this.onRefresh, required this.onDiscover});

  final List<User> toFollow;
  final Set<String> followed;
  final void Function(User user) onFollow;
  final Future<void> Function() onRefresh;
  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return RefreshIndicator(
      color: t.fg,
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
        children: [
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: t.fg, width: 2)),
              child: Icon(Icons.send_outlined, size: 38, color: t.fg),
            ),
          ),
          const SizedBox(height: 16),
          Center(child: Text('No messages yet', style: TextStyle(color: t.fg, fontSize: 20, fontWeight: FontWeight.w800))),
          const SizedBox(height: 6),
          Text(
            'Send a video to a friend with the paper-plane on any post, and see their reactions here. Friends are people you follow who follow you back.',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.fg2, fontSize: 14, height: 1.35),
          ),
          const SizedBox(height: 8),
          Center(child: TextButton(key: const Key('go-discover'), onPressed: onDiscover, child: const Text('Find videos in Discover'))),
          if (toFollow.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('People to follow', style: TextStyle(color: t.fg, fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final u in toFollow)
              _PersonRow(key: ValueKey('tofollow-${u.id}'), user: u, label: followed.contains(u.id) ? 'Following' : 'Follow', filled: !followed.contains(u.id), onPressed: () => onFollow(u)),
          ],
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({super.key, required this.user, required this.label, required this.onPressed, this.filled = true});

  final User user;
  final String label;
  final bool filled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          ForestAvatar(user: user, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(child: Text(user.username, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                  if (user.isBot) ...[const SizedBox(width: 6), const BotTag()],
                ]),
                Text(user.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: t.fg2)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 34,
            child: filled
                ? FilledButton(key: ValueKey('act-${user.id}'), onPressed: onPressed, style: FilledButton.styleFrom(backgroundColor: t.fg, padding: const EdgeInsets.symmetric(horizontal: 16)), child: Text(label, style: TextStyle(color: t.bg, fontWeight: FontWeight.w700)))
                : OutlinedButton(key: ValueKey('act-${user.id}'), onPressed: onPressed, style: OutlinedButton.styleFrom(side: BorderSide(color: t.border), padding: const EdgeInsets.symmetric(horizontal: 14)), child: Text(label, style: TextStyle(color: t.fg, fontWeight: FontWeight.w700))),
          ),
        ],
      ),
    );
  }
}
