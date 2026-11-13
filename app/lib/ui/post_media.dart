import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../models/post.dart';
import '../services/caption_service.dart';
import '../services/video_pool.dart';
import 'caption_overlay.dart';
import 'forest_icon.dart';
import 'format.dart';
import 'reel_focus.dart';
import 'seek_bar.dart';

/// The video of a post, in a fixed 4:5 frame with the video filling it
/// (cover), or full screen in the viewer.
///
/// Feed cards pass a [focusKey]: the video's player comes from the [VideoPool]
/// while the card is on screen or close to it (so it is ready when you get
/// there, and stays in the pool, with its last frame, when you scroll past), and
/// only plays while [ReelFocus] says it is the most visible one. The viewer
/// passes [fullscreen], takes the same pooled player (an instant start) and
/// always plays.
///
/// States that are not a playing video: still processing, processing failed,
/// the post has no file, or the file would not load.
class PostMedia extends StatefulWidget {
  const PostMedia({
    super.key,
    required this.post,
    required this.mediaUrl,
    this.coverUrl,
    required this.muted,
    required this.onToggleMute,
    this.focusKey,
    this.fullscreen = false,
    this.onTap,
    this.onDoubleTap,
    this.onRetry,
  });

  final Post post;

  /// Absolute URL, or null when the post has no file.
  final String? mediaUrl;

  /// Absolute URL of a picture to show until the video is ready to play (a post made in the editor has one), or null.
  final String? coverUrl;
  final bool muted;
  final VoidCallback onToggleMute;

  /// Identifies this video to [ReelFocus]. Must be unique among the feed.
  final Object? focusKey;
  final bool fullscreen;

  /// Single tap in a card (the viewer toggles pause itself).
  final VoidCallback? onTap;

  /// Double tap. When null, double tap is not handled and a single tap
  /// fires immediately.
  final VoidCallback? onDoubleTap;

  /// Shown as a Retry button on a video that ended FAILED (only its author can
  /// ever see one; the server re-runs the analysis, nothing is uploaded again).
  final VoidCallback? onRetry;

  @override
  State<PostMedia> createState() => _PostMediaState();
}

