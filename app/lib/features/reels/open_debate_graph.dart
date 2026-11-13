import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/post.dart';
import 'reels_repository.dart';
import 'reply_tree_screen.dart';

/// Opens the debate graph of the debate [post] belongs to: the same screen Discover opens from a reel (every opinion and reply as a
/// tree with FOR / AGAINST connectors, and a player that plays whichever one you tap). Used by the FOR / AGAINST score on Home
/// cards and in the full-screen viewer.
Future<void> openDebateGraph(BuildContext context, Post post) async {
  final repository = context.read<ReelsRepository>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final navigator = Navigator.of(context);
  try {
    final nodes = await repository.getTree(post.id); // the whole debate, root first
    if (nodes.isEmpty) throw StateError('empty debate');
    final root = nodes.firstWhere((n) => n.parentVideoId == null, orElse: () => nodes.first);
    await navigator.push<void>(
      MaterialPageRoute<void>(builder: (_) => ReplyTreeScreen(rootVideo: root, repository: repository)),
    );
  } on Object {
    messenger?.showSnackBar(const SnackBar(content: Text('Could not open the debate graph. Try again.')));
  }
}
