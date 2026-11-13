// The photo preview starts its slideshow when photos are added to the (same, changed-in-place) list.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:forest_app/features/editor/photo_post_preview.dart';
import 'package:forest_app/features/editor/recipe.dart';

void main() {
  testWidgets('adding photos to the list the preview already holds makes the slideshow move on', (tester) async {
    final photos = <String>[]; // like EditorController.photos: one list, changed in place
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Scaffold(
              body: PhotoPostPreview(photos: photos, recipe: const Recipe(mode: EditorMode.photos, slideSeconds: 1)),
            );
          },
        ),
      ),
    );
    rebuild(() => photos.addAll(['/a.jpg', '/b.jpg']));
    await tester.pump();

    String shown() => ((tester.widgetList<Image>(find.byType(Image)).last.image) as ResizeImage).imageProvider is FileImage
        ? (((tester.widgetList<Image>(find.byType(Image)).last.image) as ResizeImage).imageProvider as FileImage).file.path
        : '';
    expect(shown(), '/a.jpg');
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 600)); // the fade
    expect(shown(), '/b.jpg');
    expect(File('/a.jpg').existsSync(), isFalse, reason: 'the files are not real; the preview only shows a broken-image icon');
  });
}
