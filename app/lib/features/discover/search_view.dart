import 'package:flutter/material.dart';

import '../../models/video.dart';
import '../../theme/forest_theme.dart';
import '../../ui/chips.dart';
import '../../ui/forest_avatar.dart';
import 'discover_search_controller.dart';
import 'search_repository.dart';

/// What Discover shows under the search box while it is in use: recent searches before anything is typed, then the results, with
/// All / Accounts / Posts to choose from. A slot for Channels is left out until channels exist.
class SearchView extends StatefulWidget {
  const SearchView({
    super.key,
    required this.controller,
    required this.coverUrl,
    required this.onOpenPost,
    required this.onOpenAccount,
    required this.onPickRecent,
  });

  final DiscoverSearchController controller;
  final String? Function(Video video) coverUrl;
  final void Function(Video video) onOpenPost;
  final void Function(AccountHit hit) onOpenAccount;
  final void Function(String query) onPickRecent;

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 600) widget.controller.loadMore();
  }

  Future<void> _follow(AccountHit hit) async {
    final problem = await widget.controller.toggleFollow(hit);
    if (problem != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (!c.hasQuery) return _Recent(controller: c, onPick: widget.onPickRecent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TypeChips(controller: c),
        Expanded(child: _results(context, c)),
      ],
    );
  }

  Widget _results(BuildContext context, DiscoverSearchController c) {
    if (c.error != null) return _Notice(text: c.error!, action: 'Try again', onAction: c.retry);
    if (c.loading) return const Center(child: CircularProgressIndicator());

    final all = c.type == SearchType.all;
    final showAccounts = c.type != SearchType.posts;
    final showPosts = c.type != SearchType.accounts;
    if (c.accounts.isEmpty && c.posts.isEmpty) {
      return _Notice(text: 'Nothing found for “${c.query}”. Try other words, or check the spelling.');
    }

    // A flat list of rows, so a long result list is built a screenful at a time.
    final rows = <Widget>[
      if (showAccounts && c.accounts.isNotEmpty) ...[
        if (all) const _Heading('Accounts'),
        for (final a in c.accounts)
          _AccountRow(key: ValueKey('account-${a.user.id}'), hit: a, onTap: () => widget.onOpenAccount(a), onFollow: () => _follow(a)),
      ],
      if (showPosts && c.posts.isNotEmpty) ...[
        if (all) const _Heading('Posts'),
        for (final v in c.posts)
          _PostRow(key: ValueKey('post-${v.id}'), video: v, coverUrl: widget.coverUrl(v), onTap: () => widget.onOpenPost(v)),
      ],
      if (c.moreFailed)
        TextButton(onPressed: c.loadMore, child: const Text('Could not load more. Tap to try again'))
      else if (c.loadingMore)
        const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))),
    ];
    return ListView(
      controller: _scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 24),
      children: rows,
    );
  }
}

class _TypeChips extends StatelessWidget {
  const _TypeChips({required this.controller});

  final DiscoverSearchController controller;

  static const _labels = {SearchType.all: 'All', SearchType.accounts: 'Accounts', SearchType.posts: 'Posts'};

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal, // three chips are wider than a very narrow phone
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          for (final type in SearchType.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: ValueKey('search-tab-${type.name}'),
                label: Text(_labels[type]!),
                selected: controller.type == type,
                onSelected: (_) => controller.setType(type),
                showCheckmark: false,
                labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: controller.type == type ? t.bg : t.fg),
                selectedColor: t.fg,
                backgroundColor: t.raised,
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text, style: TextStyle(color: context.forest.fg, fontSize: 15, fontWeight: FontWeight.w800)),
      );
}

String _count(int n, String one) => '$n ${n == 1 ? one : '${one}s'}';

class _AccountRow extends StatelessWidget {
  const _AccountRow({super.key, required this.hit, required this.onTap, required this.onFollow});

