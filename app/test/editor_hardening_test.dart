// What the editor does when things go wrong around it: a picker that cannot open, a permission that is refused.

import 'package:flutter_test/flutter_test.dart';

import 'package:forest_app/features/editor/editor_controller.dart';
import 'package:forest_app/features/editor/editor_pickers.dart';
import 'package:forest_app/features/editor/recipe.dart';

class _BrokenPickers implements EditorPickers {
  @override
  Future<List<String>> photos({required int limit}) => throw StateError('no permission');

  @override
  Future<PickedVideo?> galleryVideo() => throw StateError('no permission');

  @override
  Future<PickedMusic?> music() => throw StateError('no permission');
}

void main() {
  test('a photo picker that cannot open says so instead of crashing', () async {
    final c = EditorController(mode: EditorMode.photos, pickers: _BrokenPickers());
    addTearDown(c.dispose);
    await c.pickMorePhotos();
    expect(c.photos, isEmpty);
    expect(c.notice, contains('Could not open your photos'));
  });

  test('a video picker that cannot open says so', () async {
    final c = EditorController(mode: EditorMode.video, pickers: _BrokenPickers());
    addTearDown(c.dispose);
    await c.pickGalleryVideo();
    expect(c.videoPath, isNull);
    expect(c.notice, contains('Could not open your videos'));
  });

  test('a music picker that cannot open says so', () async {
    final c = EditorController(mode: EditorMode.text, pickers: _BrokenPickers());
    addTearDown(c.dispose);
    await c.pickMusic();
    expect(c.musicPath, isNull);
    expect(c.notice, contains('Could not open your files'));
  });
}
