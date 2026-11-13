import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../services/app_errors.dart';
import '../../models/video.dart';
import '../../utils/stance.dart';
import 'reels_repository.dart';

/// Screen displaying the debate tree with indented children, stance connectors,
/// AND an active interactive video player at the top that plays whichever node is clicked!
class ReplyTreeScreen extends StatefulWidget {
  const ReplyTreeScreen({
    super.key,
    required this.rootVideo,
    required this.repository,
    this.onSelectVideo,
  });

  final Video rootVideo;
  final ReelsRepository repository;

  /// Called with the video that was playing when "Watch in Reel" is pressed. Without it (opened from Home) there is no such button.
  final ValueChanged<Video>? onSelectVideo;

  @override
  State<ReplyTreeScreen> createState() => _ReplyTreeScreenState();
}

class _ReplyTreeScreenState extends State<ReplyTreeScreen> {
  late Future<List<Video>> _treeFuture;
  late Video _selectedVideo;
  VideoPlayerController? _playerController;
  bool _isPlaying = false;
  bool _isMuted = false;
  bool _isLoadingPlayer = false;

  @override
  void initState() {
    super.initState();
    _selectedVideo = widget.rootVideo;
    _treeFuture = widget.repository.getTree(widget.rootVideo.id);
    _initPlayerFor(_selectedVideo);
  }

  Future<void> _initPlayerFor(Video video) async {
    setState(() {
      _isLoadingPlayer = true;
      _selectedVideo = video;
    });

    final old = _playerController;
    if (old != null) {
      await old.pause();
      await old.dispose();
    }

    final url = widget.repository.videoUrl(video);
    final controller = VideoPlayerController.networkUrl(Uri.parse(url), videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    _playerController = controller;

    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(_isMuted ? 0 : 1);
      if (mounted) {
        setState(() {
          _isLoadingPlayer = false;
          _isPlaying = true;
        });
        await controller.play();
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingPlayer = false);
    }
  }

