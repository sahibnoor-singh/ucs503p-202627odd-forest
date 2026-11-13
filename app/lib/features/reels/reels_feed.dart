import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard, KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:provider/provider.dart';

import '../../services/app_errors.dart';
import '../../models/video.dart';
import 'reel_controller.dart';
import 'reels_repository.dart';
import 'reply_sheet.dart';
import 'reply_tree_screen.dart';
import 'video_reel.dart';

/// Full-screen Instagram Reels Feed for FORREST:
/// - Vertical scrolling: Whole video smoothly scrolls page-by-page just like Instagram Reels. The pages above the one on screen are
///   the videos watched before it, newest nearest: when a horizontal swipe takes you from a video to one of its replies, the video
///   you left becomes the page above (and the pages that were above it move one further up), so swiping down walks back through
///   what you watched, in the order you watched it. The pages below are videos still to come.
/// - Horizontal swiping: Whole video card slides to navigate FOR and AGAINST perspectives.
/// - Tree View: Selecting any video node plays it right inside the tree.
/// - Single count indicator: Displays one clear FOR/AGAINST indicator on the video metadata card.
class ReelsFeed extends StatefulWidget {
  const ReelsFeed({
    super.key,
    this.repository,
    this.initialDebateRoots,
    this.initialCursor,
    this.startOn,
    this.onClose,
  });

  final ReelsRepository? repository;
  final List<Video>? initialDebateRoots;

  /// With [initialDebateRoots]: where the feed carries on after them (the `nextCursor` of the list they came from).
  final String? initialCursor;

  /// With [initialDebateRoots]: a reply inside the first debate to show first (from a search result), instead of its opening video.
  final Video? startOn;

  /// Shows a back arrow on every reel and calls this when it is tapped (the feed was opened from the Discover grid).
  final VoidCallback? onClose;

  @override
  State<ReelsFeed> createState() => _ReelsFeedState();
}

class _ReelsFeedState extends State<ReelsFeed> with WidgetsBindingObserver {
  /// True when the app went to the background while a reel was playing (so we resume only that case).
  bool _pausedByLifecycle = false;

  late final ReelsRepository _repository;
  late final ValueNotifier<bool> _muteNotifier;
  late final ReelController _reelController;
  final PageController _pageController = PageController();

  /// The vertical list: watched videos, then the one on screen, then those still to come (see the class comment).
  List<_ReelPage> _pages = [];
  int _currentIndex = 0;

  /// True while this screen scrolls itself to keep the same video on screen after a page was put in above it.
  bool _inserting = false;

  /// Bumped on every refresh. A response that was asked for before the refresh is stale and is dropped.
  int _generation = 0;
  String? _nextCursor;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    _repository = widget.repository ?? context.read<ReelsRepository>();
    _muteNotifier = ValueNotifier<bool>(false);
    _reelController = ReelController(muteNotifier: _muteNotifier);

