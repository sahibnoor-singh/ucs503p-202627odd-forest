import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/post.dart';
import '../../screens/account_screen.dart';
import '../../services/api_client.dart';
import '../../theme/forest_theme.dart';
import '../../ui/chips.dart';
import '../../ui/forest_avatar.dart';
import '../reels/open_debate_graph.dart';
import '../safety/safety_actions.dart';
import 'credibility_details_screen.dart';
import 'follow_list_screen.dart';
import 'profile_controller.dart';
import 'profile_edit_screen.dart';
import 'profile_models.dart';
import 'profile_repository.dart';

/// Opens a full profile page for any user (by id).
Future<void> openProfileScreen(BuildContext context, String userId) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId)),
  );
}

/// The FOREST profile page.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.userId, this.repository});

  final String userId;
  final ProfileRepository? repository;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileController _controller;

  @override
  void initState() {
    super.initState();
    final repo = widget.repository ?? ProfileRepository(context.read<ApiClient>());
    _controller = ProfileController(repo, userId: widget.userId);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return ChangeNotifierProvider<ProfileController>.value(
      value: _controller,
      child: Scaffold(
        backgroundColor: t.bg,
        body: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => _body(context, t),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, ForestTokens t) {
    switch (_controller.status) {
      case ProfileStatus.loading:
        return CustomScrollView(
          slivers: [
            _appBar(t, null),
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
          ],
        );
      case ProfileStatus.error:
        return CustomScrollView(
          slivers: [
            _appBar(t, null),
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: t.fg2),
                      const SizedBox(height: 12),
                      Text(_controller.error ?? 'Could not load profile.', textAlign: TextAlign.center, style: TextStyle(color: t.fg2)),
                      const SizedBox(height: 16),
                      TextButton(onPressed: _controller.load, child: const Text('Retry')),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      case ProfileStatus.loaded:
        final profile = _controller.profile!;
        return RefreshIndicator(
          onRefresh: _controller.load,
          child: CustomScrollView(
            slivers: [
              _appBar(t, profile),
              SliverToBoxAdapter(child: _ProfileHeader(profile: profile, controller: _controller)),
              if (!profile.personality.isEmpty)
                SliverToBoxAdapter(child: _PersonalitySection(profile: profile)),
              SliverToBoxAdapter(child: _CredibilityCard(credibility: profile.credibility, userId: profile.user.id)),
              if (!profile.contributions.isEmpty)
                SliverToBoxAdapter(child: _ContributionOverview(contributions: profile.contributions)),
              SliverToBoxAdapter(child: _ContentTabs(controller: _controller, profile: profile)),
            ],
          ),
        );
    }
  }

  SliverAppBar _appBar(ForestTokens t, UserProfile? profile) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: t.bg,
      foregroundColor: t.fg,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: profile != null ? Text(profile.user.username, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)) : null,
      actions: [
        if (profile != null) ...[
          IconButton(
            icon: const Icon(Icons.share_outlined, size: 22),
            tooltip: 'Share profile',
            onPressed: () => _shareProfile(context, profile),
          ),
          if (!profile.isMe)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 22),
              onSelected: (v) => _onMenuAction(context, v, profile),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'report', child: Text('Report')),
                PopupMenuItem(
                  value: 'block',
                  child: Text(profile.blockedByMe ? 'Unblock' : 'Block'),
                ),
              ],
            )
          else
            IconButton(
              icon: const Icon(Icons.settings_outlined, size: 22),
              tooltip: 'Settings',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccountSettingsScreen()),
              ),
            ),
        ],
      ],
    );
  }

  void _shareProfile(BuildContext context, UserProfile profile) {
    final url = 'https://forestapp.in/u/${profile.user.username}';
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Profile link copied: $url')),
    );
  }

  Future<void> _onMenuAction(BuildContext context, String action, UserProfile profile) async {
    if (action == 'block') {
      final nav = Navigator.of(context);
      final blocked = await blockPersonFlow(
        context,
        userId: profile.user.id,
        username: profile.user.username,
      );
      if (blocked && mounted) nav.pop();
    }
  }
}