  void _togglePlayPause() {
    final controller = _playerController;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
        _isPlaying = false;
      } else {
        controller.play();
        _isPlaying = true;
      }
    });
  }

  void _toggleMute() {
    final controller = _playerController;
    if (controller == null) return;
    setState(() {
      _isMuted = !_isMuted;
      controller.setVolume(_isMuted ? 0 : 1);
    });
  }

  @override
  void dispose() {
    _playerController?.dispose();
    super.dispose();
  }

  void _selectAndReturn(Video video) {
    widget.onSelectVideo?.call(video);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _playerController;
    final isInitialized = controller != null && controller.value.isInitialized;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: const Text('Debate Tree'),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (widget.onSelectVideo != null)
          TextButton.icon(
            onPressed: () => _selectAndReturn(_selectedVideo),
            icon: const Icon(Icons.fullscreen, color: Color(0xFF16A34A)),
            label: const Text(
              'Watch in Reel',
              style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF16A34A)),
            ),
          ),
          const SizedBox(width: 8),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFFE5E7EB)),
        ),
      ),
      body: Column(
        children: [
          // 1. ACTIVE VIDEO PLAYER AT TOP: Plays whichever video is clicked in the tree!
          Container(
            color: Colors.black,
            width: double.infinity,
            height: 220,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (isInitialized && !_isLoadingPlayer)
                  GestureDetector(
                    onTap: _togglePlayPause,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: controller.value.aspectRatio > 0 ? controller.value.aspectRatio : 16 / 9,
                        child: VideoPlayer(controller),
                      ),
                    ),
                  )
                else
                  Center(
                    child: _isLoadingPlayer
                        ? const CircularProgressIndicator(color: Color(0xFF16A34A))
                        : const Icon(Icons.play_circle_outline, color: Colors.white54, size: 48),
                  ),

                // Top controls over video
                Positioned(
                  top: 10,
                  left: 12,
                  right: 12,
                  child: Row(
                    children: [
                      StanceBadge(stance: _selectedVideo.stance, role: _selectedVideo.role),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '@${_selectedVideo.userName}',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Spacer(),
                      // Mute toggle
                      InkWell(
                        onTap: _toggleMute,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isMuted ? Icons.volume_off : Icons.volume_up,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Center Play/Pause button
                if (isInitialized && !_isPlaying && !_isLoadingPlayer)
                  Center(
                    child: IconButton(
                      iconSize: 52,
                      icon: const Icon(Icons.play_circle_filled, color: Colors.white70),
                      onPressed: _togglePlayPause,
                    ),
                  ),

                // Bottom progress indicator
                if (isInitialized)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Color(0xFF16A34A),
                        bufferedColor: Colors.white24,
                        backgroundColor: Colors.white10,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
          ),

          // 2. TREE NODES LIST: Clicking any node plays it in the player above!
          Expanded(
            child: FutureBuilder<List<Video>>(
              future: _treeFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF16A34A)));
                }

                if (snapshot.hasError) {
                  // Do not pretend there are no replies when they simply could not be loaded.
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(friendlyError(snapshot.error, 'Could not load the replies.'),
                            textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => setState(() {
                          _treeFuture = widget.repository.getTree(widget.rootVideo.id);
                        }),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                final nodes = snapshot.data ?? [widget.rootVideo];
                final root = nodes.firstWhere((n) => n.parentVideoId == null, orElse: () => widget.rootVideo);
                final replies = nodes.where((n) => n.id != root.id).toList();

                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8, left: 4),
                      child: Text(
                        'Click any video below to play it:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),

                    // Root Node Card
                    _TreeNodeCard(
                      video: root,
                      isRoot: true,
                      isSelected: _selectedVideo.id == root.id,
                      onTap: () {
                        _initPlayerFor(root);
                      },
                    ),
                    const SizedBox(height: 14),

                    if (replies.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.park_outlined, color: Color(0xFF9CA3AF), size: 36),
                            SizedBox(height: 8),
                            Text(
                              'No branch replies yet',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF111827)),
                            ),
                          ],
                        ),
                      )
                    else
                      ...replies.map((reply) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Stance connector line
                              Container(
                                width: 24,
                                height: 48,
                                margin: const EdgeInsets.only(left: 12, right: 8),
                                decoration: BoxDecoration(
                                  border: Border(
                                    left: BorderSide(
                                      color: stanceTextColor(reply.stance),
                                      width: 2.5,
                                    ),
                                    bottom: BorderSide(
                                      color: stanceTextColor(reply.stance),
                                      width: 2.5,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: _TreeNodeCard(
                                  video: reply,
                                  isRoot: false,
                                  isSelected: _selectedVideo.id == reply.id,
                                  onTap: () {
                                    _initPlayerFor(reply);
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TreeNodeCard extends StatelessWidget {
  const _TreeNodeCard({
    required this.video,
    required this.isRoot,
    required this.isSelected,
    required this.onTap,
  });

  final Video video;
  final bool isRoot;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF0FDF4) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF16A34A)
                : isRoot
                    ? const Color(0xFF111827)
                    : const Color(0xFFE5E7EB),
            width: isSelected ? 2.5 : (isRoot ? 2 : 1),
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected ? const Color(0x2216A34A) : const Color(0x0A000000),
              blurRadius: isSelected ? 8 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StanceBadge(stance: video.stance, role: video.role),
                const SizedBox(width: 8),
                Text(
                  '@${video.userName}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF111827)),
                ),
                const Spacer(),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow, color: Colors.white, size: 12),
                        SizedBox(width: 2),
                        Text(
                          'NOW PLAYING',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  )
                else
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_circle_outline, color: Color(0xFF6B7280), size: 16),
                      SizedBox(width: 4),
                      Text('Play', style: TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              video.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: Color(0xFF111827)),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.verified_outlined, size: 13, color: Color(0xFF16A34A)),
                const SizedBox(width: 4),
                Text(
                  'Credibility: ${video.credibility}%',
                  style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11.5),
                ),
                const Spacer(),
                Row(
                  children: [
                    const Icon(Icons.favorite_border, size: 13, color: Color(0xFF6B7280)),
                    const SizedBox(width: 3),
                    Text('${video.likeCount}', style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7280))),
                    const SizedBox(width: 8),
                    const Icon(Icons.mode_comment_outlined, size: 13, color: Color(0xFF6B7280)),
                    const SizedBox(width: 3),
                    Text('${video.replyCount}', style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7280))),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