    if (widget.initialDebateRoots != null && widget.initialDebateRoots!.isNotEmpty) {
      _pages = [for (final v in widget.initialDebateRoots!) _ReelPage(root: v)]; // a copy: it grows when more pages load
      final start = widget.startOn;
      if (start != null) _pages.first.active = start;
      _nextCursor = widget.initialCursor;
      _isLoading = false;
      _primeSurrounding(0);
    } else {
      _fetchInitialFeed();
    }
  }

  /// Up and down arrows (or Page Up / Page Down) move between debates on a laptop. Only while this feed is the page in front.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted || !_pageController.hasClients) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    final key = event.logicalKey;
    const curve = Curves.easeOut;
    const duration = Duration(milliseconds: 250);
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.pageDown) {
      _pageController.nextPage(duration: duration, curve: curve);
    } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.pageUp) {
      _pageController.previousPage(duration: duration, curve: curve);
    } else {
      return false;
    }
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Without this the reel keeps talking after the user leaves the app.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _pausedByLifecycle = _reelController.pauseCurrent() || _pausedByLifecycle;
    } else if (state == AppLifecycleState.resumed && _pausedByLifecycle) {
      _pausedByLifecycle = false;
      _reelController.resumeCurrent();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _reelController.dispose();
    _muteNotifier.dispose();
    super.dispose();
  }

  Future<void> _fetchInitialFeed() async {
    final gen = ++_generation;
    // Keep showing the current videos while refreshing; the full-screen spinner is for the very first load only.
    final firstLoad = _pages.isEmpty;
    if (firstLoad) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final page = await _repository.getFeed();
      if (!mounted || gen != _generation) return;

      final roots = page.videos.where((v) => v.parentVideoId == null || v.role == 'PARENT').toList();

      // A new list: the old players belong to other videos.
      _reelController.reset();
      if (_pageController.hasClients) _pageController.jumpToPage(0);
      setState(() {
        _pages = [for (final v in (roots.isNotEmpty ? roots : page.videos)) _ReelPage(root: v)];
        _nextCursor = page.nextCursor;
        _isLoadingMore = false;
        _currentIndex = 0;
        _isLoading = false;
        _errorMessage = null;
      });

      if (_pages.isNotEmpty) {
        _primeSurrounding(0);
      }
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _isLoading = false;
        _errorMessage = friendlyError(e, 'The feed could not be loaded.');
      });
      // On a refresh the old list stays on screen, so say what went wrong instead of failing silently.
      if (!firstLoad) _snack('Could not refresh. ${friendlyError(e, 'Pull down to try again.')}');
    }
  }

  Future<void> _fetchMoreFeed() async {
    if (_isLoadingMore || _nextCursor == null) return;
    _isLoadingMore = true;
    final gen = _generation;

    try {
      final page = await _repository.getFeed(cursor: _nextCursor);
      if (!mounted || gen != _generation) return; // a refresh happened meanwhile: this page belongs to the old list
      final have = _pages.map((p) => p.root.id).toSet(); // also the debates already watched: they are not offered again
      final fresh = page.videos
          .where((v) => v.parentVideoId == null || v.role == 'PARENT')
          .where((v) => !have.contains(v.id)) // never show the same video twice
          .toList();
      setState(() {
        _pages.addAll([for (final v in fresh) _ReelPage(root: v)]);
        _nextCursor = page.nextCursor;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      _isLoadingMore = false; // the next scroll near the end tries again
      _snack('Could not load more videos. ${friendlyError(e, 'Scroll again to retry.')}');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Starts loading a video without letting a failure escape as an unhandled error
  /// (the reel that is on screen shows its own retry; neighbours simply try again when reached).
  void _prime(int index, Video video) {
    _reelController.prime(index, _repository.videoUrl(video), videoId: video.id).catchError((Object _) {});
  }

  void _primeSurrounding(int index) {
    final ids = _pages.map((p) => p.active.id).toList();
    _reelController.activatePage(index, videoIds: ids);

    // The video showing now, the next page, then the page above (the one watched just before)
    for (final i in [index, index + 1, index - 1]) {
      if (i >= 0 && i < _pages.length) _prime(i, _pages[i].active);
    }
  }

  /// Called when the vertical PageView snaps to a new video page
  void _onPageChanged(int index) {
    if (_inserting) return; // the screen moved itself to keep the same video showing; _putAbove does the rest
    if (index >= 0 && index < _pages.length) {
      setState(() {
        _currentIndex = index;
      });
      _primeSurrounding(index);
    }

    if (index >= _pages.length - 2) {
      _fetchMoreFeed();
    }
  }

  /// Silences the feed while a full-screen page or sheet is open (otherwise its sound plays behind a reply
  /// recording), and brings the current reel back when it closes.
  Future<T?> _whileCovered<T>(Future<T?> Function() open) async {
    _reelController.currentController?.pause();
    try {
      return await open();
    } finally {
      if (mounted) _primeSurrounding(_currentIndex); // plays the current reel again
    }
  }

  void _openTree(_ReelPage page) {
    _whileCovered(() => Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ReplyTreeScreen(
          rootVideo: page.root,
          repository: _repository,
          onSelectVideo: (selected) => _selectFromTree(page, selected),
        ),
      ),
    ));
  }

  /// A video was picked in the debate tree: it plays on this page, and the one that was playing goes onto the page above.
  void _selectFromTree(_ReelPage page, Video selected) {
    final at = _pages.indexOf(page);
    if (at < 0 || page.active.id == selected.id) return;
    _putAbove(page, at, page.active, selected);
    // the page itself notices its new video in didUpdateWidget and starts playing it
  }

  /// The page [page] (number [at]) moved from [from] to [to]: asked by the page itself. Returns the page's new number.
  int _onNavigated(_ReelPage page, Video from, Video to) {
    final at = _pages.indexOf(page);
    if (at < 0) return _currentIndex;
    if (page.active.id == to.id) return at; // already done here (a pick from the tree screen)
    return _putAbove(page, at, from, to);
  }

  /// Puts [from] on a new page above [page], which goes on to show [to]. The screen is scrolled by exactly that one page in the same
  /// frame, so the person sees no change: the page they are looking at keeps its key, and so keeps its player and its place.
  int _putAbove(_ReelPage page, int at, Video from, Video to) {
    page.active = to;
    _pages.insert(at, _ReelPage(root: page.root, active: from));
    _reelController.insertSlot(at, newCurrent: at + 1);
    _inserting = true;
    setState(() {
      _currentIndex = at + 1;
    });
    if (_pageController.hasClients) _pageController.jumpToPage(at + 1);
    _inserting = false;
    // the page's own player is swapped by the caller right after this returns; the neighbours are loaded once that has happened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _primeSurrounding(_currentIndex);
    });
    return at + 1;
  }

  /// Scrolls up to the page above (the video watched just before this one).
  void _goUp(_ReelPage page) {
    final at = _pages.indexOf(page);
    if (at <= 0 || !_pageController.hasClients) return;
    _pageController.animateToPage(at - 1, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  void _openReplySheet(Video targetVideo) {
    _whileCovered(() => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReplySheet(
        parentVideo: targetVideo,
        repository: _repository,
        onReplyPosted: (newReply) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(newReply.status == 'ready'
                  ? 'Reply posted! Classified as ${newReply.stance}.'
                  : 'Reply posted. It is still being analysed and will appear soon.'),
              backgroundColor: const Color(0xFF16A34A),
            ),
          );
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF16A34A)),
        ),
      );
    }

    if (_errorMessage != null && _pages.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.white54, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Could not load debate feed\n$_errorMessage',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _fetchInitialFeed,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_pages.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No debate videos available.', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _fetchInitialFeed,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Refresh'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: RefreshIndicator(
        color: const Color(0xFF16A34A),
        onRefresh: _fetchInitialFeed,
        child: PageView.custom(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          // Page snapping on top of edge clamping. Without the clamping parent nothing reports an overscroll at the
          // first page, so pull-to-refresh never fired.
          physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
          allowImplicitScrolling: true,
          onPageChanged: _onPageChanged,
          childrenDelegate: SliverChildBuilderDelegate(
            (context, index) {
              final page = _pages[index];
              return VideoReel(
                // Keyed by the page, not by the video or the debate: a key that changed with the video would rebuild this page on
                // every swipe to a reply and lose its animation and loaded tree. A stable key is also what lets the page stay put
                // when another is put in above it.
                key: ValueKey(page.key),
                rootVideo: page.root,
                activeVideo: page.active,
                index: index,
                reelController: _reelController,
                repository: _repository,
                onOpenTree: () => _openTree(page),
                onOpenReplySheet: () => _openReplySheet(page.active),
                onNavigated: (from, to) => _onNavigated(page, from, to),
                previousVideo: index > 0 ? _pages[index - 1].active : null,
                onGoUp: () => _goUp(page),
                onClose: widget.onClose,
              );
            },
            childCount: _pages.length,
            findChildIndexCallback: (key) {
              if (key is! ValueKey<String>) return null;
              final at = _pages.indexWhere((p) => p.key == key.value);
              return at < 0 ? null : at;
            },
          ),
        ),
      ),
    );
  }
}

/// One page of the vertical list: a debate, and the video of it showing on this page.
class _ReelPage {
  _ReelPage({required this.root, Video? active})
      : active = active ?? root,
        key = 'page_${_made++}';

  static int _made = 0;

  /// Identifies the page for as long as it exists (a page keeps it when others are put in above it).
  final String key;
  final Video root;
  Video active;
}
