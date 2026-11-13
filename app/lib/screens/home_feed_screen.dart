import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/home/feed_controller.dart';
import '../features/home/feed_item_card.dart';
import '../features/home/suggested_people.dart';
import '../features/today/today_controller.dart';
import '../features/today/today_header.dart';
import '../features/messages/messages_screen.dart';
import '../features/notifications/notifications_controller.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/messages/unread_controller.dart';
import '../features/post/post_menu.dart';
import '../features/reply/reply_sheet.dart';
import '../features/share/share_sheet.dart';
import '../models/post.dart';
import '../features/reels/open_debate_graph.dart';
import '../features/thread/thread_sheet.dart';
import '../features/viewer/post_viewer.dart';
import '../theme/forest_theme.dart';
import '../ui/forest_icon.dart';
import '../ui/reel_focus.dart';

/// Phase-1 "Home": activity from people you follow, Plain mode, built from
/// docs/design/home_prototype.html (PHASE1_HOME_PLAN.md §2). Reads
/// `GET /api/home` through [FeedController].
class HomeFeedScreen extends StatefulWidget {
  const HomeFeedScreen({super.key});

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen> with WidgetsBindingObserver {
  final ReelFocus _focus = ReelFocus();
  late final FeedController _controller;
  StreamSubscription<ToastEvent>? _toastSub;
  bool _backgrounded = false;
  UnreadController? _unread; // looked up in initState: dispose must not look anything up
  NotificationsController? _notes;
  TodayController? _today;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = context.read<FeedController>();
    _unread = context.read<UnreadController?>();
    _notes = context.read<NotificationsController?>();
    _today = context.read<TodayController?>();
    _toastSub = _controller.toasts.listen(_showToast);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.ensureLoaded();
      _today?.load();
      _unread?.start();
      _notes?.start();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unread?.stop();
    _notes?.stop();
    _toastSub?.cancel();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final away = state != AppLifecycleState.resumed;
    if (away == _backgrounded) return;
    _backgrounded = away;
    away ? _focus.suspend() : _focus.resume();
    if (!away) {
      _unread?.refresh();
      _notes?.refreshCount();
    }
  }

  void _showToast(ToastEvent event) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(event.message),
        duration: event.duration ?? Duration(milliseconds: event.actionLabel != null ? 4500 : 2400),
        action: event.actionLabel == null
            ? null
            : SnackBarAction(label: event.actionLabel!, onPressed: event.onAction ?? () {}),
      ));
  }

  CardActions _actions(BuildContext context) => cardActionsFor(context, _controller);

  /// Pull to refresh: the feed, and the question and waiting list above it.
  Future<void> _refreshAll() async {
    unawaited(_today?.load());
    await _controller.refresh();
  }

  bool _onScroll(ScrollNotification n) {
    _focus.scheduleUpdate();
    if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 900) {
      _controller.loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<FeedController>();
    final items = c.items;
    final t = context.forest;

    Widget body;
    if (items.isEmpty && c.loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (items.isEmpty && c.error != null) {
      body = _Message(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load Home',
        text: c.error!,
        button: 'Retry',
        onPressed: c.refresh,
      );
    } else if (items.isEmpty && c.loaded) {
      // A new account follows nobody: offer people to follow (pull to refresh works too).
      body = Column(
        children: [
          const TodayHeader(),
          Expanded(
            child: RefreshIndicator(
              color: t.fg,
              onRefresh: _refreshAll,
              child: SuggestedPeople(onDiscover: () => _goToTab(context, 1)),
            ),
          ),
        ],
      );
    } else {
      body = RefreshIndicator(
        color: t.fg,
        onRefresh: _refreshAll,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: items.length + 2, // the question and what is waiting, the cards, the footer. (No stories row: see docs/STORIES_SPEC.md.)
            itemBuilder: (context, i) {
              if (i == 0) return const TodayHeader();
              final index = i - 1;
              if (index == items.length) {
                return _Footer(
                  loadingMore: c.loadingMore,
                  hasMore: c.hasMore,
                  onDiscover: () => _goToTab(context, 1),
                );
              }
              return Padding(
                // The first card sits right under the stories row.
                padding: EdgeInsets.fromLTRB(8, index == 0 ? 2 : 10, 8, 0), // a clear gap, on a backdrop that differs from the cards
                child: FeedItemCard(
                  key: ValueKey(items[index].post.id),
                  item: items[index],
                  actions: _actions(context),
                ),
              );
            },
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: t.backdrop,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _HomeBar(
              onMessages: () async {
                await openMessages(context);
                _unread?.refresh();
              },
              onNotifications: () async {
                await openNotifications(context);
                _notes?.refreshCount();
              },
            ),
            Expanded(child: ReelFocusScope(focus: _focus, child: body)),
          ],
        ),
      ),
    );
  }

  void _goToTab(BuildContext context, int index) {
    // The tab shell listens for this; Home itself does not own navigation.
    DefaultTabNavigator.of(context)?.call(index);
  }
}

