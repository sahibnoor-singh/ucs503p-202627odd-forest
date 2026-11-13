import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/feed_item.dart';
import '../../models/post.dart';
import '../../models/user.dart';
import '../../theme/forest_theme.dart';
import '../../ui/action_bar.dart';
import '../../ui/caption_line.dart';
import '../../ui/chips.dart';
import '../../ui/forest_card.dart';
import '../../ui/format.dart';
import '../../ui/post_media.dart';
import '../../ui/quoted_block.dart';
import '../../ui/user_header.dart';
import 'feed_controller.dart';

/// What a card can do. A button whose callback is null is hidden (or shown
/// read-only), never faked.
class CardActions {
  const CardActions({
    this.openViewer,
    this.like,
    this.likeOnly,
    this.openThread,
    this.reply,
    this.share,
    this.openGraph,
    this.more,
  });

  final void Function(Post post, User author)? openViewer;
  final void Function(Post post)? like;

  /// Double tap on a video: like, never un-like.
  final void Function(Post post)? likeOnly;
  final void Function(Post post, User author)? openThread;
  final void Function(Post post, User author)? reply;
  final void Function(Post post)? share;

  /// Tapping the FOR / AGAINST score: the debate graph.
  final void Function(Post post)? openGraph;

  /// `⋯`. [authorIsFollowed] is true for the person whose card this is
  /// (Home only shows people you follow) and unknown (false) for a quoted parent.
  final void Function(Post post, User author, {required bool authorIsFollowed})? more;
}

/// One Home card. Switches on the item type: A (opinion), B (video reply),
/// C (text reply). See PHASE1_HOME_PLAN.md §2.2.
class FeedItemCard extends StatelessWidget {
  const FeedItemCard({super.key, required this.item, required this.actions});

  final FeedItem item;
  final CardActions actions;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<FeedController>();
    return switch (item.type) {
      ItemType.post => _CardA(item: item, actions: actions, c: c),
      ItemType.videoReply => _CardB(item: item, actions: actions, c: c),
      ItemType.textReply => _CardC(item: item, actions: actions, c: c),
    };
  }
}

// ---- shared bits -------------------------------------------------------

/// A text row inside a card: horizontal inset (8 in a card, 5 in the boxed
/// original; the prototype's ".card>*:not(.reel){margin-inline:8px}").
Widget _inset(Widget child, {double h = 8, double top = 0}) => Padding(
      padding: EdgeInsets.fromLTRB(h, top, h, 0),
      child: child,
    );

Widget _media(FeedController c, CardActions a, Post post, User author, Object focusKey) {
  final playable = post.status == PostStatus.ready && post.mediaUrl != null;
  return PostMedia(
    key: ValueKey(focusKey),
    post: post,
    mediaUrl: c.mediaUrl(post),
    coverUrl: c.coverUrl(post),
    muted: c.muted,
    onToggleMute: c.toggleMute,
    focusKey: focusKey,
    onTap: (playable && a.openViewer != null) ? () => a.openViewer!(post, author) : null,
    onDoubleTap: (playable && a.likeOnly != null) ? () => a.likeOnly!(post) : null,
    // Only your own video can be FAILED; the server re-runs it (no new upload).
    onRetry: (post.status == PostStatus.failed && c.isMine(author)) ? () => c.retryVideo(post) : null,
  );
}

Widget _actionBar(CardActions a, Post post, User author, {bool reply = true}) => ActionBar(
      post: post,
      onLike: a.like == null ? null : () => a.like!(post),
      onThread: a.openThread == null ? null : () => a.openThread!(post, author),
      onReply: (reply && a.reply != null) ? () => a.reply!(post, author) : null,
      onShare: a.share == null ? null : () => a.share!(post),
      onScore: a.openGraph == null ? null : () => a.openGraph!(post),
    );

VoidCallback? _more(CardActions a, Post post, User author, {required bool followed}) =>
    a.more == null ? null : () => a.more!(post, author, authorIsFollowed: followed);

String _openingText(Post p) {
  final extra = (p.body?.trim().isNotEmpty ?? false) ? p.body! : (p.summary ?? '');
  return [if (p.title != null) p.title!, if (extra.isNotEmpty) extra].join(' ');
}

// ---- Card A: an opinion --------------------------------------------------

class _CardA extends StatelessWidget {
  const _CardA({required this.item, required this.actions, required this.c});

  final FeedItem item;
  final CardActions actions;
  final FeedController c;

  @override
  Widget build(BuildContext context) {
    final post = c.resolve(item.post);
    final caption = _openingText(post);
    return ForestCard(children: [
      _inset(
        UserHeader(
          user: item.actor,
          sub: '· ${relativeTime(post.createdAt)}',
          onMore: _more(actions, post, item.actor, followed: true),
        ),
        top: 4,
      ),
      _media(c, actions, post, item.actor, '${post.id}#main'),
      if (caption.isNotEmpty) _inset(CaptionLine(user: item.actor, text: caption)),
      _inset(_actionBar(actions, post, item.actor)),
    ]);
  }
}

// ---- Card B: a video reply, parent quoted below ------------------------------

