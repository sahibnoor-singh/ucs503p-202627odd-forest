import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/analytics.dart';
import '../../services/api_client.dart';
import '../../theme/forest_theme.dart';
import '../../ui/forest_sheet.dart';

/// The person's invite code and link (`GET /api/me/invite`).
class InviteInfo {
  const InviteInfo({required this.code, required this.link, required this.invitedCount});

  factory InviteInfo.fromJson(Map<String, dynamic> json) => InviteInfo(
        code: json['code'] as String,
        link: json['link'] as String,
        invitedCount: (json['invitedCount'] as num?)?.toInt() ?? 0,
      );

  final String code;
  final String link;
  final int invitedCount;
}

/// "Invite friends": the code to hand to a friend, and the link that explains FOREST to them.
Future<void> showInviteSheet(BuildContext context) => showForestSheet<void>(context, builder: (_) => const InviteSheet());

class InviteSheet extends StatefulWidget {
  const InviteSheet({super.key});

  @override
  State<InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<InviteSheet> {
  InviteInfo? _info;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    try {
      final json = await api.getJson('/api/me/invite');
      if (json is! Map<String, dynamic>) throw const ApiException('The server sent an answer the app does not understand.');
      if (mounted) setState(() => _info = InviteInfo.fromJson(json));
    } on Object catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Could not load your invite. Check your connection.');
    }
  }

  void _copy(String text, String done) {
    Clipboard.setData(ClipboardData(text: text));
    context.read<Analytics?>()?.track('invite_copied');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final info = _info;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Invite friends', style: TextStyle(color: t.fg, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'A friend who signs up with your code follows you, and you follow them, so their first Home is not empty.',
            style: TextStyle(color: t.fg2, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 18),
          if (info == null && _error == null) const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
          else if (info == null) Text(_error!, style: TextStyle(color: t.fg2))
          else ...[
            Center(child: Text(info.code, key: const Key('invite-code'), style: TextStyle(color: t.fg, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 6))),
            const SizedBox(height: 16),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                key: const Key('invite-copy-link'),
                onPressed: () => _copy('Join me on FOREST, where we answer opinions with video: ${info.link}', 'Link copied'),
                icon: const Icon(Icons.link_rounded),
                label: const Text('Copy invite link', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                style: FilledButton.styleFrom(backgroundColor: t.accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: OutlinedButton(
                key: const Key('invite-copy-code'),
                onPressed: () => _copy(info.code, 'Code copied'),
                style: OutlinedButton.styleFrom(foregroundColor: t.fg, side: BorderSide(color: t.border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: const Text('Copy code only', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(
                info.invitedCount == 0 ? 'Nobody has joined with your code yet.' : '${info.invitedCount} ${info.invitedCount == 1 ? 'friend has' : 'friends have'} joined with your code.',
                style: TextStyle(color: t.fg2, fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