/// What a card can do, wired to [controller]. Home uses it, and so do the pages that show the same cards (a question's answers, a room).
CardActions cardActionsFor(BuildContext context, FeedController controller) => CardActions(
      openViewer: (post, author) => openPostViewer(context, post: post, author: author, actions: cardActionsFor(context, controller)),
      like: controller.toggleLike,
      likeOnly: controller.likeOnly,
      openThread: (post, author) => showThreadSheet(context, postId: post.id, actions: cardActionsFor(context, controller)),
      reply: (post, author) => showReplySheet(context, parent: post, author: author),
      share: (post) => showShareSheet(
        context,
        postId: post.id,
        canSend: post.kind == PostKind.video && post.mediaUrl != null,
        onCopyLink: () => copyShareLink(controller, post),
      ),
      openGraph: (post) => openDebateGraph(context, post),
      more: (post, author, {required authorIsFollowed}) => showItemMenu(
        context,
        post: post,
        author: author,
        authorIsFollowed: authorIsFollowed,
      ),
    );

/// Lets the Home tab ask the tab shell to switch tabs (set up in main.dart).
class DefaultTabNavigator extends InheritedWidget {
  const DefaultTabNavigator({super.key, required this.goTo, required super.child});

  final void Function(int index) goTo;

  static void Function(int index)? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DefaultTabNavigator>()?.goTo;

  @override
  bool updateShouldNotify(DefaultTabNavigator old) => goTo != old.goTo;
}

class _Footer extends StatelessWidget {
  const _Footer({required this.loadingMore, required this.hasMore, required this.onDiscover});

  final bool loadingMore;
  final bool hasMore;
  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    if (loadingMore || hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
        ),
      );
    }
    // Prototype `.caught`: padding 16 16 20, 4px gap, check icon 44, h3 17/700
    // (6px above), 13px line, accent button 15/700 (6px above).
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
      child: Column(
        children: [
          ForestIcon(Icn.check, size: 44, color: t.fg),
          const SizedBox(height: 10),
          const Text(
            'You’re all caught up',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'That is everything from people you follow.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: t.fg2),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDiscover,
            child: Text(
              'Go to Discover',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.text,
    required this.button,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String text;
  final String button;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: t.fg),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: t.fg2)),
            const SizedBox(height: 14),
            OutlinedButton(onPressed: onPressed, child: Text(button)),
          ],
        ),
      ),
    );
  }
}

/// The strip above Home: the app's name, and the paper-plane that opens the messages (with the number of conversations that have
/// something new).
class _HomeBar extends StatelessWidget {
  const _HomeBar({required this.onMessages, required this.onNotifications});

  final VoidCallback onMessages;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final unread = context.watch<UnreadController?>()?.count ?? 0;
    final bell = context.watch<NotificationsController?>()?.unread ?? 0;
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 6),
        child: Row(
          children: [
            Text('FOREST', style: TextStyle(color: t.fg, fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
            const Spacer(),
            Semantics(
              button: true,
              label: bell > 0 ? 'Notifications, $bell new' : 'Notifications',
              excludeSemantics: true,
              child: InkResponse(
                key: const Key('open-notifications'),
                onTap: onNotifications,
                radius: 26,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(Icons.notifications_none_rounded, size: 27, color: t.fg),
                      if (bell > 0)
                        Positioned(
                          right: 6,
                          top: 7,
                          child: Container(
                            key: const Key('notifications-badge'),
                            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: t.like, borderRadius: BorderRadius.circular(9), border: Border.all(color: t.bg, width: 1.5)),
                            child: Text(bell > 9 ? '9+' : '$bell', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Semantics(
              button: true,
              label: unread > 0 ? 'Messages, $unread new' : 'Messages',
              excludeSemantics: true,
              child: InkResponse(
                key: const Key('open-messages'),
                onTap: onMessages,
                radius: 26,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ForestIcon(Icn.send, size: 26, color: t.fg),
                      if (unread > 0)
                        Positioned(
                          right: 4,
                          top: 6,
                          child: Container(
                            key: const Key('messages-badge'),
                            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: t.like, borderRadius: BorderRadius.circular(9), border: Border.all(color: t.bg, width: 1.5)),
                            child: Text(unread > 9 ? '9+' : '$unread', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
