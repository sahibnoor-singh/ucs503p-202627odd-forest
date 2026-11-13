import 'package:flutter/material.dart';

import '../../utils/stance.dart';

/// Four-direction gesture navigation layer for FORREST:
/// - Swipe Up: Next independent video in personalized main feed.
/// - Swipe Left: Most relevant FOR reply to current video.
/// - Swipe Right: Most relevant AGAINST reply to current video.
/// - Swipe Down: Return to exact previous navigation state via history stack.
///
/// Features:
/// - Diagonal prevention: Locks to dominant axis with strict threshold.
/// - Debounce protection: Prevents duplicate/rapid triggering.
/// - Rich peek overlays: Visual preview of destination stance/action before releasing.
/// - Tap-to-pause: Smooth animated play/pause indicator.
class GestureLayer extends StatefulWidget {
  const GestureLayer({
    super.key,
    required this.child,
    required this.onSwipeUpNextFeed,
    required this.onSwipeDownBack,
    required this.onSwipeLeftFor,
    required this.onSwipeRightAgainst,
    required this.onTapVideo,
    required this.isPlaying,
    this.hasForVideo = false,
    this.hasAgainstVideo = false,
    this.hasPreviousHistory = false,
    this.forPreview,
    this.againstPreview,
    this.backPreview,
  });

  final Widget child;
  final VoidCallback onSwipeUpNextFeed;
  final VoidCallback onSwipeDownBack;
  final VoidCallback onSwipeLeftFor;
  final VoidCallback onSwipeRightAgainst;
  final VoidCallback onTapVideo;
  final bool isPlaying;
  final bool hasForVideo;
  final bool hasAgainstVideo;
  final bool hasPreviousHistory;
  final String? forPreview;
  final String? againstPreview;
  final String? backPreview;

  @override
  State<GestureLayer> createState() => _GestureLayerState();
}

