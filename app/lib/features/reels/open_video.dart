import 'package:flutter/material.dart';

import '../../models/video.dart';
import '../../services/api_client.dart';
import 'reels_feed.dart';
import 'reels_repository.dart';

/// Opens the full-screen reels feed on [roots] (opening videos, in order). [startOn] shows a reply inside the first debate first;
/// [cursor] is where the feed carries on after [roots]. A back arrow closes it.
Future<void> pushReels(BuildContext context, ReelsRepository repository, List<Video> roots, {String? cursor, Video? startOn}) {
  return Navigator.of(context).push<void>(MaterialPageRoute<void>(
    builder: (route) => Scaffold(
      backgroundColor: Colors.black,
      body: ReelsFeed(
        repository: repository,
        initialDebateRoots: roots,
        initialCursor: cursor,
        startOn: startOn,
        onClose: () => Navigator.of(route).pop(),
      ),
    ),
  ));
}

/// Opens one video: an opening video plays on its own; a reply opens inside its debate, on that reply. Says why in a snackbar if the
/// debate cannot be loaded.
Future<void> openVideoInReels(BuildContext context, ReelsRepository repository, Video video) async {
  if (video.parentVideoId == null) {
    await pushReels(context, repository, [video]);
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  try {
    final debate = await repository.getTree(video.id); // the whole debate, its opening video first
    if (!context.mounted) return;
    final root = debate.firstWhere((n) => n.parentVideoId == null, orElse: () => debate.first);
    await pushReels(context, repository, [root], startOn: root.id == video.id ? null : video);
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : 'Could not open that video. Try again.')));
  }
}
