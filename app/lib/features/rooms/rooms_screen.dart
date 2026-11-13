import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../theme/forest_theme.dart';
import 'create_room_screen.dart';
import 'room_screen.dart';
import 'rooms_repository.dart';

/// Debate rooms you are in, a way to join one with a code, and a way to start one.
class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  late final RoomsRepository _repo = context.read<RoomsRepository>();
  List<Room>? _rooms;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _repo.mine();
      if (mounted) {
        setState(() {
          _rooms = list;
          _error = null;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Could not load your rooms. Check your connection.');
    }
  }

  Future<void> _open(Room room) async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => RoomScreen(roomId: room.id)));
    if (mounted) _load();
  }

  Future<void> _create() async {
    final made = await Navigator.of(context).push<Room>(MaterialPageRoute<Room>(builder: (_) => const CreateRoomScreen()));
    if (made != null && mounted) {
      await _load();
      if (mounted) await _open(made);
    }
  }

  Future<void> _join() async {
    final code = await showDialog<String>(context: context, builder: (_) => const _JoinDialog());
    if (code == null || code.trim().isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final room = await _repo.join(code.trim());
      if (!mounted) return;
      await _load();
      if (mounted) await _open(room);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final rooms = _rooms;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Debate rooms', style: TextStyle(fontWeight: FontWeight.w800)),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: t.border)),
      ),
      body: RefreshIndicator(
        color: t.fg,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              'A room is one motion that a society, a class or a group of friends argues for a few days. Everyone posts a video, and the room shows where it stands.',
              style: TextStyle(color: t.fg2, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    key: const Key('rooms-create'),
                    onPressed: _create,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Start a room', style: TextStyle(fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(backgroundColor: t.accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    key: const Key('rooms-join'),
                    onPressed: _join,
                    icon: const Icon(Icons.vpn_key_outlined),
                    label: const Text('Join', style: TextStyle(fontWeight: FontWeight.w700)), // short on purpose: "Join with a code" wrapped to two lines on a 360 px phone
                    style: OutlinedButton.styleFrom(foregroundColor: t.fg, side: BorderSide(color: t.border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            if (rooms == null && _error == null)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (rooms == null)
              Center(child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: t.fg2)))
            else if (rooms.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text('You are not in any room yet.', textAlign: TextAlign.center, style: TextStyle(color: t.fg2, fontSize: 15)),
              )
            else
              for (final room in rooms) _RoomTile(key: ValueKey('room-${room.id}'), room: room, onTap: () => _open(room)),
          ],
        ),
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({super.key, required this.room, required this.onTap});

  final Room room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: t.raised,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: t.border)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(room.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.fg, fontSize: 16.5, fontWeight: FontWeight.w800))),
                  RoomStatusPill(status: room.status),
                ]),
                const SizedBox(height: 6),
                Text(room.motion, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.fg2, fontSize: 14, height: 1.3)),
                const SizedBox(height: 10),
                Text('${room.memberCount} ${room.memberCount == 1 ? 'member' : 'members'} · ${room.posts} ${room.posts == 1 ? 'opinion' : 'opinions'}', style: TextStyle(color: t.fg2, fontSize: 12.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RoomStatusPill extends StatelessWidget {
  const RoomStatusPill({super.key, required this.status});

  final RoomStatus status;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final (label, color) = switch (status) {
      RoomStatus.open => ('OPEN', t.forStance),
      RoomStatus.upcoming => ('STARTS SOON', t.accent),
      RoomStatus.closed => ('CLOSED', t.fg2),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
    );
  }
}

class _JoinDialog extends StatefulWidget {
  const _JoinDialog();

  @override
  State<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends State<_JoinDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join a room'),
      content: TextField(
        key: const Key('join-code'),
        controller: _code,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        maxLength: 8,
        decoration: const InputDecoration(labelText: 'Room code', counterText: ''),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(key: const Key('join-confirm'), onPressed: () => Navigator.pop(context, _code.text), child: const Text('Join')),
      ],
    );
  }
}
