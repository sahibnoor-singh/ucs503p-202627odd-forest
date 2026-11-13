import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user.dart';
import '../../services/api_client.dart';
import '../../theme/forest_theme.dart';
import '../../ui/chips.dart';
import '../../ui/forest_avatar.dart';
import 'safety_repository.dart';

/// A row for Account: opens the list of people you have blocked.
class BlockedAccountsTile extends StatelessWidget {
  const BlockedAccountsTile({super.key});

  @override
  Widget build(BuildContext context) => ListTile(
        key: const Key('blocked-accounts'),
        leading: const Icon(Icons.block_rounded),
        title: const Text('Blocked accounts'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => const BlockedAccountsScreen())),
      );
}

/// The people you blocked, with Unblock. Without this a block could never be undone after the snackbar's Undo is gone.
class BlockedAccountsScreen extends StatefulWidget {
  const BlockedAccountsScreen({super.key, this.repository});

  /// For tests; the app uses the shared one.
  final SafetyRepository? repository;

  @override
  State<BlockedAccountsScreen> createState() => _BlockedAccountsScreenState();
}

class _BlockedAccountsScreenState extends State<BlockedAccountsScreen> {
  late final SafetyRepository? _repository = widget.repository ?? context.read<SafetyRepository?>();
  late final BlocklistController? _blocklist = context.read<BlocklistController?>();
  List<User>? _people;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = _repository;
    if (repo == null) {
      setState(() => _error = 'Could not load this list right now.');
      return;
    }
    setState(() => _error = null);
    try {
      final list = await repo.blocked();
      if (mounted) setState(() => _people = list);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Could not load your blocked accounts. Check your connection and try again.');
    }
  }

  Future<void> _unblock(User user) async {
    if (_busy.contains(user.id)) return;
    setState(() => _busy.add(user.id));
    try {
      await _repository!.unblock(user.id);
      _blocklist?.remove(user.id);
      if (!mounted) return;
      setState(() => _people = [for (final u in _people ?? const <User>[]) if (u.id != user.id) u]);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unblocked @${user.username}. You can follow each other again.')));
    } on Object catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : 'Could not unblock @${user.username}. Try again.')));
    } finally {
      if (mounted) setState(() => _busy.remove(user.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Blocked accounts', style: TextStyle(fontWeight: FontWeight.w800)),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: t.border)),
      ),
      body: _body(t),
    );
  }

  Widget _body(ForestTokens t) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: t.fg2, fontSize: 15)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Try again')),
          ]),
        ),
      );
    }
    final people = _people;
    if (people == null) return const Center(child: CircularProgressIndicator());
    if (people.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text('You have not blocked anyone. People you block cannot see your posts or send you videos.', textAlign: TextAlign.center, style: TextStyle(color: t.fg2, fontSize: 15, height: 1.4)),
        ),
      );
    }
    return ListView(
      children: [
        for (final u in people)
          ListTile(
            key: ValueKey('blocked-${u.id}'),
            leading: ForestAvatar(user: u, size: 44),
            title: Row(children: [
              Flexible(child: Text(u.username, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
              if (u.isBot) ...[const SizedBox(width: 6), const BotTag()],
            ]),
            subtitle: Text(u.fullName),
            trailing: OutlinedButton(
              key: ValueKey('unblock-${u.id}'),
              onPressed: _busy.contains(u.id) ? null : () => _unblock(u),
              child: const Text('Unblock'),
            ),
          ),
      ],
    );
  }
}
