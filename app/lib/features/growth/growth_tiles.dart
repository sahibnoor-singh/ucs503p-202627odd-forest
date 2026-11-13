import 'package:flutter/material.dart';

import '../rooms/rooms_screen.dart';
import 'invite_sheet.dart';

/// Two rows for the Account tab: invite friends, and debate rooms. One widget so the Account page needs one line.
class GrowthTiles extends StatelessWidget {
  const GrowthTiles({super.key});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          ListTile(
            key: const Key('open-invite'),
            leading: const Icon(Icons.person_add_alt_1_outlined),
            title: const Text('Invite friends'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showInviteSheet(context),
          ),
          ListTile(
            key: const Key('open-rooms'),
            leading: const Icon(Icons.groups_2_outlined),
            title: const Text('Debate rooms'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => const RoomsScreen())),
          ),
        ],
      );
}