  final AccountHit hit;
  final VoidCallback onTap;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final user = hit.user;
    final label = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: hit.followedByMe ? t.fg : t.bg);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ForestAvatar(user: user, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(user.username, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      ),
                      if (user.isBot) ...[const SizedBox(width: 6), const BotTag()],
                    ],
                  ),
                  Text(user.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: t.fg2)),
                  Text('${_count(hit.followerCount, 'follower')} · ${_count(hit.postCount, 'post')}', style: TextStyle(fontSize: 12, color: t.fg2)),
                ],
              ),
            ),
            if (!hit.isMe) ...[
              const SizedBox(width: 10),
              SizedBox(
                height: 34,
                child: hit.followedByMe
                    ? OutlinedButton(
                        key: ValueKey('follow-${user.id}'),
                        onPressed: onFollow,
                        style: OutlinedButton.styleFrom(side: BorderSide(color: t.border), padding: const EdgeInsets.symmetric(horizontal: 14)),
                        child: Text('Following', style: label),
                      )
                    : FilledButton(
                        key: ValueKey('follow-${user.id}'),
                        onPressed: onFollow,
                        style: FilledButton.styleFrom(backgroundColor: t.fg, padding: const EdgeInsets.symmetric(horizontal: 18)),
                        child: Text('Follow', style: label),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PostRow extends StatelessWidget {
  const _PostRow({super.key, required this.video, required this.coverUrl, required this.onTap});

  final Video video;
  final String? coverUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final title = (video.title ?? '').trim().isNotEmpty ? video.title!.trim() : video.caption.trim();
    final reply = video.parentVideoId != null;
    final stance = video.stance == 'FOR' || video.stance == 'AGAINST' ? video.stance : null;
    return Semantics(
      button: true,
      label: '${title.isEmpty ? 'Video' : title} by ${video.userName}${video.isBot ? ' (automated account)' : ''}${reply ? ', a reply' : ''}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 64,
                  height: 86,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: t.raised),
                      if (coverUrl != null)
                        Image.network(coverUrl!, fit: BoxFit.cover, cacheWidth: 192, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                      const Positioned(right: 3, top: 3, child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16, shadows: [Shadow(blurRadius: 4, color: Colors.black54)])),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? 'Video by @${video.userName}' : title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.25),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(child: Text('@${video.userName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: t.fg2))),
                        if (video.isBot) ...[const SizedBox(width: 6), const BotTag()],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        if (reply)
                          Text(stance == null ? 'Reply' : 'Reply · $stance', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: stance == 'FOR' ? t.forStance : stance == 'AGAINST' ? t.againstStance : t.fg2))
                        else if (video.forCount + video.againstCount > 0)
                          Text('${video.forCount} for · ${video.againstCount} against', style: TextStyle(fontSize: 12, color: t.fg2)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Recent extends StatelessWidget {
  const _Recent({required this.controller, required this.onPick});

  final DiscoverSearchController controller;
  final void Function(String query) onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final list = controller.recent;
    if (list.isEmpty) {
      return _Notice(text: 'Search for posts, debates and people.\nWords from titles, captions and what is said in videos all count.');
    }
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(
            children: [
              Expanded(child: Text('Recent', style: TextStyle(color: t.fg, fontSize: 15, fontWeight: FontWeight.w800))),
              TextButton(onPressed: controller.clearRecents, child: const Text('Clear all')),
            ],
          ),
        ),
        for (final q in list)
          ListTile(
            key: ValueKey('recent-$q'),
            dense: true,
            leading: Icon(Icons.history_rounded, color: t.fg2),
            title: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: 'Remove "$q"',
              icon: Icon(Icons.close_rounded, size: 18, color: t.fg2),
              onPressed: () => controller.removeRecent(q),
            ),
            onTap: () => onPick(q),
          ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: t.fg2, fontSize: 15, height: 1.35)),
            if (action != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(action!)),
            ],
          ],
        ),
      ),
    );
  }
}