class _PostMediaState extends State<PostMedia>
    with SingleTickerProviderStateMixin
    implements ReelFocusMember {
  static const _bg = Color(0xFF222222);

  VideoPool? _pool;

  /// The pool's player for [_leasedUrl], once it is ready.
  VideoPlayerController? _controller;
  String? _leasedUrl;
  bool _failed = false;
  bool _userPaused = false;
  CaptionService? _captions;
  ReelFocus? _focus;
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  );

  bool get _hasVideo =>
      widget.post.status == PostStatus.ready && widget.mediaUrl != null;

  @override
  Object get focusKey => widget.focusKey!;

  @override
  MediaProximity measure() {
    if (!mounted) return MediaProximity.none;
    final box = context.findRenderObject();
    final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return MediaProximity.none;
    if (viewport is! RenderBox || !viewport.hasSize) return MediaProximity.none;
    final rect = box.localToGlobal(Offset.zero, ancestor: viewport) & box.size;
    final h = viewport.size.height;
    // Start loading half a screen below and a fifth of a screen above: every video that is loaded holds a hardware
    // decoder, and phones only have a few.
    final near = rect.overlaps(Rect.fromLTRB(-1, -0.2 * h, viewport.size.width + 1, 1.5 * h));
    final shown = rect.intersect(Offset.zero & viewport.size);
    final fraction = (shown.width <= 0 || shown.height <= 0) ? 0.0 : shown.height / box.size.height;
    return MediaProximity(visible: fraction, near: near);
  }

  bool get _wantsController {
    if (!_hasVideo) return false;
    if (widget.fullscreen) return true;
    return widget.focusKey != null && (_focus?.isNear(widget.focusKey!) ?? false);
  }

  bool get _wantsPlay {
    if (_userPaused) return false;
    if (widget.fullscreen) return true;
    return widget.focusKey != null && _focus?.focusedKey == widget.focusKey;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pool = Provider.of<VideoPool?>(context, listen: false);
    _captions = Provider.of<CaptionService?>(context);
    final focus = widget.fullscreen ? null : ReelFocusScope.maybeOf(context);
    if (!identical(focus, _focus)) {
      if (widget.focusKey != null) _focus?.unregister(this);
      _focus = focus;
      if (widget.focusKey != null) focus?.register(this);
    }
    _sync();
  }

  @override
  void didUpdateWidget(PostMedia old) {
    super.didUpdateWidget(old);
    if (old.mediaUrl != widget.mediaUrl || old.post.status != widget.post.status) {
      _dropLease();
      _failed = false;
    }
    _sync();
  }

  @override
  void dispose() {
    if (widget.focusKey != null) _focus?.unregister(this);
    _dropLease();
    _burst.dispose();
    super.dispose();
  }

  /// Gives the player back to the pool (it stays there, paused, until the pool
  /// needs the room).
  void _dropLease() {
    final url = _leasedUrl;
    if (url != null) _pool?.release(url, this);
    _leasedUrl = null;
    _controller = null;
  }

  void _sync() {
    final pool = _pool;
    if (pool == null) return;
    pool.setMuted(widget.muted);
    final url = widget.mediaUrl;
    if (_wantsController && url != null) {
      if (_leasedUrl == null && !_failed) _acquire(pool, url);
    } else if (_leasedUrl != null) {
      _dropLease();
    }
    final leased = _leasedUrl;
    if (leased != null) pool.setPlaying(leased, this, _wantsPlay);
  }

  Future<void> _acquire(VideoPool pool, String url) async {
    _leasedUrl = url;
    final pending = pool.acquire(url, this);
    // A player that is already ready is used in this very frame: no flash of
    // the placeholder when you scroll back to a video.
    final ready = pool.peek(url);
    if (ready != null) {
      _controller = ready;
      return;
    }
    final controller = await pending;
    if (!mounted || _leasedUrl != url) return; // given back while it loaded
    if (controller == null) {
      setState(() {
        _failed = true;
        _leasedUrl = null;
      });
      return;
    }
    setState(() => _controller = controller);
    pool.setPlaying(url, this, _wantsPlay);
  }

  void _togglePause() {
    setState(() => _userPaused = !_userPaused);
    _sync();
  }

  void _doubleTap() {
    _burst.forward(from: 0);
    widget.onDoubleTap!();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final controller = _controller;

    Widget body;
    var showControls = false;
    var showingCover = false;
    if (post.status == PostStatus.processing) {
      body = const _Notice(spinner: true, text: 'Processing…');
    } else if (post.status == PostStatus.failed) {
      body = _Notice(
        icon: Icons.error_outline,
        text: 'Processing failed',
        actionLabel: widget.onRetry == null ? null : 'Retry',
        onAction: widget.onRetry,
      );
    } else if (widget.mediaUrl == null || _failed) {
      body = const _Notice(icon: Icons.videocam_off_outlined, text: 'Video unavailable');
    } else if (controller != null && controller.value.isInitialized) {
      final size = controller.value.size;
      showControls = true;
      // The whole video is always shown, never cropped or stretched: it is fitted inside the frame
      // (the 4:5 card frame, or the full screen) and any space left over is black (_bg).
      body = FittedBox(
        fit: BoxFit.contain,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: size.width > 0 ? size.width : 1,
          height: size.height > 0 ? size.height : 1,
          child: VideoPlayer(controller),
        ),
      );
    } else if (widget.coverUrl != null) {
      // the video is still being fetched: show its cover instead of an empty frame, fitted the way the video will be
      showingCover = true;
      body = Image.network(
        widget.coverUrl!,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    } else {
      body = const SizedBox.shrink();
      showControls = false;
    }

    final stack = Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: showControls || showingCover ? Colors.black : _bg), // black bars around a playing video
        body,
        if (showControls && controller != null && widget.post.hasCaptions)
          PostCaptions(
            postId: widget.post.id,
            controller: controller,
            // clear of the duration pill and mute button on a card, of the caption text and action bar in the viewer
            bottom: widget.fullscreen ? MediaQuery.paddingOf(context).bottom + 182 : 34,
            leftInset: widget.fullscreen ? 14 : 56,
            rightInset: widget.fullscreen ? 14 : 56,
          ),
        if (showControls && controller != null) ..._controls(controller),
        _heartBurst(),
      ],
    );

    final framed = widget.fullscreen
        ? SizedBox.expand(child: stack)
        : AspectRatio(aspectRatio: 4 / 5, child: stack);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.fullscreen ? _togglePause : widget.onTap,
      onDoubleTap: widget.onDoubleTap == null ? null : _doubleTap,
      child: framed,
    );
  }

  List<Widget> _controls(VideoPlayerController controller) {
    return [
      // first, so the duration label and the mute button above it still get their own taps
      Positioned(
        left: 0,
        right: 0,
        bottom: widget.fullscreen ? MediaQuery.paddingOf(context).bottom + 2 : 0,
        child: SeekBar(controller: controller, height: widget.fullscreen ? 32 : 26),
      ),
      ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final playing = value.isPlaying;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (!playing)
                const Center(
                  child: _Circle(
                    size: 54,
                    child: Padding(
                      padding: EdgeInsets.only(left: 3), // optical centring, as in the prototype
                      child: ForestIcon(Icn.play, size: 26, color: Colors.white),
                    ),
                  ),
                ),
              if (!widget.fullscreen)
                Positioned(
                  left: 10,
                  bottom: 14,
                  child: _Pill(durationLabel(value.duration)),
                ),
            ],
          );
        },
      ),
      if (widget.post.hasCaptions && _captions != null)
        Positioned(
          right: widget.fullscreen ? 50 : 46,
          top: widget.fullscreen ? 14 + MediaQuery.paddingOf(context).top : null,
          bottom: widget.fullscreen ? null : 14,
          child: CaptionButton(
            enabled: _captions!.enabled,
            onTap: () => showCaptionPicker(context, postId: widget.post.id),
          ),
        ),
      Positioned(
        right: widget.fullscreen ? 12 : 8,
        top: widget.fullscreen ? 14 + MediaQuery.paddingOf(context).top : null,
        bottom: widget.fullscreen ? null : 14,
        child: GestureDetector(
          onTap: widget.onToggleMute,
          child: Semantics(
            button: true,
            label: widget.muted ? 'Sound on' : 'Mute',
            child: _Circle(
              size: 30,
              alpha: 0.5,
              child: ForestIcon(
                widget.muted ? Icn.muted : Icn.sound,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _heartBurst() {
    final scale = _burst.drive(TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.4, end: 1.15), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.25), weight: 40),
    ]));
    final opacity = _burst.drive(TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 25),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 40),
    ]));
    return IgnorePointer(
      child: Center(
        child: FadeTransition(
          opacity: opacity,
          child: ScaleTransition(
            scale: scale,
            child: const ForestIcon(Icn.heartBurst, size: 96, color: Color(0xFFFF3040)),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({this.icon, this.spinner = false, required this.text, this.actionLabel, this.onAction});

  final IconData? icon;
  final bool spinner;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spinner)
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white70),
            )
          else
            Icon(icon, color: Colors.white54, size: 34),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          if (actionLabel != null) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: onAction,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({required this.size, required this.child, this.alpha = 0.45});

  final double size;
  final double alpha;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: alpha), shape: BoxShape.circle),
      child: child,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0x73000000),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