class _GestureLayerState extends State<GestureLayer>
    with TickerProviderStateMixin {
  Offset _dragOffset = Offset.zero;
  static const double _horizontalThreshold = 70.0;
  static const double _verticalThreshold = 80.0;

  late AnimationController _springController;
  late Animation<Offset> _springAnimation;
  bool _showPauseIndicator = false;
  bool _isNavigating = false;
  int? _lockedAxis; // 0 = horizontal, 1 = vertical, null = undecided

  @override
  void initState() {
    super.initState();
    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(() {
        setState(() => _dragOffset = _springAnimation.value);
      });
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    if (_springController.isAnimating || _isNavigating) return;
    _lockedAxis = null;
    _dragOffset = Offset.zero;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_springController.isAnimating || _isNavigating) return;

    final newOffset = _dragOffset + details.delta;

    // Determine and lock dominant axis to prevent accidental diagonal triggering
    if (_lockedAxis == null) {
      if (newOffset.dx.abs() > 12 && newOffset.dx.abs() > newOffset.dy.abs() * 1.3) {
        _lockedAxis = 0; // Horizontal locked
      } else if (newOffset.dy.abs() > 12 && newOffset.dy.abs() > newOffset.dx.abs() * 1.3) {
        _lockedAxis = 1; // Vertical locked
      }
    }

    setState(() {
      if (_lockedAxis == 0) {
        // Horizontal only
        _dragOffset = Offset(newOffset.dx.clamp(-160.0, 160.0), 0);
      } else if (_lockedAxis == 1) {
        // Vertical only
        _dragOffset = Offset(0, newOffset.dy.clamp(-160.0, 160.0));
      } else {
        // Slight initial free movement before locking
        _dragOffset = Offset(
          newOffset.dx.clamp(-40.0, 40.0),
          newOffset.dy.clamp(-40.0, 40.0),
        );
      }
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isNavigating) {
      _springBack();
      return;
    }

    final dx = _dragOffset.dx;
    final dy = _dragOffset.dy;

    if (_lockedAxis == 0) {
      // Horizontal gestures
      if (dx <= -_horizontalThreshold) {
        // Swipe Left -> FOR reply
        _isNavigating = true;
        _springBack();
        widget.onSwipeLeftFor();
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted) _isNavigating = false;
        });
        return;
      } else if (dx >= _horizontalThreshold) {
        // Swipe Right -> AGAINST reply
        _isNavigating = true;
        _springBack();
        widget.onSwipeRightAgainst();
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted) _isNavigating = false;
        });
        return;
      }
    } else if (_lockedAxis == 1) {
      // Vertical gestures
      if (dy <= -_verticalThreshold) {
        // Swipe Up -> Next in personalized feed
        _isNavigating = true;
        _springBack();
        widget.onSwipeUpNextFeed();
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted) _isNavigating = false;
        });
        return;
      } else if (dy >= _verticalThreshold) {
        // Swipe Down -> Return to exact previous navigation state
        _isNavigating = true;
        _springBack();
        widget.onSwipeDownBack();
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted) _isNavigating = false;
        });
        return;
      }
    }

    _springBack();
  }

  void _springBack() {
    _lockedAxis = null;
    _springAnimation = Tween<Offset>(
      begin: _dragOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _springController,
      curve: Curves.easeOutCubic,
    ));
    _springController.forward(from: 0.0);
  }

  void _handleTap() {
    widget.onTapVideo();
    setState(() => _showPauseIndicator = true);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _showPauseIndicator = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dx = _dragOffset.dx;
    final dy = _dragOffset.dy;

    final isDraggingLeft = dx < 0 && _lockedAxis == 0;
    final isDraggingRight = dx > 0 && _lockedAxis == 0;
    final isDraggingUp = dy < 0 && _lockedAxis == 1;
    final isDraggingDown = dy > 0 && _lockedAxis == 1;

    final revealRatioX = (dx.abs() / _horizontalThreshold).clamp(0.0, 1.0);
    final revealRatioY = (dy.abs() / _verticalThreshold).clamp(0.0, 1.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Horizontal Peeking Panels (FOR / AGAINST)
        if (isDraggingLeft || isDraggingRight)
          Positioned.fill(
            child: Container(
              color: isDraggingLeft
                  ? (widget.hasForVideo
                      ? StanceColors.forBg.withValues(alpha: 0.95 * revealRatioX)
                      : const Color(0xFFF3F4F6).withValues(alpha: 0.95 * revealRatioX))
                  : (widget.hasAgainstVideo
                      ? StanceColors.againstBg.withValues(alpha: 0.95 * revealRatioX)
                      : const Color(0xFFF3F4F6).withValues(alpha: 0.95 * revealRatioX)),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              alignment: isDraggingLeft ? Alignment.centerRight : Alignment.centerLeft,
              child: AnimatedOpacity(
                opacity: revealRatioX,
                duration: const Duration(milliseconds: 80),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isDraggingRight) ...[
                      Icon(
                        widget.hasAgainstVideo ? Icons.arrow_back_rounded : Icons.info_outline_rounded,
                        color: widget.hasAgainstVideo ? StanceColors.againstText : const Color(0xFF6B7280),
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
                              ? (widget.hasForVideo ? 'FOR REPLY' : 'NO FOR REPLIES')
                              : (widget.hasAgainstVideo ? 'AGAINST REPLY' : 'NO AGAINST REPLIES'),
                          style: TextStyle(
                            color: isDraggingLeft
                                ? (widget.hasForVideo ? StanceColors.forText : const Color(0xFF4B5563))
                                : (widget.hasAgainstVideo ? StanceColors.againstText : const Color(0xFF4B5563)),
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                        if (isDraggingLeft && widget.hasForVideo)
                          Text(
                            widget.forPreview ?? 'Connected argument',
                            style: TextStyle(
                              color: StanceColors.forText.withValues(alpha: 0.8),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          )
                        else if (isDraggingRight && widget.hasAgainstVideo)
                          Text(
                            widget.againstPreview ?? 'Counter argument',
                            style: TextStyle(
                              color: StanceColors.againstText.withValues(alpha: 0.8),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                    if (isDraggingLeft) ...[
                      const SizedBox(width: 10),
                      Icon(
                        widget.hasForVideo ? Icons.arrow_forward_rounded : Icons.info_outline_rounded,
                        color: widget.hasForVideo ? StanceColors.forText : const Color(0xFF6B7280),
                        size: 28,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

        // 2. Vertical Peeking Panels (Next Feed / Back in History)
        if (isDraggingUp || isDraggingDown)
          Positioned.fill(
            child: Container(
              color: isDraggingUp
                  ? const Color(0xFF1E293B).withValues(alpha: 0.95 * revealRatioY)
                  : (widget.hasPreviousHistory
                      ? const Color(0xFF0F766E).withValues(alpha: 0.95 * revealRatioY)
                      : const Color(0xFF374151).withValues(alpha: 0.95 * revealRatioY)),
              padding: const EdgeInsets.symmetric(vertical: 36),
              alignment: isDraggingUp ? Alignment.bottomCenter : Alignment.topCenter,
              child: AnimatedOpacity(
                opacity: revealRatioY,
                duration: const Duration(milliseconds: 80),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isDraggingDown) ...[
                      Icon(
                        widget.hasPreviousHistory ? Icons.arrow_upward_rounded : Icons.history_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      isDraggingUp
                          ? 'NEXT DEBATE'
                          : (widget.hasPreviousHistory ? 'RETURN TO PREVIOUS' : 'START OF HISTORY'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    if (isDraggingDown && widget.backPreview != null)
                      Text(
                        widget.backPreview!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    if (isDraggingUp) ...[
                      const SizedBox(height: 6),
                      const Icon(
                        Icons.arrow_downward_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

        // 3. Sliding child with translation
        Transform.translate(
          offset: _dragOffset,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _handleTap,
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: widget.child,
          ),
        ),

        // 4. Animated Play / Pause Indicator
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
                  widget.isPlaying ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
