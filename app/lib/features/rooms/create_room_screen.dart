import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/auth/auth_widgets.dart';
import '../../services/api_client.dart';
import '../../theme/forest_theme.dart';
import 'rooms_repository.dart';

/// Start a room: a name, the motion, and how long it stays open. Pops the new [Room].
class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  final _name = TextEditingController();
  final _motion = TextEditingController();
  final _about = TextEditingController();
  int? _days = 3; // null = no end
  bool _busy = false;
  String? _error;
  final Map<String, String> _fieldErrors = {};

  @override
  void dispose() {
    for (final c in [_name, _motion, _about]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    final repo = context.read<RoomsRepository>();
    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors.clear();
    });
    try {
      final room = await repo.create(
        name: _name.text.trim(),
        motion: _motion.text.trim(),
        description: _about.text,
        endsAt: _days == null ? null : DateTime.now().add(Duration(days: _days!)),
      );
      if (mounted) Navigator.of(context).pop(room);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        final field = e.field;
        if (field != null) {
          _fieldErrors[field] = e.message;
        } else {
          _error = e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
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
        title: const Text('Start a room', style: TextStyle(fontWeight: FontWeight.w800)),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: t.border)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthField(fieldKey: const Key('room-name'), label: 'Room name', controller: _name, error: _fieldErrors['name'], helper: 'For example: Debate Society, Friday round'),
            AuthField(
              fieldKey: const Key('room-motion'),
              label: 'The motion',
              controller: _motion,
              error: _fieldErrors['motion'],
              helper: 'One statement people can be for or against, like "This house believes attendance should not be compulsory."',
              keyboard: TextInputType.multiline,
            ),
            AuthField(fieldKey: const Key('room-about'), label: 'About (optional)', controller: _about, error: _fieldErrors['description']),
            Text('Open for', style: TextStyle(color: t.fg, fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final (label, days) in [('1 day', 1), ('3 days', 3), ('1 week', 7), ('No end', null)])
                ChoiceChip(
                  key: Key('room-days-${days ?? 'none'}'),
                  label: Text(label),
                  selected: _days == days,
                  onSelected: (_) => setState(() => _days = days),
                  showCheckmark: false,
                  selectedColor: t.accent,
                  backgroundColor: t.raised,
                  labelStyle: TextStyle(color: _days == days ? Colors.white : t.fg, fontWeight: FontWeight.w600),
                  side: BorderSide(color: _days == days ? t.accent : t.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
            ]),
            if (_fieldErrors['endsAt'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_fieldErrors['endsAt']!, style: TextStyle(color: t.like, fontSize: 13))),
            const SizedBox(height: 24),
            AuthError(_error),
            AuthButton(label: 'Create room', busy: _busy, onPressed: _create),
          ],
        ),
      ),
    );
  }
}
