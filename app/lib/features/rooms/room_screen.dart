import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/feed_item.dart';
import '../../models/user.dart';
import '../../screens/home_feed_screen.dart' show cardActionsFor;
import '../../screens/upload_screen.dart';
import '../../services/analytics.dart';
import '../../services/api_client.dart';
import '../../theme/forest_theme.dart';
import '../../ui/forest_avatar.dart';
import '../editor/post_attachment.dart';
import '../home/feed_controller.dart';
import '../home/feed_item_card.dart';
import 'rooms_repository.dart';
import 'rooms_screen.dart' show RoomStatusPill;

/// One room: the motion, where the room stands, the code to hand to friends, a button to argue your side, and what people posted.
class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.roomId});

  final String roomId;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late final RoomsRepository _repo = context.read<RoomsRepository>();
  RoomDetail? _detail;
  List<FeedItem>? _posts;
  String? _error;

  @override
  void initState() {
    super.initState();
    context.read<Analytics?>()?.track('room_opened');
    _load();
  }

  Future<void> _load() async {
    final feed = context.read<FeedController>();
    try {
      final results = await Future.wait<Object>([_repo.detail(widget.roomId), _repo.posts(widget.roomId)]);
      final posts = results[1] as List<FeedItem>;
      feed.adopt(posts);
      if (mounted) {
        setState(() {
          _detail = results[0] as RoomDetail;
          _posts = posts;
          _error = null;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Could not load this room. Check your connection.');
    }
  }

  Future<void> _post(Room room) async {
    final sent = await openUploadFor(context, PostAttachment(roomId: room.id, label: 'Argue in ${room.name}'));
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Posted. It joins the room once it has been processed.')));
      _load();
    }
  }

  Future<void> _leave() async {
    final nav = Navigator.of(context);
    final ok = await _confirm('Leave this room?', 'You can join again with the code.', 'Leave');
    if (ok != true) return;
    try {
      await _repo.leave(widget.roomId);
      nav.pop();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _close() async {
    final ok = await _confirm('Close this room?', 'Nobody can post in it after this. It stays readable.', 'Close room');
    if (ok != true) return;
    try {
      await _repo.close(widget.roomId);
      if (mounted) _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<bool?> _confirm(String title, String text, String action) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(key: const Key('room-confirm'), onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final detail = _detail;
    final room = detail?.room;
    final feed = context.read<FeedController>();
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(room?.name ?? 'Room', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (room != null)
            PopupMenuButton<String>(
              key: const Key('room-menu'),
              onSelected: (v) => v == 'close' ? _close() : _leave(),
              itemBuilder: (_) => [
                if (room.isOwner && room.status != RoomStatus.closed) const PopupMenuItem(value: 'close', child: Text('Close room')),
                if (!room.isOwner) const PopupMenuItem(value: 'leave', child: Text('Leave room')),
              ],
            ),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: t.border)),
      ),
      body: room == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: t.fg2))),
            )
          : RefreshIndicator(
              color: t.fg,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 28),
                children: [
                  _Motion(room: room),
                  _Standing(room: room),
                  if (detail!.members.isNotEmpty) _Members(room: room, members: detail.members),
                  if (room.canPost)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: SizedBox(
                        height: 50,
                        child: FilledButton.icon(
                          key: const Key('room-post'),
                          onPressed: () => _post(room),
                          icon: const Icon(Icons.videocam_rounded),
                          label: const Text('Argue your side', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          style: FilledButton.styleFrom(backgroundColor: t.accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Text(room.status == RoomStatus.upcoming ? 'This room has not started yet.' : 'This room is closed. You can still read it.', style: TextStyle(color: t.fg2)),
                    ),
                  Divider(height: 1, color: t.border),
                  if (_posts == null)
                    const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()))
                  else if (_posts!.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
                      child: Text('Nobody has posted in this room yet.', textAlign: TextAlign.center, style: TextStyle(color: t.fg2, fontSize: 15)),
                    )
                  else
                    for (final item in _posts!)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
                        child: FeedItemCard(key: ValueKey('room-post-${item.post.id}'), item: item, actions: cardActionsFor(context, feed)),
                      ),
                ],
              ),
            ),
    );
  }
}

class _Motion extends StatelessWidget {
  const _Motion({required this.room});

  final Room room;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: t.raised, borderRadius: BorderRadius.circular(18), border: Border.all(color: t.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('THE MOTION', style: TextStyle(color: t.accent, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
            const Spacer(),
            RoomStatusPill(status: room.status),
          ]),
          const SizedBox(height: 8),
          Text(room.motion, key: const Key('room-motion-text'), style: TextStyle(color: t.fg, fontSize: 20, fontWeight: FontWeight.w800, height: 1.25)),
          if (room.description != null) ...[
            const SizedBox(height: 8),
            Text(room.description!, style: TextStyle(color: t.fg2, fontSize: 14, height: 1.4)),
          ],
          if (room.endsAt != null) ...[
            const SizedBox(height: 8),
            Text(room.status == RoomStatus.closed ? 'Ended ${_day(room.endsAt!)}' : 'Open until ${_day(room.endsAt!)}', style: TextStyle(color: t.fg2, fontSize: 12.5)),
          ],
          if (room.code != null) ...[
            const SizedBox(height: 12),
            Row(children: [
              Text('Room code', style: TextStyle(color: t.fg2, fontSize: 13)),
              const SizedBox(width: 10),
              Text(room.code!, key: const Key('room-code'), style: TextStyle(color: t.fg, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 3)),
              const Spacer(),
              TextButton(
                key: const Key('room-copy-code'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: room.code!));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied')));
                },
                child: const Text('Copy'),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  static String _day(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final l = d.toLocal();
    return '${l.day} ${months[l.month - 1]}';
  }
}

/// Where the room stands: a bar split between FOR and AGAINST the motion (as the AI read each video), and how many are undecided.
class _Standing extends StatelessWidget {
  const _Standing({required this.room});

  final Room room;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final decided = room.forCount + room.againstCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (decided == 0)
            Text(room.posts == 0 ? 'No opinions yet.' : 'Reading the opinions…', style: TextStyle(color: t.fg2, fontSize: 14))
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 10,
                child: Row(children: [
                  Expanded(flex: room.forCount == 0 ? 0 : room.forCount, child: Container(key: const Key('standing-for'), color: t.forStance)),
                  Expanded(flex: room.againstCount == 0 ? 0 : room.againstCount, child: Container(key: const Key('standing-against'), color: t.againstStance)),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Text('${room.forCount} FOR', style: TextStyle(color: t.forStance, fontWeight: FontWeight.w800, fontSize: 13.5)),
              const Spacer(),
              Text('${room.againstCount} AGAINST', style: TextStyle(color: t.againstStance, fontWeight: FontWeight.w800, fontSize: 13.5)),
            ]),
            if (room.undecided > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${room.undecided} undecided', style: TextStyle(color: t.fg2, fontSize: 12.5))),
          ],
        ],
      ),
    );
  }
}

class _Members extends StatelessWidget {
  const _Members({required this.room, required this.members});

  final Room room;
  final List<User> members;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(children: [
        SizedBox(
          height: 30,
          width: (members.length.clamp(1, 6) * 20.0) + 12,
          child: Stack(children: [
            for (var i = 0; i < members.length.clamp(0, 6); i++) Positioned(left: i * 20.0, child: ForestAvatar(user: members[i], size: 30)),
          ]),
        ),
        const SizedBox(width: 8),
        Text('${room.memberCount} ${room.memberCount == 1 ? 'member' : 'members'}', style: TextStyle(color: t.fg2, fontSize: 13)),
      ]),
    );
  }
}
