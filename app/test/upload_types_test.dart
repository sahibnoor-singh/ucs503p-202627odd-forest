// Files go up with the type the server's upload check wants. (Left alone, package:http sends application/octet-stream, which the
// server refuses for photos: a photo post from a phone was rejected with "Photos must be one of ...".)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:forest_app/services/api_client.dart';

void main() {
  test('each kind of file the editor sends gets its own type', () {
    expect(uploadTypeOf('/cache/abc/34.jpg').mimeType, 'image/jpeg');
    expect(uploadTypeOf('/cache/abc/Photo.JPEG').mimeType, 'image/jpeg', reason: 'capitals do not matter');
    expect(uploadTypeOf('a.png').mimeType, 'image/png');
    expect(uploadTypeOf('a.webp').mimeType, 'image/webp');
    expect(uploadTypeOf('/x/clip.mp4').mimeType, 'video/mp4');
    expect(uploadTypeOf('clip.mov').mimeType, 'video/quicktime');
    expect(uploadTypeOf('song.mp3').mimeType, 'audio/mpeg');
    expect(uploadTypeOf('song.m4a').mimeType, 'audio/mp4');
    expect(uploadTypeOf('mystery').mimeType, 'application/octet-stream');
    expect(uploadTypeOf('/a.b/mystery').mimeType, 'application/octet-stream', reason: 'a dot in a folder name is not an extension');
  });

  test('postMultipartFiles puts the type on every file part', () async {
    final dir = Directory.systemTemp.createTempSync('forest_upload');
    addTearDown(() => dir.deleteSync(recursive: true));
    final photo = File('${dir.path}/34.jpg')..writeAsBytesSync([1, 2, 3]);
    final song = File('${dir.path}/song.mp3')..writeAsBytesSync([4, 5]);

    String? body;
    final client = MockClient((request) async {
      body = request.body;
      return http.Response('{}', 200, headers: {'content-type': 'application/json'});
    });
    final api = ApiClient(baseUrl: 'http://api.test', devUser: 'me', client: client);
    await api.postMultipartFiles('/api/posts/compose', fields: {'recipe': '{}'}, files: [
      (field: 'photos', path: photo.path),
      (field: 'music', path: song.path),
    ]);
    expect(body, contains('content-type: image/jpeg'));
    expect(body, contains('content-type: audio/mpeg'));
    expect(body, isNot(contains('application/octet-stream')));
  });
}
