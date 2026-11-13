import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HardwareKeyboard, KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../models/video.dart';
import '../../services/analytics.dart';
import '../../services/app_errors.dart';
import '../../services/api_client.dart';
import '../../services/caption_service.dart';
import '../../ui/caption_overlay.dart';
import '../../ui/seek_bar.dart';
import '../../utils/stance.dart';
import '../../services/public_links.dart';
import '../../services/session.dart';
import '../home/feed_controller.dart';
import '../profile/profile_screen.dart';
import '../thread/thread_sheet.dart';
import '../../screens/home_feed_screen.dart' show cardActionsFor;
import '../safety/safety_actions.dart';
import '../share/share_sheet.dart';
import 'reel_controller.dart';
import 'reel_overlay.dart';
import 'sides_heard.dart';
import 'reels_repository.dart';

/// Fullscreen player widget for a single debate tree page in the FORREST feed.
/// Vertical scroll: Handled by parent PageView with native Instagram Reels physics.
/// Horizontal drag: Slides the entire video card to navigate perspectives (Left: FOR, Right: AGAINST).
class VideoReel extends StatefulWidget {
  const VideoReel({
    super.key,
    required this.rootVideo,
    required this.index,
    required this.reelController,
    required this.repository,
    required this.onOpenTree,
    required this.onOpenReplySheet,
    this.activeVideo,
    this.onNavigated,
    this.previousVideo,
    this.onGoUp,
    this.onClose,
  });

  final Video rootVideo;
  final int index;
  final ReelController reelController;
  final ReelsRepository repository;
  final VoidCallback onOpenTree;
  final VoidCallback onOpenReplySheet;
  final Video? activeVideo;

  /// This page moved from [from] to [to] (a swipe to a FOR / AGAINST reply, or back to the parent). The feed puts [from] on the
  /// page above, so swiping down returns to it, and answers with this page's new number (it is one more now). Without a feed
  /// (tests) the page stays where it is.
  final int Function(Video from, Video to)? onNavigated;

  /// The video on the page above this one (the one watched just before), if any.
  final Video? previousVideo;

  /// Scrolls to the page above.
  final VoidCallback? onGoUp;

  /// Leaves the feed (opened from the Discover grid). Shown as a back arrow at the top left.
  final VoidCallback? onClose;

  @override
  State<VideoReel> createState() => _VideoReelState();
}

class _VideoReelState extends State<VideoReel> with SingleTickerProviderStateMixin {
  late Video _currentVideo;
  late Video _rootVideo;
  List<Video> _treeNodes = [];
  List<Video> _forVideos = [];
  List<Video> _againstVideos = [];

  int _forIndex = 0;
  int _againstIndex = 0;
  int _forCount = 0;
  int _againstCount = 0;

  // Horizontal drag state (slides the WHOLE video horizontally)
  // The finger's sideways offset. A ValueNotifier, not setState: only the sliding layer listens to it, so a swipe
  // moves the picture without rebuilding the video, the overlay and the buttons on every finger move.
  final ValueNotifier<double> _drag = ValueNotifier<double>(0.0);
  double get _dragOffset => _drag.value;
  set _dragOffset(double v) => _drag.value = v;
  static const double _threshold = 70.0;
  late AnimationController _springController;
  late Animation<double> _springAnimation;
  bool _isNavigating = false;

  bool _failed = false;

  /// The whole title is showing ("more" was tapped). Closes when the video is tapped, or another video comes in.
  bool _titleExpanded = false;
  bool _showPauseIndicator = false;
  Timer? _viewTimer;
  bool _viewRecorded = false;

  /// Is this the reel on screen? The feed keeps neighbours built (pre-loaded), and those must not count as
  /// watched: that would teach the recommender about videos nobody saw.
  bool _isActive = false;
  DateTime? _loadTime;
  String? _emptyFeedbackMessage;
  Timer? _feedbackTimer;

