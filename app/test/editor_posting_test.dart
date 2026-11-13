// Posting something made in the editor: the recipe and files go to the repository, a reply or a new opinion comes back
// PROCESSING, and the controller polls it until it is READY.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:forest_app/data/api_feed_repository.dart';
import 'package:forest_app/data/fake_feed_repository.dart';
import 'package:forest_app/features/editor/recipe.dart';
import 'package:forest_app/features/home/feed_controller.dart';
import 'package:forest_app/models/post.dart';
import 'package:forest_app/services/api_client.dart';

({FakeFeedRepository repo, FeedController c, List<ToastEvent> toasts}) _make() {
  final repo = FakeFeedRepository.sample(now: DateTime.utc(2026, 10, 10, 12));
  final c = FeedController(repo, pollInterval: const Duration(milliseconds: 5));
  final toasts = <ToastEvent>[];
  c.toasts.listen(toasts.add);
  addTearDown(c.dispose);
  return (repo: repo, c: c, toasts: toasts);
}

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 60));

const _textRecipe = Recipe(
  mode: EditorMode.text,
  durationSec: 6,
  text: TextSpec(content: 'Should exams be open-book?'),
  background: Background.gradient(Color(0xFF0F2027), Color(0xFF2C5364), angle: 180),
);

void main() {
  test('a new opinion goes out with the recipe, title and caption, and comes back processing', () async {
    final t = _make();
    await t.c.refresh();
    final item = await t.c.compose(recipe: _textRecipe, title: 'Open-book exams?', body: 'my view');
    expect(item.post.status, PostStatus.processing);
    expect(item.post.parentId, isNull);
    expect(t.repo.log, contains('compose:root'));
    final sent = t.repo.composed.single;
    expect(sent['title'], 'Open-book exams?');
    expect(sent['body'], 'my view');
    expect((sent['recipe'] as Map)['mode'], 'TEXT');
    await Future<void>.delayed(Duration.zero);
    expect(t.toasts.map((e) => e.message), contains('Posted. Making your video now.'));
  });

  test('a reply is attached to its parent, and counted once it is ready', () async {
    final t = _make();
    await t.c.refresh();
    final parent = t.c.items.firstWhere((i) => i.post.id == 'p1').post;
    final before = t.c.resolve(parent).replyCount;
    final item = await t.c.compose(parent: parent, recipe: const Recipe(mode: EditorMode.video), videoPath: '/tmp/a.mp4', videoSeconds: 12);
    expect(item.post.parentId, 'p1');
    expect(t.repo.composed.single['videoPath'], '/tmp/a.mp4');
    expect(t.c.resolve(parent).replyCount, before, reason: 'not counted while it is still being made');
    await _flush();
    expect(t.c.resolve(parent).replyCount, before + 1);
    expect(t.toasts.map((e) => e.message), contains(startsWith('Your video reply is ready')));
  });

  test('a new opinion says it is ready when it is, with nothing to count', () async {
    final t = _make();
    await t.c.refresh();
    await t.c.compose(recipe: _textRecipe);
    await _flush();
    expect(t.toasts.map((e) => e.message), contains('Your post is ready.'));
  });

  test('a failure is thrown so the editor can show it and stay open', () async {
    final t = _make();
    await t.c.refresh();
    t.repo.failNext = const ApiException('Text can be at most 280 characters.', statusCode: 400);
    expect(() => t.c.compose(recipe: _textRecipe), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('280'))));
  });

  test('photos, music and the video are sent as separate files with the recipe as JSON', () async {
    late http.BaseRequest seen;
    final bodies = <String>[];
    final client = MockClient.streaming((request, bodyStream) async {
      seen = request;
      bodies.add(utf8.decode(await bodyStream.toBytes(), allowMalformed: true));
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({
          'type': 'POST',
          'actor': {'id': 'u1', 'username': 'dev', 'fullName': 'Dev', 'avatarUrl': null, 'isBot': false},
          'post': {
            'id': 'n1', 'kind': 'VIDEO', 'parentId': null, 'rootId': 'n1', 'depth': 0, 'title': null, 'body': null, 'mediaUrl': null,
            'stance': 'PARENT', 'status': 'PROCESSING', 'summary': null, 'createdAt': '2026-10-10T12:00:00.000Z',
            'likeCount': 0, 'likedByMe': false, 'replyCount': 0, 'forCount': 0, 'againstCount': 0,
          },
          'parent': null,
          'root': null,
          'createdAt': '2026-10-10T12:00:00.000Z',
        }))),
        201,
        headers: {'content-type': 'application/json'},
      );
    });
    final dir = Directory.systemTemp.createTempSync('forest_editor_test').path;
    final a = await _file(dir, 'a.jpg');
    final b = await _file(dir, 'b.jpg');
    final song = await _file(dir, 'song.mp3');
    final repo = ApiFeedRepository(ApiClient(baseUrl: 'http://test.invalid', devUser: '', client: client));

    final item = await repo.compose(
      recipe: const Recipe(mode: EditorMode.photos, photoCount: 2, music: MusicSpec(volume: .5)),
      title: '  A title  ',
      body: '   ',
      photoPaths: [a, b],
      musicPath: song,
    );
    expect(item.post.status, PostStatus.processing);
    expect(seen.method, 'POST');
    expect(seen.url.path, '/api/posts/compose');
    final body = bodies.single;
    expect(RegExp('name="photos"').allMatches(body).length, 2, reason: 'one form part per photo');
    expect(body, contains('name="music"'));
    expect(body, isNot(contains('name="video"')));
    expect(body, contains('name="title"'));
    expect(body, contains('A title'));
    expect(body, isNot(contains('name="body"')), reason: 'a blank caption is not sent');
    expect(body, contains('"mode":"PHOTOS"'));
    expect(body, contains('"music":{"volume":0.5,"startSec":0.0}'));
  });
}

Future<String> _file(String dir, String name) async {
  final f = File('$dir/$name')..writeAsBytesSync(List.filled(16, 1));
  return f.path;
}
