import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../theme/forest_theme.dart';

/// "Friends shape my Discover": whether posts that a friend's taste would pick (a friend who sends you videos you keep liking) may
/// appear among your own. At most a quarter of what you see; off means only your own ranking, plus the exploration that is always
/// there. Self-contained so any settings page can place it (the Account tab does for now).
class FriendTasteSwitch extends StatefulWidget {
  const FriendTasteSwitch({super.key, required this.api});

  final ApiClient api;

  @override
  State<FriendTasteSwitch> createState() => _FriendTasteSwitchState();
}

class _FriendTasteSwitchState extends State<FriendTasteSwitch> {
  bool? _on; // null until the server has said
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final json = await widget.api.getJson('/api/me');
      final settings = json is Map<String, dynamic> ? json['settings'] : null;
      if (mounted && settings is Map<String, dynamic>) setState(() => _on = settings['friendTaste'] != false);
    } on Object {
      // no switch is better than a wrong one
    }
  }

  Future<void> _set(bool value) async {
    final before = _on;
    setState(() {
      _on = value;
      _saving = true;
    });
    try {
      await widget.api.sendJson('PUT', '/api/me/settings', body: {'friendTaste': value});
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _on = before);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : 'Could not save that. Try again.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = _on;
    if (on == null) return const SizedBox.shrink();
    final t = context.forest;
    return SwitchListTile(
      key: const Key('friend-taste-switch'),
      value: on,
      onChanged: _saving ? null : _set,
      title: const Text('Friends shape my Discover', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      subtitle: Text(
        'Adds a few posts that friends who send you videos you like would pick, a quarter of what you see at most. Off: only your own picks.',
        style: TextStyle(color: t.fg2, fontSize: 12.5, height: 1.3),
      ),
    );
  }
}
