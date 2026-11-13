import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../theme/forest_theme.dart';
import '../../ui/chips.dart';
import '../../ui/forest_avatar.dart';
import 'profile_models.dart';
import 'profile_repository.dart';
import 'profile_screen.dart';

/// Screen listing followers or following accounts for a given user.
class FollowListScreen extends StatefulWidget {
  const FollowListScreen({
    super.key,
    required this.userId,
    required this.username,
    required this.isFollowers,
  });

  final String userId;
  final String username;
  final bool isFollowers;

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  late final ProfileRepository _repo = ProfileRepository(context.read<ApiClient>());

  final List<FollowEntry> _users = [];
  String? _cursor;
  bool _loading = true;
  String? _error;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = widget.isFollowers
          ? await _repo.getFollowers(widget.userId)
          : await _repo.getFollowing(widget.userId);
      if (mounted) {
        setState(() {
          _users.clear();
          _users.addAll(res.users);
          _cursor = res.nextCursor;
          _hasMore = res.nextCursor != null;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } on Object {
      if (mounted) setState(() { _error = 'Could not load list.'; _loading = false; });
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loading) return;
    try {
      final res = widget.isFollowers
          ? await _repo.getFollowers(widget.userId, cursor: _cursor)
          : await _repo.getFollowing(widget.userId, cursor: _cursor);
      if (mounted) {
        setState(() {
          _users.addAll(res.users);
          _cursor = res.nextCursor;
          _hasMore = res.nextCursor != null;
        });
      }
    } on Object {
      // Keep existing users
    }
  }

  Future<void> _toggleFollow(int index) async {
    final entry = _users[index];
    final newState = !entry.followedByMe;
    setState(() {
      _users[index] = FollowEntry(user: entry.user, followedByMe: newState);
    });
    try {
      await _repo.setFollowing(entry.user.id, newState);
    } on Object {
      // Revert on error
      if (mounted) {
        setState(() {
          _users[index] = entry;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final title = widget.isFollowers ? 'Followers' : 'Following';

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            Text('@${widget.username}', style: TextStyle(color: t.fg2, fontSize: 12)),
          ],
        ),
        backgroundColor: t.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: t.border),
        ),
      ),
      body: _buildBody(t),
    );
  }

  Widget _buildBody(ForestTokens t) {
    if (_loading && _users.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _users.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: TextStyle(color: t.fg2)),
              const SizedBox(height: 12),
              TextButton(onPressed: _loadInitial, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_users.isEmpty) {
      return Center(
        child: Text(
          widget.isFollowers ? 'No followers yet.' : 'Not following anyone yet.',
          style: TextStyle(color: t.fg2, fontSize: 14),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _users.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) => Divider(height: 1, color: t.border),
      itemBuilder: (context, i) {
        if (i == _users.length) {
          _loadMore();
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final entry = _users[i];
        final user = entry.user;
        return ListTile(
          leading: ForestAvatar(user: user, size: 44),
          title: Row(
            children: [
              Flexible(child: Text(user.username, style: TextStyle(color: t.fg, fontWeight: FontWeight.w700, fontSize: 14), overflow: TextOverflow.ellipsis)),
              if (user.isBot) ...[const SizedBox(width: 6), const BotTag()],
            ],
          ),
          subtitle: Text(user.fullName, style: TextStyle(color: t.fg2, fontSize: 12.5), overflow: TextOverflow.ellipsis),
          trailing: SizedBox(
            height: 32,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: entry.followedByMe ? t.raised : t.accent,
                foregroundColor: entry.followedByMe ? t.fg : Colors.white,
                side: entry.followedByMe ? BorderSide(color: t.border) : BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: () => _toggleFollow(i),
              child: Text(
                entry.followedByMe ? 'Following' : 'Follow',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          onTap: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => ProfileScreen(userId: user.id)),
            );
          },
        );
      },
    );
  }
}
