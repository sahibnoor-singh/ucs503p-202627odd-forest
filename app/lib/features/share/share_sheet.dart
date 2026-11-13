import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user.dart';
import '../../services/api_client.dart';
import '../../theme/forest_theme.dart';
import '../../ui/forest_avatar.dart';
import '../../ui/forest_sheet.dart';
import 'share_repository.dart';

/// The paper-plane: send this video to a friend, or copy its link. Friends are the people you follow who follow you back
/// (the server enforces it). Nothing is typed and nothing is written to them: it is the video itself, in their Discover.
///
/// [canSend] is false for posts that are not videos (a text reply can only be linked to).
Future<void> showShareSheet(
  BuildContext context, {
  required String postId,
  required bool canSend,
  required VoidCallback onCopyLink,
  ShareRepository? repository,
}) {
  final repo = repository ?? context.read<ShareRepository>();
  return showForestSheet<void>(
    context,
    builder: (sheet) => _ShareSheet(
      postId: postId,
      canSend: canSend,
      repository: repo,
      onCopyLink: () {
        Navigator.of(sheet).pop();
        onCopyLink();
      },
    ),
  );
}

enum _Sending { idle, sending, sent }

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.postId, required this.canSend, required this.repository, required this.onCopyLink});

  final String postId;
  final bool canSend;
  final ShareRepository repository;
  final VoidCallback onCopyLink;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  List<User>? _friends;
  String? _loadError;
  final Map<String, _Sending> _state = {};
  String? _problem;

  @override
  void initState() {
    super.initState();
    if (widget.canSend) _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final list = await widget.repository.friends();
      if (mounted) setState(() => _friends = list);
    } on Object catch (e) {
      if (mounted) setState(() => _loadError = e is ApiException ? e.message : 'Could not load your friends. Try again.');
    }
  }

  static const _reasons = {
    'NOT_FRIENDS': 'You can only send videos to people you follow who follow you back.',
    'BOT': 'Automated accounts cannot be sent videos.',
    'UNAVAILABLE': 'That person cannot be sent videos right now.',
    'SELF': 'You cannot send a video to yourself.',
  };

  Future<void> _send(User friend) async {
    if (_state[friend.id] == _Sending.sending || _state[friend.id] == _Sending.sent) return;
    setState(() {
      _state[friend.id] = _Sending.sending;
      _problem = null;
    });
    try {
      final result = await widget.repository.send(widget.postId, [friend.id]);
      if (!mounted) return;
      setState(() {
        if (result.sent.contains(friend.id)) {
          _state[friend.id] = _Sending.sent;
        } else {
          _state[friend.id] = _Sending.idle;
          _problem = _reasons[result.skipped[friend.id]] ?? 'Could not send to @${friend.username}.';
        }
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _state[friend.id] = _Sending.idle;
        _problem = e is ApiException ? e.message : 'Could not send to @${friend.username}. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final friends = _friends;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetRow(label: 'Copy link', onTap: widget.onCopyLink),
        if (widget.canSend) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
            child: Text('Send to a friend', style: TextStyle(color: t.fg, fontSize: 15, fontWeight: FontWeight.w800)),
          ),
          if (_loadError != null)
            _Note(text: _loadError!, action: 'Try again', onAction: _load)
          else if (friends == null)
            const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()))
          else if (friends.isEmpty)
            const _Note(text: 'No friends to send to yet. Follow people, and when they follow you back you can send them videos.')
          else
            for (final f in friends) _FriendRow(friend: f, state: _state[f.id] ?? _Sending.idle, onSend: () => _send(f)),
          if (_problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_problem!, key: const ValueKey('share-problem'), style: TextStyle(color: t.like, fontSize: 13)),
            ),
        ] else
          const _Note(text: 'Only videos can be sent to friends. You can still copy the link.'),
      ],
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({required this.friend, required this.state, required this.onSend});

  final User friend;
  final _Sending state;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final sent = state == _Sending.sent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          ForestAvatar(user: friend, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(friend.username, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                Text(friend.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: t.fg2)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 34,
            width: 84,
            child: sent
                ? OutlinedButton(
                    key: ValueKey('send-${friend.id}'),
                    onPressed: null,
                    child: Text('Sent', style: TextStyle(color: t.fg2, fontWeight: FontWeight.w700)),
                  )
                : FilledButton(
                    key: ValueKey('send-${friend.id}'),
                    onPressed: state == _Sending.sending ? null : onSend,
                    style: FilledButton.styleFrom(backgroundColor: t.fg, padding: EdgeInsets.zero),
                    child: state == _Sending.sending
                        ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: t.bg))
                        : Text('Send', style: TextStyle(color: t.bg, fontWeight: FontWeight.w700)),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: TextStyle(color: t.fg2, fontSize: 14, height: 1.35)),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}