  @override
  void initState() {
    super.initState();
    _rootVideo = widget.rootVideo;
    _currentVideo = widget.activeVideo ?? widget.rootVideo;
    _forCount = _currentVideo.forCount;
    _againstCount = _currentVideo.againstCount;

    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(() {
        _dragOffset = _springAnimation.value;
      });

    _loadTreeAndReplies();
    _loadCurrentVideo();
    _isActive = widget.reelController.currentIndex == widget.index;
    if (_isActive) _beginWatching();
    widget.reelController.addListener(_onActivePageChanged);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  void _beginWatching() {
    _loadTime = DateTime.now();
    _startViewTimer();
  }

  /// The feed tells us when the visible page changes: start counting when we become visible, and when we
  /// stop being visible after only a moment, record that as a skip.
  void _onActivePageChanged() {
    final nowActive = widget.reelController.currentIndex == widget.index;
    if (nowActive == _isActive) return;
    _isActive = nowActive;
    if (nowActive) {
      _beginWatching();
    } else {
      _recordSkipIfShortWatch();
      _viewTimer?.cancel();
      _loadTime = null;
    }
  }

  @override
  void didUpdateWidget(covariant VideoReel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // This page moved in the list (a page was put in above it): it may have become, or stopped being, the one on screen.
    if (oldWidget.index != widget.index) _onActivePageChanged();
    if (widget.activeVideo != null && widget.activeVideo!.id != _currentVideo.id) {
      _switchToVideo(widget.activeVideo!);
    } else if (oldWidget.rootVideo.id != widget.rootVideo.id) {
      _rootVideo = widget.rootVideo;
      _currentVideo = widget.rootVideo;
      _loadTreeAndReplies();
      _loadCurrentVideo();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    widget.reelController.removeListener(_onActivePageChanged);
    if (_isActive) _recordSkipIfShortWatch();
    _viewTimer?.cancel();
    _feedbackTimer?.cancel();
    _springController.dispose();
    _drag.dispose();
    super.dispose();
  }

  Future<void> _loadTreeAndReplies() async {
    try {
      final nodes = await widget.repository.getTree(_rootVideo.id);
      if (!mounted) return;
      setState(() {
        _treeNodes = nodes;
        _updateDirectRepliesForCurrent();
      });
    } catch (_) {
      _updateDirectRepliesForCurrent();
    }
  }

  void _updateDirectRepliesForCurrent() async {
    // Filter direct replies belonging to THIS video
    var fors = _treeNodes
        .where((v) => v.parentVideoId == _currentVideo.id && v.stance.toUpperCase() == 'FOR')
        .toList(growable: false);
    var againsts = _treeNodes
        .where((v) => v.parentVideoId == _currentVideo.id && v.stance.toUpperCase() == 'AGAINST')
        .toList(growable: false);

    // If root video, also include any tree-level FOR / AGAINST
    if (fors.isEmpty && _currentVideo.id == _rootVideo.id) {
      fors = _treeNodes
          .where((v) => v.stance.toUpperCase() == 'FOR' && v.id != _rootVideo.id)
          .toList(growable: false);
    }
    if (againsts.isEmpty && _currentVideo.id == _rootVideo.id) {
      againsts = _treeNodes
          .where((v) => v.stance.toUpperCase() == 'AGAINST' && v.id != _rootVideo.id)
          .toList(growable: false);
    }

    if (mounted) {
      setState(() {
        _forVideos = fors;
        _againstVideos = againsts;
        _forCount = fors.isNotEmpty ? fors.length : _currentVideo.forCount;
        _againstCount = againsts.isNotEmpty ? againsts.length : _currentVideo.againstCount;
      });
    }

    // Also fetch direct replies from backend in background to ensure fresh counts
    final forVideoId = _currentVideo.id;
    try {
      final both = await Future.wait([
        widget.repository.getReplies(forVideoId, side: 'FOR'),
        widget.repository.getReplies(forVideoId, side: 'AGAINST'),
      ]);
      final liveFors = both[0];
      final liveAgainsts = both[1];
      // The person may have swiped to another video while this was loading: never paint its answer here.
      if (mounted && _currentVideo.id == forVideoId && (liveFors.isNotEmpty || liveAgainsts.isNotEmpty)) {
        setState(() {
          if (liveFors.isNotEmpty) _forVideos = liveFors;
          if (liveAgainsts.isNotEmpty) _againstVideos = liveAgainsts;
          _forCount = _forVideos.length;
          _againstCount = _againstVideos.length;
        });
      }
    } catch (_) {}
  }

  void _loadCurrentVideo() {
    final url = widget.repository.videoUrl(_currentVideo);
    widget.reelController.prime(widget.index, url, videoId: _currentVideo.id).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  void _recordSkipIfShortWatch() {
    if (_loadTime != null && !_viewRecorded) {
      final elapsed = DateTime.now().difference(_loadTime!).inMilliseconds;
      if (elapsed < 2500) {
        widget.repository.recordInteraction(
          videoId: _currentVideo.id,
          watchDurationMs: elapsed,
          skipped: true,
          completed: false,
        );
      }
    }
  }

  void _startViewTimer() {
    _viewTimer?.cancel();
    _viewRecorded = false;
    _viewTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isActive && !_viewRecorded) {
        _viewRecorded = true;
        widget.repository.recordInteraction(
          videoId: _currentVideo.id,
          watchDurationMs: 3000,
          completed: false,
        );
        _noteSideHeard();
      }
    });
  }