// ──── PROFILE HEADER ────

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile, required this.controller});

  final UserProfile profile;
  final ProfileController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar + stats row
          Row(
            children: [
              ForestAvatar(user: profile.user, size: 80),
              const SizedBox(width: 24),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _StatColumn(
                      count: profile.postCount,
                      label: 'Posts',
                    ),
                    _StatColumn(
                      count: profile.followerCount,
                      label: 'Followers',
                      onTap: () => _openFollowList(context, isFollowers: true),
                    ),
                    _StatColumn(
                      count: profile.followingCount,
                      label: 'Following',
                      onTap: () => _openFollowList(context, isFollowers: false),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Name + bot tag
          Row(
            children: [
              Flexible(
                child: Text(
                  profile.user.fullName,
                  style: TextStyle(color: t.fg, fontSize: 16, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (profile.user.isBot) ...[const SizedBox(width: 8), const BotTag()],
            ],
          ),
          // Bio
          if (profile.bio != null && profile.bio!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(profile.bio!, style: TextStyle(color: t.fg, fontSize: 14, height: 1.4)),
          ],
          const SizedBox(height: 14),
          // Action buttons
          if (profile.isMe)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: t.border),
                  foregroundColor: t.fg,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onPressed: () async {
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => ProfileEditScreen(profile: profile)),
                  );
                  unawaited(controller.load());
                },
                child: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: profile.followedByMe ? t.surface : t.accent,
                  foregroundColor: profile.followedByMe ? t.fg : Colors.white,
                  side: profile.followedByMe ? BorderSide(color: t.border) : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onPressed: () async {
                  final ok = await controller.toggleFollow();
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not update. Try again.')),
                    );
                  }
                },
                child: Text(
                  profile.followedByMe ? 'Following' : 'Follow',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openFollowList(BuildContext context, {required bool isFollowers}) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FollowListScreen(
          userId: profile.user.id,
          username: profile.user.username,
          isFollowers: isFollowers,
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.count, required this.label, this.onTap});

  final int count;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_formatCount(count), style: TextStyle(color: t.fg, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: t.fg2, fontSize: 12)),
        ],
      ),
    );
  }

  static String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 10000) return '${(n / 1000).toStringAsFixed(0)}K';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ──── PERSONALITY SECTION ────

