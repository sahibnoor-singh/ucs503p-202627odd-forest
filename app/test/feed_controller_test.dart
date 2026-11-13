// FeedController against the fake repository: paging, optimistic likes with
// rollback, replies, status polling, report, and block/undo.

import 'package:flutter_test/flutter_test.dart';

import 'package:forest_app/data/fake_feed_repository.dart';
import 'package:forest_app/data/feed_repository.dart';
import 'package:forest_app/features/home/feed_controller.dart';
import 'package:forest_app/models/post.dart';
import 'package:forest_app/services/api_client.dart';

({FakeFeedRepository repo, FeedController c, List<ToastEvent> toasts}) _make({int pageSize = 20}) {
  final repo = FakeFeedRepository.sample(now: DateTime.utc(2026, 10, 10, 12));
  final c = FeedController(repo, pageSize: pageSize, pollInterval: const Duration(milliseconds: 5));
  final toasts = <ToastEvent>[];
  c.toasts.listen(toasts.add);
  addTearDown(c.dispose);
  return (repo: repo, c: c, toasts: toasts);
}

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  test('first page, then loadMore appends and ends the feed', () async {
    final t = _make(pageSize: 4);
    await t.c.refresh();
    expect(t.c.items.map((i) => i.post.id), ['r3', 'r1', 'r2', 'p1']);
    expect(t.c.hasMore, isTrue);

    await t.c.loadMore();
    expect(t.c.items.map((i) => i.post.id), ['r3', 'r1', 'r2', 'p1', 'p2', 'r4']);
    expect(t.c.hasMore, isFalse);

    await t.c.loadMore(); // nothing left: no-op
    expect(t.c.items, hasLength(6));
  });

  test('a failed first load shows the reason; a failed refresh keeps the feed', () async {
    final t = _make();
    t.repo.failNext = const ApiException('Sign in required', statusCode: 401);
    await t.c.refresh();
    expect(t.c.error, 'Sign in required');
    expect(t.c.items, isEmpty);

    await t.c.refresh();
    expect(t.c.error, isNull);
    expect(t.c.items, isNotEmpty);

    t.repo.failNext = const ApiException('Offline');
    await t.c.refresh();
    expect(t.c.error, isNull, reason: 'items on screen are kept');
    expect(t.c.items, isNotEmpty);
    await _flush();
    expect(t.toasts.last.message, 'Offline');
  });

  test('like is optimistic, syncs with the server, and un-likes', () async {
    final t = _make();
    await t.c.refresh();
    final base = t.c.items.first.post; // r3, 7 likes
    expect(base.likedByMe, isFalse);

    final pending = t.c.toggleLike(base);
    expect(t.c.resolve(base).likedByMe, isTrue, reason: 'optimistic');
    expect(t.c.resolve(base).likeCount, 8);
    await pending;
    expect(t.repo.log, ['like:r3']);
    expect(t.c.resolve(base).likeCount, 8);

    await t.c.toggleLike(base);
    expect(t.repo.log, ['like:r3', 'unlike:r3']);
    expect(t.c.resolve(base).likedByMe, isFalse);
    expect(t.c.resolve(base).likeCount, 7);
  });

  test('a failed like rolls back and says why', () async {
    final t = _make();
    await t.c.refresh();
    final base = t.c.items.first.post;
    t.repo.failNext = const ApiException('Post not found', statusCode: 404);
    await t.c.toggleLike(base);
    await _flush();
    expect(t.c.resolve(base).likedByMe, isFalse);
    expect(t.c.resolve(base).likeCount, 7);
    expect(t.toasts.last.message, 'Post not found');
  });

  test('double tap only likes, never un-likes', () async {
    final t = _make();
    await t.c.refresh();
    final base = t.c.items.first.post;
    await t.c.likeOnly(base);
    await t.c.likeOnly(base);
    expect(t.repo.log, ['like:r3']);
    expect(t.c.resolve(base).likedByMe, isTrue);
  });

  test('a PROCESSING post cannot be liked', () async {
    final t = _make();
    await t.c.refresh();
    final parent = t.c.items.firstWhere((i) => i.post.id == 'p1').post;
    final reply = await t.c.replyVideo(parent, '/tmp/x.mp4');
    expect(reply.post.status, PostStatus.processing);
    await t.c.toggleLike(reply.post);
    expect(t.repo.log.where((l) => l.startsWith('like')), isEmpty);
  });

  test('text reply counts on the parent and the root right away', () async {
    final t = _make();
    await t.c.refresh();
    final r1 = t.c.items.firstWhere((i) => i.post.id == 'r1').post; // child of p1
    final p1 = t.c.items.firstWhere((i) => i.post.id == 'p1').post;
    expect(t.c.resolve(r1).replyCount, 1);
    expect(t.c.resolve(p1).replyCount, 6);
    expect(t.c.resolve(p1).forCount, 2);

    t.repo.nextTextStance = Stance.forSide;
    await t.c.replyText(r1, '  I agree  ');
    await _flush();

    expect(t.repo.log.last, 'replyText:r1:I agree', reason: 'trimmed');
    expect(t.c.resolve(r1).replyCount, 2);
    expect(t.c.resolve(p1).replyCount, 7, reason: 'root counts all replies below it');
    expect(t.c.resolve(p1).forCount, 3);
    expect(t.toasts.last.message, 'Reply posted. AI stance: FOR');
  });

  test('a rejected reply throws so the composer can show the reason', () async {
    final t = _make();
    await t.c.refresh();
    final p1 = t.c.items.firstWhere((i) => i.post.id == 'p1').post;
    t.repo.failNext = const ApiException('Text is limited to 280 characters', statusCode: 400);
    await expectLater(
      t.c.replyText(p1, 'x'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('280'))),
    );
    expect(t.c.resolve(p1).replyCount, 6, reason: 'nothing counted');
  });

  test('a video reply is counted only once it is READY', () async {
    final t = _make();
    await t.c.refresh();
    final p1 = t.c.items.firstWhere((i) => i.post.id == 'p1').post;
    t.repo.pollsUntilReady = 2;

    final reply = await t.c.replyVideo(p1, '/tmp/clip.mp4');
    expect(reply.post.status, PostStatus.processing);
    expect(t.c.resolve(p1).replyCount, 6, reason: 'server counts READY replies only');
    await _flush();
    expect(t.toasts.map((e) => e.message), contains('Reply posted. Analysing it now.'));

    // two polls later it is READY
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(t.c.resolve(reply.post).status, PostStatus.ready);
    expect(t.c.resolve(p1).replyCount, 7);
    expect(t.toasts.last.message, startsWith('Your video reply is ready'));
  });

  test('report succeeds with a toast, and reports failure without throwing', () async {
    final t = _make();
    await t.c.refresh();
    final post = t.c.items.first.post;
    expect(await t.c.report(post, ReportReason.spam), isTrue);
    expect(t.repo.log.last, 'report:r3:SPAM');
    await _flush();
    expect(t.toasts.last.message, 'Reported. We will review it.');

    t.repo.failNext = const ApiException("You can't report your own post", statusCode: 400);
    expect(await t.c.report(post, ReportReason.other), isFalse);
    await _flush();
    expect(t.toasts.last.message, "You can't report your own post");
  });

  test('block hides the person at once; Undo unblocks and re-follows', () async {
    final t = _make();
    await t.c.refresh();
    final kabir = t.c.items.first.actor; // r3's author
    expect(t.c.items.any((i) => i.actor.id == kabir.id), isTrue);

    await t.c.block(kabir, wasFollowing: true);
    expect(t.c.items.any((i) => i.actor.id == kabir.id), isFalse);
    expect(t.repo.log, ['block:u3']);
    await _flush();
    final toast = t.toasts.last;
    expect(toast.message, 'Blocked @kabir_m');
    expect(toast.actionLabel, 'Undo');

    toast.onAction!();
    await _flush();
    expect(t.repo.log, ['block:u3', 'unblock:u3', 'follow:u3'],
        reason: 'blocking removes the follow, so Undo follows again');
    expect(t.c.items.any((i) => i.actor.id == kabir.id), isTrue);
  });

  test('blocking someone you did not follow does not re-follow on Undo', () async {
    final t = _make();
    await t.c.refresh();
    final riya = t.c.items.firstWhere((i) => i.post.id == 'r1').actor;
    await t.c.block(riya, wasFollowing: false);
    await _flush();
    t.toasts.last.onAction!();
    await _flush();
    expect(t.repo.log, ['block:u2', 'unblock:u2']);
  });

  test('a failed block un-hides the person', () async {
    final t = _make();
    await t.c.refresh();
    final kabir = t.c.items.first.actor;
    t.repo.failNext = const ApiException('Server down');
    await t.c.block(kabir, wasFollowing: true);
    expect(t.c.items.any((i) => i.actor.id == kabir.id), isTrue);
    await _flush();
    expect(t.toasts.last.message, 'Server down');
  });

  test('blocking a parent author also hides replies to them', () async {
    final t = _make();
    await t.c.refresh();
    final aman = t.c.items.firstWhere((i) => i.post.id == 'p1').actor;
    await t.c.block(aman, wasFollowing: true);
    // r1 and r2 reply to aman's p1; they disappear with him.
    expect(t.c.items.map((i) => i.post.id), ['r3', 'p2', 'r4']);
  });

  test('mute is one switch for everything and says so', () async {
    final t = _make();
    expect(t.c.muted, isTrue);
    t.c.toggleMute();
    await _flush();
    expect(t.c.muted, isFalse);
    expect(t.toasts.last.message, 'Sound on');
    t.c.toggleMute();
    await _flush();
    expect(t.toasts.last.message, 'Videos muted');
  });

  test('thread posts are registered, so likes there match the feed', () async {
    final t = _make();
    await t.c.refresh();
    final thread = await t.c.loadThread('p1');
    final x1 = thread.replies.firstWhere((r) => r.post.id == 'x1').post;
    await t.c.toggleLike(x1);
    expect(t.c.resolve(x1).likedByMe, isTrue);
    final again = await t.c.loadThread('p1');
    expect(again.replies.firstWhere((r) => r.post.id == 'x1').post.likedByMe, isTrue);
  });
}