  /// This video has been watched for a few seconds: if it is a FOR or AGAINST reply, that side of the debate counts as heard.
  void _noteSideHeard() {
    final becameBoth = widget.reelController.sidesHeard.record(_rootVideo.id, _currentVideo.stance);
    if (!mounted) return;
    setState(() {});
    if (becameBoth) {
      try {
        context.read<Analytics>().track('both_sides_heard');
      } on ProviderNotFoundException {
        // no analytics in this build (tests): nothing to tell
      }
    }
  }

  /// The "heard both sides" line: only on debates that actually have replies on both sides.
  SidesNote? _sidesNote() {
    final both = _treeNodes.any((v) => v.id != _rootVideo.id && v.stance.toUpperCase() == 'FOR') &&
        _treeNodes.any((v) => v.id != _rootVideo.id && v.stance.toUpperCase() == 'AGAINST');
    if (!both && !(_forCount > 0 && _againstCount > 0)) return null;
    return widget.reelController.sidesHeard.noteFor(_rootVideo.id, onRoot: _currentVideo.id == _rootVideo.id);
  }

  /// Is this the viewer's own video?
  bool get _isMine {
    final me = Provider.of<Session?>(context, listen: false)?.user?.id;
    return me != null && me == _currentVideo.authorId;
  }

  bool _isFollowing() => widget.reelController.followState[_currentVideo.authorId] ?? _currentVideo.authorFollowed;

