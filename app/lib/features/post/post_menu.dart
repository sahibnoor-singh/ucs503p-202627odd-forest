import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/public_links.dart';
import 'package:provider/provider.dart';

import '../../data/feed_repository.dart';
import '../../models/post.dart';
import '../../models/user.dart';
import '../../theme/forest_theme.dart';
import '../../ui/forest_sheet.dart';
import '../home/feed_controller.dart';

/// What the person sees as the post's text in menus and quotes.
String snippetOf(Post post) {
  for (final s in [post.title, post.body]) {
    if (s != null && s.trim().isNotEmpty) return s.trim();
  }
  return 'Video reply';
}

/// The public page of the debate (`/p/<id>` on the server): the video, the sides, and the replies, for anyone with the link.
String shareLinkFor(Post post) => PublicLinks.debate(post.id);

Future<void> copyShareLink(FeedController controller, Post post) async {
  await Clipboard.setData(ClipboardData(text: shareLinkFor(post)));
  controller.say('Link copied');
}

/// `⋯`: Report, Block @user, Copy link. Report and Block are not offered on
/// your own posts (the server refuses to report them).
Future<void> showItemMenu(
  BuildContext context, {
  required Post post,
  required User author,
  required bool authorIsFollowed,
}) {
  final controller = context.read<FeedController>();
  return showForestSheet<void>(
    context,
    builder: (sheet) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetContext('${author.username}: ${snippetOf(post)}'),
        const SizedBox(height: 8),
        if (!controller.isMine(author)) ...[
          SheetRow(
            label: 'Report',
            danger: true,
            onTap: () {
              Navigator.of(sheet).pop();
              showReportSheet(context, post: post);
            },
          ),
          SheetRow(
            label: 'Block @${author.username}',
            danger: true,
            onTap: () {
              Navigator.of(sheet).pop();
              controller.block(author, wasFollowing: authorIsFollowed);
            },
          ),
        ],
        SheetRow(
          label: 'Copy link',
          onTap: () {
            Navigator.of(sheet).pop();
            copyShareLink(controller, post);
          },
        ),
      ],
    ),
  );
}

/// "Why are you reporting this?" with the five fixed reasons.
Future<void> showReportSheet(BuildContext context, {required Post post}) {
  final controller = context.read<FeedController>();
  return showForestSheet<void>(
    context,
    builder: (sheet) {
      final t = sheet.forest;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Why are you reporting this?',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          for (final reason in ReportReason.values)
            SheetRow(
              label: reason.label,
              onTap: () {
                Navigator.of(sheet).pop();
                controller.report(post, reason);
              },
            ),
          const SizedBox(height: 10),
          Text(
            'Reports go to a human review queue. Nothing is removed automatically.',
            style: TextStyle(fontSize: 12.5, color: t.fg2),
          ),
        ],
      );
    },
  );
}
