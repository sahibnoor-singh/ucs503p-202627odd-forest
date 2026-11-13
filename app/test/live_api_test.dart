// Opt-in: runs the real HTTP repository and FeedController against a real
// backend, to prove the app and `app/backend` agree. Skipped by default.
//
//   cd app/backend && npm run seed -- --reset && npm start          (port 3000)
//   cd app && flutter test test/live_api_test.dart --dart-define=LIVE_API=http://localhost:3000
//
// It changes data (likes, a reply, a report, a block that it undoes), so point
// it at a database you are happy to re-seed. The server must have no Gemini key
// for the stance assertions (replies are then UNRESOLVED).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:forest_app/data/api_feed_repository.dart';
import 'package:forest_app/data/auth_repository.dart';
import 'package:forest_app/features/reels/reels_repository.dart';
import 'package:forest_app/data/feed_repository.dart';
import 'package:forest_app/features/home/feed_controller.dart';
import 'package:forest_app/models/feed_item.dart';
import 'package:forest_app/models/post.dart';
import 'package:forest_app/services/api_client.dart';

const _live = String.fromEnvironment('LIVE_API');

void main() {
  final skip = _live.isEmpty ? 'set --dart-define=LIVE_API=http://localhost:3000 to run' : null;
  _liveAuthAndDiscover(skip);

  test('app ⇄ backend: home, like, reply, video status, report, block', skip: skip, () async {
    final api = ApiClient(baseUrl: _live, devUser: 'dev');
    final repo = ApiFeedRepository(api);
    final c = FeedController(repo, pollInterval: const Duration(milliseconds: 400), maxPolls: 40);
    final toasts = <String>[];
    c.toasts.listen((e) => toasts.add(e.message));
    addTearDown(c.dispose);

    // who am I, and the 401 path
    final me = await repo.me();
    expect(me.username, 'dev');
    expect(me.isBot, isFalse);
    await expectLater(
      ApiFeedRepository(ApiClient(baseUrl: _live, devUser: '')).home(),
      throwsA(isA<ApiException>().having((e) => e.isUnauthorized, '401', isTrue)),
    );

    // Home: every row parses, nothing is skipped
    await c.refresh();
    expect(c.error, isNull);
    expect(c.items, hasLength(6));
    expect(c.items.every((i) => i.actor.isBot || i.actor.id == me.id), isTrue);
    final opinion = c.items.firstWhere((i) => i.type == ItemType.post && i.post.replyCount > 0);

    // like → count goes up on the server; un-like restores it
    final before = opinion.post.likeCount;
    await c.toggleLike(opinion.post);
    expect(c.resolve(opinion.post).likedByMe, isTrue);
    expect((await repo.post(opinion.post.id)).post.likeCount, before + 1);
    await c.toggleLike(opinion.post);
    expect((await repo.post(opinion.post.id)).post.likeCount, before);

    // thread: flat list rebuilds into a tree under the opinion
    final thread = await c.loadThread(opinion.post.id);
    expect(thread.total, thread.replies.length);
    expect(thread.replies.every((r) => r.post.rootId == opinion.post.id), isTrue);

    // text reply: READY at once, classified (UNRESOLVED without a Gemini key), counted
    final repliesBefore = c.resolve(opinion.post).replyCount;
    final text = await c.replyText(opinion.post, '  Live test reply 😀  ');
    expect(text.post.status, PostStatus.ready);
    expect(text.post.body, 'Live test reply 😀');
    expect(text.post.depth, opinion.post.depth + 1);
    expect(c.resolve(opinion.post).replyCount, repliesBefore + 1);
    expect((await repo.post(opinion.post.id)).post.replyCount, repliesBefore + 1,
        reason: 'the local count matches what the server says');

    // text over the limit is refused with the server's message
    await expectLater(
      c.replyText(opinion.post, 'x' * 281),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('280'))),
    );

    // video reply: comes back PROCESSING. The bytes are not a real video, so
    // the server's analysis fails and the app must say so rather than hang.
    final junk = File('${Directory.systemTemp.path}/forest_live_test_${DateTime.now().microsecondsSinceEpoch}.mp4')
      ..writeAsBytesSync(List<int>.filled(2048, 7));
    addTearDown(() {
      if (junk.existsSync()) junk.deleteSync();
    });
    final video = await c.replyVideo(opinion.post, junk.path);
    expect(video.post.status, PostStatus.processing);
    expect(video.post.mediaUrl, startsWith('/uploads/'));
    expect(c.resolve(opinion.post).replyCount, repliesBefore + 1, reason: 'not counted while PROCESSING');
    for (var i = 0; i < 50 && toasts.every((t) => !t.contains('video reply')); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    final finished = c.resolve(video.post).status;
    // ignore: avoid_print
    print('video reply finished as ${finished.wire}; toasts: ${toasts.where((t) => t.contains("video reply")).toList()}');
    expect(finished, anyOf(PostStatus.ready, PostStatus.failed));
    expect(toasts.any((t) => t.contains('Your video reply')), isTrue);

    // a video that ended FAILED can be retried without uploading it again
    if (finished == PostStatus.failed) {
      await c.retryVideo(video.post);
      expect(c.resolve(video.post).status, PostStatus.processing, reason: 'POST /api/posts/:id/retry');
      for (var i = 0; i < 50 && c.resolve(video.post).status == PostStatus.processing; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      // ignore: avoid_print
      print('after retry: ${c.resolve(video.post).status.wire}');
      expect(c.resolve(video.post).status, isNot(PostStatus.processing));
    }

    // report: someone else's post works; your own is refused
    expect(await c.report(opinion.post, ReportReason.misinformation), isTrue);
    expect(await c.report(text.post, ReportReason.spam), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 20)); // toasts arrive via a stream
    expect(toasts.last, "You can't report your own post");

    // block hides them on the server's Home too; Undo restores follow
    final target = c.items.firstWhere((i) => i.actor.id != me.id).actor;
    await c.block(target, wasFollowing: true);
    expect((await repo.home()).items.any((i) => i.actor.id == target.id), isFalse);
    await c.unblock(target, wasFollowing: true);
    expect((await repo.home()).items.any((i) => i.actor.id == target.id), isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  // aman_s follows nobody in the seed, so his Home is empty.
  test('app ⇄ backend: suggested people, follow, retry refusals and a real 429',
      skip: skip, () async {
    final repo = ApiFeedRepository(ApiClient(baseUrl: _live, devUser: 'aman_s'));
    final c = FeedController(repo);
    addTearDown(c.dispose);

    // an empty Home leads to suggestions
    await c.refresh(); // an empty Home starts loading the suggestions by itself
    expect(c.items, isEmpty);
    for (var i = 0; i < 50 && c.suggestions == null && c.suggestionsError == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(c.suggestionsError, isNull);
    final people = c.suggestions!;
    expect(people, isNotEmpty);
    expect(people.any((p) => p.user.username == 'aman_s'), isFalse, reason: 'never yourself');
    final target = people.first.user;

    // follow, then it is no longer suggested; unfollow brings it back
    await c.toggleFollow(target);
    expect(c.isFollowing(target), isTrue);
    expect((await repo.suggestedUsers()).any((p) => p.user.id == target.id), isFalse);
    await c.toggleFollow(target);
    expect((await repo.suggestedUsers()).any((p) => p.user.id == target.id), isTrue);

    // retry on a post that is not yours / not failed: refused with a readable message
    await expectLater(
      repo.retryPost('does-not-exist'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)),
    );

    // hammer the follow limit (60 a minute) until the server says 429
    ApiException? limited;
    for (var i = 0; i < 90 && limited == null; i++) {
      try {
        await repo.setFollowing(target.id, false);
      } on ApiException catch (e) {
        limited = e;
      }
    }
    expect(limited, isNotNull, reason: 'the server rate-limits follow actions');
    expect(limited!.isRateLimited, isTrue);
    expect(limited.message, isNotEmpty);
    expect(limited.retryAfterSec, isNotNull, reason: 'Retry-After / retryAfterSec was read');
    // ignore: avoid_print
    print('429 from the real server: "${limited.message}" retry after ${limited.retryAfterSec}s');
  }, timeout: const Timeout(Duration(minutes: 2)));
}

// Sign up with a fresh phone number (the dev SMS provider hands the code back as `devCode`), log in again
// with the password, and use the token for Home and Discover. Needs a server in development mode.
void _liveAuthAndDiscover(String? skip) {
  test('app ⇄ backend: sign-up, login, Discover with a real token, delete account', skip: skip, () async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final phone = '+9199${(stamp % 100000000).toString().padLeft(8, '0')}';
    final username = 'live_${stamp % 1000000000}';
    const password = 'live-test-password-1';

    String? token;
    final anon = ApiClient(baseUrl: _live, devUser: '', tokenProvider: () => token);
    final auth = AuthRepository(anon);

    final sent = await auth.sendCode(phone);
    expect(sent.devCode, isNotNull, reason: 'run the server in development mode (no NODE_ENV=production)');
    final signupToken = await auth.verifyCode(sent.contact, sent.devCode!);
    final created = await auth.signUp(
      signupToken: signupToken, fullName: 'Live Test', username: username, dob: '2000-01-01', password: password,
    );
    token = created.token;
    expect(created.user.username, username);

    // the token works; the same number cannot sign up twice
    expect((await ApiFeedRepository(anon).me()).username, username);
    await expectLater(auth.sendCode(phone), throwsA(isA<ApiException>().having((e) => e.field, 'field', 'phone')));

    // log in again from "another phone"
    final second = await AuthRepository(ApiClient(baseUrl: _live, devUser: '')).login(username, password);
    expect(second.user.id, created.user.id);
    await expectLater(
      AuthRepository(ApiClient(baseUrl: _live, devUser: '')).login(username, 'wrong-password-123'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
    );

    // Discover through the shared client: feed, then like/unlike the first video
    final reels = ReelsRepository(anon);
    final page = await reels.getFeed(limit: 5);
    expect(page.videos, isNotEmpty);
    final first = page.videos.first;
    expect(first.filename, isNotEmpty);
    expect(await reels.setLike(first.id), greaterThan(0));
    expect(await reels.deleteLike(first.id), greaterThanOrEqualTo(0));
    expect((await reels.getTree(first.id)).first.id, first.id);

    // delete the account: wrong password refused (and does not look like an expired login), then it is gone
    await expectLater(auth.deleteAccount('not-the-password'), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)));
    await auth.deleteAccount(password);
    await expectLater(ApiFeedRepository(anon).me(), throwsA(isA<ApiException>().having((e) => e.isUnauthorized, '401', true)));
  });
}
