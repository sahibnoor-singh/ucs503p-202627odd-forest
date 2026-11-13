import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/feed_repository.dart';
import '../../services/api_client.dart';
import '../../theme/forest_theme.dart';
import '../../ui/forest_avatar.dart';
import '../../ui/format.dart';
import '../profile/profile_screen.dart';
import '../reels/open_video.dart';
import '../reels/reels_repository.dart';
import 'notifications_controller.dart';
import 'notifications_repository.dart';

Future<void> openNotifications(BuildContext context) =>
    Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()));

/// "@riya followed you from this reel", newest first. The person's picture opens their profile; the reel's cover on the right opens
/// that reel. Opening the screen marks everything read.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final NotificationsController _c;
  // Which lines were unread when the screen opened: they keep their dot while it is open, although everything is marked read at once.
  Set<String> _wasUnread = {};

  @override
  void initState() {
    super.initState();
    _c = context.read<NotificationsController>();
    _wasUnread = {for (final n in _c.items.where((n) => !n.read)) n.id};
    _c.addListener(_onChange);
    // After the first frame: opening tells the controller's listeners, which must not happen while the screen is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _c.open();
      if (mounted) setState(() => _wasUnread = {..._wasUnread, for (final n in _c.items.where((n) => !n.read)) n.id});
    });
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    super.dispose();
  }

  Future<void> _openReel(AppNotification n) async {
    final id = n.postId;
    if (id == null) return;
    final repo = context.read<ReelsRepository>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final debate = await repo.getTree(id);
      if (!mounted) return;
      final video = debate.firstWhere((v) => v.id == id, orElse: () => debate.first);
      await openVideoInReels(context, repo, video);
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : 'Could not open that video. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    Widget body;
    if (_c.loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_c.error != null && _c.items.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_c.error!, textAlign: TextAlign.center, style: TextStyle(color: t.fg2)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _c.open, child: const Text('Try again')),
          ]),
        ),
      );
    } else if (_c.items.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('Nothing yet. When someone follows you, you will see it here.', textAlign: TextAlign.center, style: TextStyle(color: t.fg2, fontSize: 15, height: 1.4)),
        ),
      );
    } else {
      // A line under every notification (the last one too), so each one stands apart.
      body = ListView.builder(
        key: const Key('notifications-list'),
        itemCount: _c.items.length,
        itemBuilder: (_, i) => DecoratedBox(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.border))),
          child: _Row(
            key: ValueKey(_c.items[i].id),
            item: _c.items[i],
            fresh: _wasUnread.contains(_c.items[i].id),
            onProfile: () => openProfileScreen(context, _c.items[i].actor.id),
            onReel: _c.items[i].postId == null ? null : () => _openReel(_c.items[i]),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w800))),
      body: body,
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({super.key, required this.item, required this.fresh, required this.onProfile, required this.onReel});

  final AppNotification item;
  final bool fresh;
  final VoidCallback onProfile;
  final VoidCallback? onReel;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final feed = Provider.of<FeedRepository?>(context, listen: false);
    final cover = item.coverUrl == null ? null : (feed?.mediaUrl(item.coverUrl!) ?? item.coverUrl!);
    return InkWell(
      onTap: onReel ?? onProfile,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(children: [
          GestureDetector(onTap: onProfile, child: ForestAvatar(user: item.actor, size: 46)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.text, style: TextStyle(color: t.fg, fontSize: 14.5, height: 1.3, fontWeight: fresh ? FontWeight.w800 : FontWeight.w500)),
              const SizedBox(height: 2),
              Text(relativeTime(item.createdAt), style: TextStyle(color: t.fg2, fontSize: 12.5)),
            ]),
          ),
          if (fresh) ...[
            Container(key: const Key('unread-dot'), width: 8, height: 8, decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle)),
            const SizedBox(width: 10),
          ],
          if (cover != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(cover, key: const Key('notification-cover'), width: 44, height: 58, fit: BoxFit.cover, errorBuilder: (_, _, _) => _noCover(t)),
            )
          else if (item.postId != null)
            _noCover(t),
        ]),
      ),
    );
  }

  Widget _noCover(ForestTokens t) => Container(
        width: 44,
        height: 58,
        decoration: BoxDecoration(color: t.raised, borderRadius: BorderRadius.circular(8), border: Border.all(color: t.border)),
        child: Icon(Icons.play_arrow_rounded, color: t.fg2),
      );
}