class _PersonalitySection extends StatelessWidget {
  const _PersonalitySection({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final p = profile.personality;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.psychology_outlined, size: 18, color: t.fg2),
                const SizedBox(width: 6),
                Text('Personality', style: TextStyle(color: t.fg, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              ],
            ),
            if (p.hasSummary) ...[
              const SizedBox(height: 10),
              Text(p.summary!, style: TextStyle(color: t.fg, fontSize: 14, height: 1.45, fontStyle: FontStyle.italic)),
            ],
            if (p.hasKeywords) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final kw in p.keywords) _KeywordChip(label: kw),
                ],
              ),
            ],
            if (p.hasInterests) ...[
              const SizedBox(height: 10),
              Text('Interests', style: TextStyle(color: t.fg2, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final interest in p.interests)
                    _InterestChip(label: interest),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KeywordChip extends StatelessWidget {
  const _KeywordChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(label, style: TextStyle(color: t.accent, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _InterestChip extends StatelessWidget {
  const _InterestChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(label, style: TextStyle(color: t.fg2, fontSize: 11.5, fontWeight: FontWeight.w500)),
    );
  }
}

// ──── CREDIBILITY CARD ────

class _CredibilityCard extends StatelessWidget {
  const _CredibilityCard({required this.credibility, required this.userId});

  final UserCredibility credibility;
  final String userId;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => CredibilityDetailsScreen(credibility: credibility)),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.surface,
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _ScoreRing(score: credibility.scorePercent, tokens: t),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Credibility', style: TextStyle(color: t.fg, fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      credibility.sufficient
                          ? '${credibility.analyzedVideos} videos analyzed · ${credibility.totalClaims} claims assessed'
                          : 'Not enough analyzed content yet.',
                      style: TextStyle(color: t.fg2, fontSize: 12, height: 1.35),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: t.fg2),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score, required this.tokens});

  final int? score;
  final ForestTokens tokens;

  Color get _color {
    if (score == null) return tokens.fg2;
    if (score! >= 75) return tokens.forStance;
    if (score! >= 50) return const Color(0xFFEAB308);
    return tokens.againstStance;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: score != null ? score! / 100.0 : 0,
            strokeWidth: 4,
            backgroundColor: tokens.border,
            valueColor: AlwaysStoppedAnimation(_color),
          ),
          Text(
            score != null ? '$score' : '—',
            style: TextStyle(color: tokens.fg, fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

// ──── CONTRIBUTION OVERVIEW ────

class _ContributionOverview extends StatelessWidget {
  const _ContributionOverview({required this.contributions});

  final Contributions contributions;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final items = <({String label, int count})>[
      if (contributions.debatesStarted > 0) (label: 'Debates Started', count: contributions.debatesStarted),
      if (contributions.totalPosts > 0) (label: 'Posts', count: contributions.totalPosts),
      if (contributions.analyzedPosts > 0) (label: 'Analyzed', count: contributions.analyzedPosts),
      if (contributions.totalReplies > 0) (label: 'Replies', count: contributions.totalReplies),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            Expanded(
              child: Column(
                children: [
                  Text('${items[i].count}', style: TextStyle(color: t.fg, fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(items[i].label, style: TextStyle(color: t.fg2, fontSize: 11), textAlign: TextAlign.center),
                ],
              ),
            ),
            if (i < items.length - 1) Container(width: 1, height: 28, color: t.border),
          ],
        ],
      ),
    );
  }
}

// ──── CONTENT TABS (Videos / Saved Trees) ────

class _ContentTabs extends StatefulWidget {
  const _ContentTabs({required this.controller, required this.profile});

  final ProfileController controller;
  final UserProfile profile;

  @override
  State<_ContentTabs> createState() => _ContentTabsState();
}

class _ContentTabsState extends State<_ContentTabs> {
  int _tab = 0; // 0 = videos, 1 = saved trees (owner only)

  @override
  void initState() {
    super.initState();
    if (widget.controller.videosStatus == VideosStatus.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(widget.controller.loadVideos());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final showSaved = widget.profile.isMe;
    return Column(
      children: [
        // Tab bar
        Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.border))),
          child: Row(
            children: [
              _TabButton(label: 'Posts', selected: _tab == 0, onTap: () => setState(() => _tab = 0), tokens: t),
              if (showSaved)
                _TabButton(
                  label: 'Saved',
                  selected: _tab == 1,
                  onTap: () {
                    setState(() => _tab = 1);
                    unawaited(widget.controller.loadBookmarks());
                  },
                  tokens: t,
                ),
            ],
          ),
        ),
        if (_tab == 0) _VideosGrid(controller: widget.controller),
        if (_tab == 1 && showSaved) _SavedTreesList(controller: widget.controller),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.selected, required this.onTap, required this.tokens});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ForestTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? tokens.fg : Colors.transparent,
                width: 1.5,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? tokens.fg : tokens.fg2,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ──── VIDEOS GRID ────

class _VideosGrid extends StatelessWidget {
  const _VideosGrid({required this.controller});

