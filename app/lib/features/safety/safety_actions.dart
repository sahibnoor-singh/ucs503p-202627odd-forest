import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/feed_repository.dart' show ReportReason;
import '../../services/api_client.dart';
import '../../theme/forest_theme.dart';
import 'safety_repository.dart';

/// "Why are you reporting this?" with the fixed reasons. Returns the choice, or null when dismissed.
Future<ReportReason?> askReportReason(BuildContext context) {
  final t = context.forest;
  return showModalBottomSheet<ReportReason>(
    context: context,
    backgroundColor: t.raised,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Why are you reporting this?', style: TextStyle(color: t.fg, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final reason in ReportReason.values)
              ListTile(
                key: ValueKey('report-${reason.wire}'),
                contentPadding: EdgeInsets.zero,
                title: Text(reason.label, style: TextStyle(color: t.fg)),
                onTap: () => Navigator.of(sheet).pop(reason),
              ),
            const SizedBox(height: 4),
            Text('Reports go to a human review queue. Nothing is removed automatically.', style: TextStyle(fontSize: 12.5, color: t.fg2)),
          ],
        ),
      ),
    ),
  );
}

/// Asks why, reports the post and says what happened (including why a report was refused, for example your own post).
Future<void> reportPostFlow(BuildContext context, {required String postId}) async {
  final repository = context.read<SafetyRepository?>();
  final messenger = ScaffoldMessenger.of(context);
  final reason = await askReportReason(context);
  if (reason == null) return;
  if (repository == null) {
    messenger.showSnackBar(const SnackBar(content: Text('Could not report right now. Try again.')));
    return;
  }
  try {
    await repository.report(postId, reason);
    messenger.showSnackBar(const SnackBar(content: Text('Reported. We will review it.')));
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : 'Could not report. Check your connection and try again.')));
  }
}

/// Confirms, then blocks [userId] (called [username] on screen). They cannot see you or reach you, you stop seeing them, and any follow
/// between you ends. Returns true when the block went through. The snackbar offers Undo.
Future<bool> blockPersonFlow(BuildContext context, {required String userId, required String username}) async {
  final repository = context.read<SafetyRepository?>();
  final blocklist = context.read<BlocklistController?>();
  final messenger = ScaffoldMessenger.of(context);
  final t = context.forest;
  final sure = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Block @$username?'),
      content: const Text('They will not be able to see your posts or send you videos, and you will stop seeing theirs. '
          'You can unblock them any time from Account, then Blocked accounts.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
        TextButton(key: const Key('confirm-block'), onPressed: () => Navigator.of(ctx).pop(true), child: Text('Block', style: TextStyle(color: t.like))),
      ],
    ),
  );
  if (sure != true) return false;
  if (repository == null) {
    messenger.showSnackBar(const SnackBar(content: Text('Could not block right now. Try again.')));
    return false;
  }
  try {
    await repository.block(userId);
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : 'Could not block @$username. Try again.')));
    return false;
  }
  blocklist?.add(userId);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('Blocked @$username'),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          try {
            await repository.unblock(userId);
            blocklist?.remove(userId);
          } on Object {
            messenger.showSnackBar(const SnackBar(content: Text('Could not undo. Unblock from Account, then Blocked accounts.')));
          }
        },
      ),
    ));
  return true;
}
