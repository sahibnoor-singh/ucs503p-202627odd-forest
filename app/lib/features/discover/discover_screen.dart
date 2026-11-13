import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:provider/provider.dart';

import '../../data/feed_repository.dart';
import '../../models/video.dart';
import '../../services/api_client.dart';
import '../../theme/forest_theme.dart';
import '../reels/open_video.dart';
import '../reels/reels_repository.dart';
import '../safety/safety_repository.dart';
import 'discover_controller.dart';
import 'discover_search_controller.dart';
import 'discover_tile.dart';
import 'grid_layout.dart';
import 'open_profile.dart';
import 'search_repository.dart';
import 'search_view.dart';

/// The Discover tab: a search box on top and, under it, a grid of posts ranked for this person. Tapping a post opens the
/// full-screen feed on it, and the feed carries on through the grid's order. Pull down to reload; more posts load as the end comes
/// near. Using the search box swaps the grid for recent searches and then results (All, Accounts, Posts).
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key, this.repository, this.searchRepository, this.setFollowing});

  /// For tests; the app uses the shared ones.
  final ReelsRepository? repository;
  final SearchRepository? searchRepository;
  final Future<void> Function(String userId, bool following)? setFollowing;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  late final ReelsRepository _repository = widget.repository ?? context.read<ReelsRepository>();
  late final DiscoverController _controller = DiscoverController(_repository, blocklist: context.read<BlocklistController?>());
  late final SearchRepository _searchRepository = widget.searchRepository ?? SearchRepository(context.read<ApiClient>());
  late final DiscoverSearchController _search = DiscoverSearchController(
    _searchRepository,
    setFollowing: widget.setFollowing ?? (id, following) => context.read<FeedRepository>().setFollowing(id, following),
  );
  final ScrollController _scroll = ScrollController();
  final TextEditingController _field = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// The search box is in use: it has focus or words in it.
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    _controller.addListener(_afterChange);
    _focus.addListener(_syncSearching);
    _controller.refresh();
  }

  void _syncSearching() {
    final now = _focus.hasFocus || _field.text.isNotEmpty;
    if (now != _searching) setState(() => _searching = now);
  }

  void _cancelSearch() {
    _field.clear();
    _search.setQuery('');
    _focus.unfocus();
    _syncSearching();
  }

  void _pickRecent(String query) {
    _field.text = query;
    _field.selection = TextSelection.collapsed(offset: query.length);
    _search.setQuery(query);
    _search.submit();
    _focus.unfocus();
  }

  @override
  void dispose() {
    _controller.removeListener(_afterChange);
    _controller.dispose();
    _search.dispose();
    _focus.dispose();
    _field.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Loads the next page when the end of what is loaded is within a screen or so.
  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter < 900) _controller.loadMore();
  }

  /// A page that is too short to scroll (or tiles still waiting for a block to fill) would never reach the scroll listener.
  void _afterChange() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeLoadMore();
    });
  }

  Future<void> _reload() async {
    await _controller.refresh();
    final problem = _controller.refreshError;
    if (problem != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  /// From the tapped post on, then wherever the grid would have gone next.
  void _open(int index) => pushReels(context, _repository, _controller.videos.sublist(index), cursor: _controller.cursor);

  /// A search result.
  Future<void> _openResult(Video video) async {
    _search.remember();
    _focus.unfocus();
    await openVideoInReels(context, _repository, video);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return PopScope(
      // the back button leaves the search first, and only then the app
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancelSearch();
      },
      child: Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _SearchBar(
                controller: _field,
                focus: _focus,
                searching: _searching,
                onChanged: _search.setQuery,
                onSubmit: _search.submit,
                onCancel: _cancelSearch,
              ),
              Expanded(
                // both stay built, so closing the search returns to the grid exactly where it was scrolled to
                child: IndexedStack(
                  index: _searching ? 1 : 0,
                  children: [
                    _gridBody(),
                    ListenableBuilder(
                      listenable: _search,
                      builder: (context, _) => SearchView(
                        controller: _search,
                        coverUrl: _searchRepository.coverUrl,
                        onOpenPost: _openResult,
                        onOpenAccount: (hit) => openProfile(context, hit, _search),
                        onPickRecent: _pickRecent,
                      ),
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

  Widget _gridBody() {
    return ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            if (_controller.loading) return const _Skeleton();
            if (_controller.error != null) return _Message(text: _controller.error!, action: 'Try again', onAction: _reload);
            if (_controller.videos.isEmpty) {
              return _Message(
                text: 'Nothing to discover yet. When people post their opinions they show up here.',
                action: 'Refresh',
                onAction: _reload,
              );
            }
            return RefreshIndicator(
              onRefresh: _reload,
              child: CustomScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverLayoutBuilder(builder: (context, constraints) => _grid(constraints.crossAxisExtent)),
                  SliverToBoxAdapter(child: _Footer(controller: _controller)),
                ],
              ),
            );
          },
    );
  }

  Widget _grid(double width) {
    final videos = _controller.videos;
    final plan = planGrid(count: videos.length, width: width, complete: !_controller.hasMore);
    return SliverList.builder(
      itemCount: plan.bands.length,
      itemBuilder: (context, i) {
        final band = plan.bands[i];
        return SizedBox(
          height: band.height,
          child: Stack(
            children: [
              for (final tile in band.tiles)
                Positioned.fromRect(
                  key: ValueKey(videos[tile.index].id),
                  rect: tile.rect,
                  child: DiscoverTile(
                    video: videos[tile.index],
                    coverUrl: _repository.coverUrl(videos[tile.index]),
                    big: tile.big,
                    onTap: () => _open(tile.index),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The search box. It looks like Instagram's: a rounded grey field with a magnifier, a clear button once there are words, and a
/// Cancel button while it is in use.
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focus,
    required this.searching,
    required this.onChanged,
    required this.onSubmit,
    required this.onCancel,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool searching;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: controller,
                focusNode: focus,
                onChanged: onChanged,
                onSubmitted: (_) => onSubmit(),
                textInputAction: TextInputAction.search,
                maxLength: 80,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                style: TextStyle(color: t.fg, fontSize: 15),
                cursorColor: t.fg,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'Search posts and people',
                  hintStyle: TextStyle(color: t.fg2),
                  filled: true,
                  fillColor: t.raised,
                  contentPadding: EdgeInsets.zero,
                  prefixIcon: Icon(Icons.search_rounded, color: t.fg2, size: 22),
                  suffixIcon: ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) => controller.text.isEmpty
                        ? const SizedBox.shrink()
                        : IconButton(
                            tooltip: 'Clear',
                            icon: Icon(Icons.cancel_rounded, color: t.fg2, size: 18),
                            onPressed: () {
                              controller.clear();
                              onChanged('');
                            },
                          ),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
          if (searching)
            TextButton(
              onPressed: onCancel,
              child: Text('Cancel', style: TextStyle(color: t.fg, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.controller});

  final DiscoverController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final Widget child;
    if (controller.moreFailed) {
      child = TextButton(onPressed: controller.loadMore, child: const Text('Could not load more. Tap to try again'));
    } else if (controller.hasMore) {
      child = const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2));
    } else {
      child = Text("You've seen everything for now", style: TextStyle(color: t.fg2, fontSize: 13));
    }
    return Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: child));
  }
}

/// Grey tiles in the shape of the real grid while the first page loads.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            final plan = planGrid(count: 20, width: box.maxWidth, complete: true);
            return SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                children: [
                  for (final band in plan.bands)
                    SizedBox(
                      height: band.height,
                      child: Stack(
                        children: [
                          for (final tile in band.tiles) Positioned.fromRect(rect: tile.rect, child: ColoredBox(color: t.raised)),
                        ],
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.action, required this.onAction});

  final String text;
  final String action;
  final VoidCallback onAction;

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
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(action)),
          ],
        ),
      ),
    );
  }
}