  /// Follow (or, tapped again, unfollow) the author from this reel. The author is told "@you followed you from this reel", with this
  /// video attached. The change shows at once and is undone if the server says no.
  Future<void> _toggleFollow() async {
    final id = _currentVideo.authorId;
    if (id == null) return;
    final want = !_isFollowing();
    final states = widget.reelController.followState;
    final before = states[id];
    setState(() => states[id] = want);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final api = context.read<ApiClient>();
      if (want) {
        await api.sendJson('POST', '/api/users/$id/follow', body: {'fromPostId': _currentVideo.id});
      } else {
        await api.sendJson('DELETE', '/api/users/$id/follow');
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        if (before == null) {
          states.remove(id);
        } else {
          states[id] = before;
        }
      });
      messenger?.showSnackBar(SnackBar(content: Text(friendlyError(e, want ? 'Could not follow right now. Try again.' : 'Could not unfollow right now. Try again.'))));
    }
  }

  /// The written replies to this video, in the same sheet Home uses. Only where the app has the Home controller (it always does, bar tests).
  Future<void> _openComments() async {
    final feed = Provider.of<FeedController?>(context, listen: false);
    if (feed == null) return;
    final wasPlaying = widget.reelController.pauseCurrent();
    await showThreadSheet(context, postId: _currentVideo.id, actions: cardActionsFor(context, feed));
    if (mounted && wasPlaying) widget.reelController.resumeCurrent();
  }

  /// Opens the author's profile on top of the feed; the video is silent meanwhile and carries on when the person comes back.
  Future<void> _openAuthor() async {
    final id = _currentVideo.authorId;
    if (id == null) return;
    final wasPlaying = widget.reelController.pauseCurrent();
    await openProfileScreen(context, id);
    if (mounted && wasPlaying) widget.reelController.resumeCurrent();
  }

  /// A laptop has no finger: the arrow keys do what the swipes do (left: FOR, right: AGAINST or back to the parent), and the
  /// space bar pauses. Only the reel on screen listens, and only while no other page or sheet is open above the feed.
  bool _onKey(KeyEvent event) {
    if (!_isActive || event is! KeyDownEvent || !mounted) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _navigateToFor();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _navigateToAgainst();
    } else if (key == LogicalKeyboardKey.space) {
      _handleTap();
    } else {
      return false;
    }
    return true;
  }

  void _showFeedback(String message) {
    _feedbackTimer?.cancel();
    setState(() => _emptyFeedbackMessage = message);
    _feedbackTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => _emptyFeedbackMessage = null);
    });
  }

  // --- Horizontal Drag Handlers (Whole video card slides horizontally) ---
  void _onHorizontalDragStart(DragStartDetails details) {
    if (_springController.isAnimating || _isNavigating) return;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_springController.isAnimating || _isNavigating) return;
    final dx = details.primaryDelta ?? 0;
    _dragOffset = (_dragOffset + dx).clamp(-160.0, 160.0);
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_isNavigating) {
      _springBack();
      return;
    }

    if (_dragOffset <= -_threshold) {
      // Swipe Left -> Most relevant FOR reply
      _navigateToFor();
    } else if (_dragOffset >= _threshold) {
      // Swipe Right -> Most relevant AGAINST reply (or return to parent if in reply)
      _navigateToAgainst();
    } else {
      _springBack();
    }
  }

  void _springBack() {
    _springAnimation = Tween<double>(
      begin: _dragOffset,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _springController,
      curve: Curves.easeOutCubic,
    ));
    _springController.forward(from: 0.0);
  }

  void _navigateToFor() {
    if (_forVideos.isEmpty) {
      _springBack();
      _showFeedback('No FOR perspective in this debate tree yet');
      return;
    }

    final target = _forVideos[_forIndex % _forVideos.length];
    _forIndex++;

    _isNavigating = true;
    _springBack();
    _switchToVideo(target);

    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _isNavigating = false;
    });
  }

  void _navigateToAgainst() {
    // On a reply, swiping right goes back to what it answers (the same as the "Parent video" button)
    if (_currentVideo.id != _rootVideo.id) {
      _isNavigating = true;
      _springBack();
      _goToParent();
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _isNavigating = false;
      });
      return;
    }

    if (_againstVideos.isEmpty) {
      _springBack();
      _showFeedback('No AGAINST perspective in this debate tree yet');
      return;
    }

    final target = _againstVideos[_againstIndex % _againstVideos.length];
    _againstIndex++;

    _isNavigating = true;
    _springBack();
    _switchToVideo(target);

    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _isNavigating = false;
    });
  }

  void _returnToRoot() {
    if (_currentVideo.id == _rootVideo.id) return;
    _switchToVideo(_rootVideo);
  }

  /// The video this one answers: the page above when that is it (the person came from there), else it is brought back here.
  void _goToParent() {
    final parentId = _currentVideo.parentVideoId;
    if (parentId == null) return;
    if (widget.previousVideo?.id == parentId && widget.onGoUp != null) {
      widget.onGoUp!();
      return;
    }
    final parent = _treeNodes.where((v) => v.id == parentId).firstOrNull ?? _rootVideo;
    _switchToVideo(parent);
  }

  /// How many answers deep the playing video is (1 for the opinion itself), read from the debate loaded for this page.
  int _depth() {
    var depth = 1;
    var at = _currentVideo;
    final byId = {for (final v in _treeNodes) v.id: v};
    while (at.parentVideoId != null && depth < 50) {
      final parent = byId[at.parentVideoId];
      if (parent == null) return depth + 1;
      at = parent;
      depth++;
    }
    return depth;
  }

  void _switchToVideo(Video nextVideo) {
    _recordSkipIfShortWatch();
    _loadTime = DateTime.now();

    // Remember where the person was in the video being left, so coming back to it carries on from there.
    final leaving = _currentVideo;
    final position = widget.reelController.currentController?.value.position;
    if (position != null && widget.reelController.currentIndex == widget.index) widget.reelController.savePosition(leaving.id, position);
    // The video being left goes onto the page above; this page's number changes with that, before its player is replaced.
    final slot = widget.onNavigated?.call(leaving, nextVideo) ?? widget.index;

    setState(() {
      _currentVideo = nextVideo;
      _titleExpanded = false;
      _forCount = nextVideo.forCount;
      _againstCount = nextVideo.againstCount;
      _failed = false;
    });

    final url = widget.repository.videoUrl(nextVideo);
    widget.reelController.replaceAndPlay(slot, url, videoId: nextVideo.id).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });

    _updateDirectRepliesForCurrent();
    _startViewTimer();
  }

  void _handleLike() async {
    final willLike = !_currentVideo.isLiked;
    final newCount = willLike
        ? _currentVideo.likeCount + 1
        : (_currentVideo.likeCount - 1).clamp(0, 999999);

    setState(() {
      _currentVideo = _currentVideo.copyWith(isLiked: willLike, likeCount: newCount);
    });

    final likedId = _currentVideo.id;
    try {
      final actual = willLike
          ? await widget.repository.setLike(likedId)
          : await widget.repository.deleteLike(likedId);
      if (mounted && _currentVideo.id == likedId) {
        setState(() => _currentVideo = _currentVideo.copyWith(likeCount: actual));
      }
    } on Object catch (error) {
      // The server did not take it: put the heart back instead of pretending.
      if (mounted && _currentVideo.id == likedId) {
        setState(() => _currentVideo = _currentVideo.copyWith(
              isLiked: !willLike,
              likeCount: willLike ? _currentVideo.likeCount - 1 : _currentVideo.likeCount + 1,
            ));
        _showFeedback(error is ApiException ? error.message : 'Could not save your like.');
      }
    }
  }

  /// The paper-plane: send this video to a friend (or copy its link). The video pauses while the sheet is open.
  Future<void> _handleShare() async {
    final video = _currentVideo;
    final paused = widget.reelController.pauseCurrent();
    try {
      await showShareSheet(
        context,
        postId: video.id,
        canSend: true,
        onCopyLink: () {
          Clipboard.setData(ClipboardData(text: PublicLinks.debate(video.id)));
          _showFeedback('Link copied');
        },
      );
    } finally {
      if (paused && mounted) widget.reelController.resumeCurrent();
    }
  }

  /// Blocking is offered for other people's videos only (the server refuses it for your own), and when the server told us who made it.
  bool get _canBlockAuthor {
    final author = _currentVideo.authorId;
    if (author == null) return false;
    final me = context.read<Session?>()?.user;
    return me == null || me.id != author;
  }

  void _handleMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: Color(0xFFDC2626)),
                title: const Text('Report video', style: TextStyle(color: Color(0xFFDC2626))),
                onTap: () {
                  Navigator.pop(ctx);
                  reportPostFlow(context, postId: _currentVideo.id); // asks why, then says what happened (even "you can't report your own post")
                },
              ),
              if (_canBlockAuthor)
                ListTile(
                  key: const Key('reel-block'),
                  leading: const Icon(Icons.block_rounded, color: Color(0xFFDC2626)),
                  title: Text('Block @${_currentVideo.userName}', style: const TextStyle(color: Color(0xFFDC2626))),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final blocked = await blockPersonFlow(context, userId: _currentVideo.authorId!, username: _currentVideo.userName);
                    if (blocked && mounted) widget.onClose?.call();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('Not interested in this debate'),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.repository.recordInteraction(
                    videoId: _currentVideo.id,
                    skipped: true,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Marked as not interested.')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.refresh_rounded),
                title: const Text('Reset recommendation interests'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await widget.repository.resetUserProfile();
                  messenger.showSnackBar(SnackBar(
                    content: Text(ok ? 'Personalization preferences reset.' : 'Could not reset. Check your connection.'),
                  ));
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _handleTap() {
    // While the long title is open, a tap on the picture only closes it (it should not also pause the video).
    if (_titleExpanded) {
      setState(() => _titleExpanded = false);
      return;
    }
    widget.reelController.togglePlayPause();
    setState(() => _showPauseIndicator = true);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _showPauseIndicator = false);
    });
  }

  /// The coloured hint behind the picture while it is dragged sideways ("FOR perspective" / "return to parent" ...).
  Widget _peekPanel(double drag) {
    final isDraggingLeft = drag < 0;
    final isDraggingRight = drag > 0;
    final revealRatio = (drag.abs() / _threshold).clamp(0.0, 1.0);
    final hasTarget = isDraggingLeft ? _forVideos.isNotEmpty : (_currentVideo.id != _rootVideo.id || _againstVideos.isNotEmpty);
    return Container(
                    color: isDraggingLeft
                        ? (hasTarget
                            ? StanceColors.forBg.withValues(alpha: 0.95 * revealRatio)
                            : const Color(0xFFF3F4F6).withValues(alpha: 0.95 * revealRatio))
                        : (hasTarget
                            ? StanceColors.againstBg.withValues(alpha: 0.95 * revealRatio)
                            : const Color(0xFFF3F4F6).withValues(alpha: 0.95 * revealRatio)),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    alignment: isDraggingLeft ? Alignment.centerRight : Alignment.centerLeft,
                    child: AnimatedOpacity(
                      opacity: revealRatio,
                      duration: const Duration(milliseconds: 60),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isDraggingRight) ...[
                            Icon(
                              hasTarget ? Icons.arrow_back_rounded : Icons.info_outline_rounded,
                              color: hasTarget ? StanceColors.againstText : const Color(0xFF6B7280),
                              size: 28,
                            ),
                            const SizedBox(width: 10),
                          ],
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment:
                                isDraggingLeft ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              Text(
                                isDraggingLeft
                                    ? (hasTarget ? 'FOR PERSPECTIVE' : 'NO FOR REPLIES')
                                    : (hasTarget ? (_currentVideo.id != _rootVideo.id ? 'RETURN TO PARENT' : 'AGAINST PERSPECTIVE') : 'NO AGAINST REPLIES'),
                                style: TextStyle(
                                  color: isDraggingLeft
                                      ? (hasTarget ? StanceColors.forText : const Color(0xFF4B5563))
                                      : (hasTarget ? StanceColors.againstText : const Color(0xFF4B5563)),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              if (hasTarget)
                                Text(
                                  isDraggingLeft
                                      ? (_forVideos.isNotEmpty ? '@${_forVideos.first.userName}' : 'Connected argument')
                                      : (_currentVideo.id != _rootVideo.id ? '@${_rootVideo.userName}' : (_againstVideos.isNotEmpty ? '@${_againstVideos.first.userName}' : 'Counter argument')),
                                  style: TextStyle(
                                    color: isDraggingLeft
                                        ? StanceColors.forText.withValues(alpha: 0.8)
                                        : StanceColors.againstText.withValues(alpha: 0.8),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                          if (isDraggingLeft) ...[
                            const SizedBox(width: 10),
                            Icon(
                              hasTarget ? Icons.arrow_forward_rounded : Icons.info_outline_rounded,
                              color: hasTarget ? StanceColors.forText : const Color(0xFF6B7280),
                              size: 28,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.reelController,
      builder: (context, _) {
        final controller = widget.reelController.controllerFor(widget.index);
        final isInitialized = controller != null && controller.value.isInitialized;
        final captionService = Provider.of<CaptionService?>(context);
        final isPlaying = isInitialized && controller.value.isPlaying;
        final isAudioOnly = isInitialized &&
            (controller.value.size.width <= 0 || controller.value.size.height <= 0);

        return Container(
          color: Colors.black,
          width: double.infinity,
          height: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Peek panels behind sliding video (visible during horizontal drag). Listens to the drag on its own.
              Positioned.fill(
                child: IgnorePointer(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _drag,
                    builder: (context, drag, _) => drag == 0 ? const SizedBox.shrink() : _peekPanel(drag),
                  ),
                ),
              ),

              // 2. The WHOLE VIDEO CARD slides horizontally with finger!
              // (Vertical scrolling is handled seamlessly by parent PageView, just like Instagram!)
              ValueListenableBuilder<double>(
                valueListenable: _drag,
                builder: (context, drag, child) => Transform.translate(offset: Offset(drag, 0), child: child),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _handleTap,
                  onHorizontalDragStart: _onHorizontalDragStart,
                  onHorizontalDragUpdate: _onHorizontalDragUpdate,
                  onHorizontalDragEnd: _onHorizontalDragEnd,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Video Player / Media View
                      if (isInitialized && !isAudioOnly)
                        // The whole video is always shown, never cropped: black bars fill the rest.
                        FittedBox(
                          fit: BoxFit.contain,
                          child: SizedBox(
                            width: controller.value.size.width,
                            height: controller.value.size.height,
                            child: VideoPlayer(controller),
                          ),
                        )
                      else if (isInitialized && isAudioOnly)
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.graphic_eq_rounded, color: Colors.white54, size: 48),
                              const SizedBox(height: 8),
                              Text(
                                _currentVideo.title ?? 'Audio debate opinion',
                                style: const TextStyle(color: Colors.white70, fontSize: 16),
                              ),
                            ],
                          ),
                        )
                      else if (_failed)
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Colors.white38, size: 44),
                              const SizedBox(height: 12),
                              const Text(
                                "Couldn't load this video",
                                style: TextStyle(color: Colors.white70, fontSize: 14),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton(
                                onPressed: () {
                                  setState(() => _failed = false);
                                  _loadCurrentVideo();
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white38),
                                ),
                                child: const Text('Tap to retry'),
                              ),
                            ],
                          ),
                        )
                      else
                        Stack(
                          fit: StackFit.expand,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    stanceBgColor(_currentVideo.stance).withValues(alpha: 0.25),
                                    Colors.black,
                                  ],
                                ),
                              ),
                            ),
                            // the video's own picture while it loads: the grid tile that was tapped "opens up" into it
                            if (widget.repository.coverUrl(_currentVideo) != null)
                              Image.network(
                                widget.repository.coverUrl(_currentVideo)!,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                                errorBuilder: (_, _, _) => const SizedBox.shrink(),
                              ),
                            const Center(
                              child: CircularProgressIndicator(color: Colors.white60),
                            ),
                          ],
                        ),

                      // Bottom Scrim Gradient for Readability
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 230,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                            ),
                          ),
                        ),
                      ),

                      // Subtitles, above the scrim and clear of the action rail (right) and the video details (bottom)
                      if (isInitialized && !isAudioOnly && _currentVideo.captions.isNotEmpty)
                        PostCaptions(
                          postId: _currentVideo.id,
                          controller: controller,
                          bottom: 205,
                          leftInset: 16,
                          rightInset: 76,
                        ),

                      // In-reel Overlay: Breadcrumbs, Action rail, Video Metadata
                      ReelOverlay(
                        video: _currentVideo,
                        rootVideo: _rootVideo,
                        muteNotifier: widget.reelController.muteNotifier,
                        onToggleMute: () => widget.reelController.toggleMute(),
                        onLike: _handleLike,
                        onOpenTree: widget.onOpenTree,
                        onOpenReplySheet: widget.onOpenReplySheet,
                        onMoreOptions: _handleMoreMenu,
                        onShare: _handleShare,
                        onReturnToRoot: _returnToRoot,
                        onGoBack: _goToParent,
                        onClose: widget.onClose,
                        canGoBack: _currentVideo.id != _rootVideo.id,
                        treeDepth: _depth(),
                        forCount: _forCount,
                        againstCount: _againstCount,
                        sidesNote: _sidesNote(),
                        onOpenProfile: _currentVideo.authorId == null ? null : _openAuthor,
                        onShowFor: _navigateToFor,
                        onShowAgainst: _navigateToAgainst,
                        titleExpanded: _titleExpanded,
                        onToggleTitle: () => setState(() => _titleExpanded = !_titleExpanded),
                        onFollow: (_currentVideo.authorId == null || _isMine || (_currentVideo.authorFollowed && !widget.reelController.followState.containsKey(_currentVideo.authorId))) ? null : _toggleFollow,
                        following: _isFollowing(),
                        onComments: Provider.of<FeedController?>(context, listen: false) == null ? null : _openComments,
                      ),

                      if (captionService != null && _currentVideo.captions.isNotEmpty)
                        Positioned(
                          // level with the mute button, which sits below the status bar
                          top: MediaQuery.paddingOf(context).top + 10,
                          right: 60,
                          child: CaptionButton(
                            enabled: captionService.enabled,
                            onTap: () => showCaptionPicker(context, postId: _currentVideo.id),
                            size: 38,
                          ),
                        ),

                      // Progress bar along the bottom edge: tap or drag to jump
                      if (isInitialized)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: SeekBar(controller: controller, playedColor: const Color(0xFF16A34A)),
                        ),
                    ],
                  ),
                ),
              ),

              // Animated Play/Pause Feedback Badge
              if (_showPauseIndicator)
                Center(
                  child: AnimatedOpacity(
                    opacity: _showPauseIndicator ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 140),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isPlaying ? Icons.play_arrow_rounded : Icons.pause_rounded,
                        color: Colors.white,
                        size: 44,
                      ),
                    ),
                  ),
                ),

              // Empty State Feedback Pill (when swiping to unavailable stance)
              if (_emptyFeedbackMessage != null)
                Positioned(
                  top: 72,
                  left: 20,
                  right: 20,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white24),
                        boxShadow: const [
                          BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Color(0xFFFBBF24), size: 18),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _emptyFeedbackMessage!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