class _CardB extends StatelessWidget {
  const _CardB({required this.item, required this.actions, required this.c});

  final FeedItem item;
  final CardActions actions;
  final FeedController c;

  @override
  Widget build(BuildContext context) {
    final post = c.resolve(item.post);
    final parent = item.parent;
    final caption = post.body?.trim() ?? '';
    return ForestCard(children: [
      _inset(
        UserHeader(
          user: item.actor,
          sub: 'replied · ${relativeTime(post.createdAt)}',
          chip: StanceChip(stance: post.stance),
          onMore: _more(actions, post, item.actor, followed: true),
        ),
        top: 4,
      ),
      _media(c, actions, post, item.actor, '${post.id}#main'),
      if (caption.isNotEmpty) _inset(CaptionLine(user: item.actor, text: caption)),
      _inset(_actionBar(actions, post, item.actor)),
      if (parent != null) _inset(_quote(context, parent)),
    ]);
  }

  Widget _quote(BuildContext context, ParentRef parent) {
    final parentPost = c.resolve(parent.post);
    final isVideo = parentPost.kind == PostKind.video;
    final viewable = isVideo &&
        parentPost.status == PostStatus.ready &&
        parentPost.mediaUrl != null &&
        actions.openViewer != null;
    return QuotedBlock(
      parent: parent,
      parentPost: parentPost,
      coverUrl: c.coverUrl(parentPost),
      root: item.root,
      onTap: () {
        if (viewable) {
          actions.openViewer!(parentPost, parent.actor);
        } else {
          actions.openThread?.call(parentPost, parent.actor);
        }
      },
      onOpenRoot: item.root == null || actions.openThread == null
          ? null
          : () => actions.openThread!(_rootStub(item), item.actor),
      onLike: actions.like == null ? null : () => actions.like!(parentPost),
      onThread: actions.openThread == null
          ? null
          : () => actions.openThread!(parentPost, parent.actor),
      onShare: actions.share == null ? null : () => actions.share!(parentPost),
    );
  }
}

/// The thread sheet needs a post to open; for "in @x's debate" we only know
/// the root's id and title, so build the minimum the sheet displays.
Post _rootStub(FeedItem item) {
  final root = item.root!;
  return Post(
    id: root.id,
    kind: PostKind.video,
    parentId: null,
    rootId: root.id,
    depth: 0,
    title: root.title,
    body: null,
    mediaUrl: null,
    stance: Stance.parent,
    status: PostStatus.ready,
    summary: null,
    createdAt: item.createdAt,
    likeCount: 0,
    likedByMe: false,
    replyCount: 0,
    forCount: 0,
    againstCount: 0,
  );
}

// ---- Card C: a text reply, original shown below -------------------------------

class _CardC extends StatelessWidget {
  const _CardC({required this.item, required this.actions, required this.c});

  final FeedItem item;
  final CardActions actions;
  final FeedController c;

  @override
  Widget build(BuildContext context) {
    final post = c.resolve(item.post);
    final parent = item.parent;
    return ForestCard(children: [
      _inset(
        UserHeader(
          user: item.actor,
          sub: parent == null
              ? 'replied · ${relativeTime(post.createdAt)}'
              : 'replied to @${parent.actor.username} · ${relativeTime(post.createdAt)}',
          chip: StanceChip(stance: post.stance),
          onMore: _more(actions, post, item.actor, followed: true),
        ),
        top: 4,
      ),
      _inset(Text(post.body ?? '', style: const TextStyle(fontSize: 14))),
      _inset(_actionBar(actions, post, item.actor)),
      // 5 dp each side: the inner card must read as a separate card, not as part of the outer border.
      if (parent != null) _inset(_original(context, parent), h: 5),
    ]);
  }

  Widget _original(BuildContext context, ParentRef parent) {
    final t = context.forest;
    final orig = c.resolve(parent.post);
    final isVideo = orig.kind == PostKind.video;
    final root = item.root;
    final caption = isVideo ? _openingText(orig) : (orig.body ?? '');
    return ForestCard(
      raised: true,
      radius: 12,
      gap: 4,
      bottomPad: 6,
      children: [
        _inset(
          UserHeader(
            user: parent.actor,
            sub: '· ${relativeTime(orig.createdAt)}',
            chip: OutlineChip(isVideo ? 'PARENT VIDEO' : 'PARENT REPLY'),
            onMore: _more(actions, orig, parent.actor, followed: false),
            avatarSize: 30,
          ),
          h: 5,
          top: 2,
        ),
        if (isVideo) _media(c, actions, orig, parent.actor, '${item.post.id}#orig'),
        if (caption.isNotEmpty)
          _inset(
            isVideo
                ? CaptionLine(user: parent.actor, text: caption)
                : Text(caption, style: const TextStyle(fontSize: 14)),
            h: 5,
          ),
        _inset(_actionBar(actions, orig, parent.actor), h: 5),
        if (root != null && actions.openThread != null)
          _inset(
            GestureDetector(
              onTap: () => actions.openThread!(_rootStub(item), item.actor),
              child: Text(
                'in @${root.username}’s debate →',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: t.accent),
              ),
            ),
            h: 5,
          ),
      ],
    );
  }
}