  final ProfileController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    if (controller.videosStatus == VideosStatus.loading && controller.videos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (controller.videosStatus == VideosStatus.error && controller.videos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Text('Could not load posts.', style: TextStyle(color: t.fg2)),
              TextButton(onPressed: controller.refreshVideos, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (controller.videos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Text('No posts yet.', style: TextStyle(color: t.fg2, fontSize: 14)),
        ),
      );
    }
    return Column(
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(1),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 1,
            crossAxisSpacing: 1,
          ),
          itemCount: controller.videos.length,
          itemBuilder: (context, i) {
            final pp = controller.videos[i];
            return _VideoTile(profilePost: pp, controller: controller);
          },
        ),
        if (controller.hasMoreVideos)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: controller.videosStatus == VideosStatus.loading
                ? const CircularProgressIndicator()
                : TextButton(onPressed: controller.loadVideos, child: const Text('Load more')),
          ),
      ],
    );
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.profilePost, required this.controller});

  final ProfilePost profilePost;
  final ProfileController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final post = profilePost.post;
    final coverUrl = post.coverUrl ?? post.mediaUrl;
    return GestureDetector(
      onTap: () => _openPost(context, post),
      child: Container(
        color: t.raised,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (coverUrl != null)
              Image.network(
                controller.mediaUrl(coverUrl),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _placeholder(t),
              )
            else
              _placeholder(t),
            // Stance indicator
            Positioned(
              left: 4,
              top: 4,
              child: StanceChip(stance: post.stance),
            ),
            // Kind indicator for text posts
            if (post.kind == PostKind.text)
              Positioned(
                right: 4,
                top: 4,
                child: Icon(Icons.text_fields, size: 16, color: Colors.white.withValues(alpha: 0.8)),
              ),
            // Reply count bottom-right
            if (post.replyCount > 0)
              Positioned(
                right: 4,
                bottom: 4,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 12, color: Colors.white.withValues(alpha: 0.9)),
                    const SizedBox(width: 3),
                    Text('${post.replyCount}', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(ForestTokens t) {
    return Center(child: Icon(Icons.videocam_outlined, size: 28, color: t.fg2));
  }

  void _openPost(BuildContext context, Post post) {
    unawaited(openDebateGraph(context, post));
  }
}

// ──── SAVED TREES ────

class _SavedTreesList extends StatelessWidget {
  const _SavedTreesList({required this.controller});

  final ProfileController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final bookmarks = controller.bookmarks;
    if (bookmarks == null) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (bookmarks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.bookmark_outline, size: 40, color: t.fg2),
              const SizedBox(height: 8),
              Text('No saved trees yet.', style: TextStyle(color: t.fg2, fontSize: 14)),
              const SizedBox(height: 4),
              Text('Bookmark debates to save them here.', style: TextStyle(color: t.fg2, fontSize: 12)),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: bookmarks.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: t.border),
      itemBuilder: (context, i) {
        final bm = bookmarks[i];
        return _SavedTreeTile(bookmark: bm, controller: controller);
      },
    );
  }
}

class _SavedTreeTile extends StatelessWidget {
  const _SavedTreeTile({required this.bookmark, required this.controller});

  final Bookmark bookmark;
  final ProfileController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final post = bookmark.post;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      leading: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: t.raised,
          borderRadius: BorderRadius.circular(8),
        ),
        child: post.coverUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(controller.mediaUrl(post.coverUrl!), fit: BoxFit.cover, errorBuilder: (_, _, _) => _treeIcon(t)),
              )
            : _treeIcon(t),
      ),
      title: Text(
        post.title ?? post.summary ?? 'Untitled debate',
        style: TextStyle(color: t.fg, fontSize: 14, fontWeight: FontWeight.w600),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          Text('@${bookmark.actor.username}', style: TextStyle(color: t.fg2, fontSize: 12)),
          const SizedBox(width: 8),
          StanceChip(stance: post.stance),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (post.replyCount > 0)
            Text('${post.replyCount} replies', style: TextStyle(color: t.fg2, fontSize: 11)),
          Text(_timeAgo(bookmark.savedAt), style: TextStyle(color: t.fg2, fontSize: 10)),
        ],
      ),
      onTap: () => unawaited(openDebateGraph(context, post)),
    );
  }

  Widget _treeIcon(ForestTokens t) {
    return Center(child: Icon(Icons.account_tree_outlined, size: 24, color: t.fg2));
  }

  static String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 365) return '${(diff.inDays / 365).floor()}y ago';
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return 'Just now';
  }
}
