// Replying with the editor: the Reply sheet's video options open the editor for that post, and what is made goes out as a reply.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:forest_app/features/editor/editor_screen.dart';

import 'support/harness.dart';

void main() {
  testWidgets('Reply → Upload video → Text card opens the editor for a reply, and Post sends it to that post', (tester) async {
    useTallScreen(tester);
    final repo = sampleRepo();
    await pumpHome(tester, repo);

    await tester.tap(find.text('Reply').first);
    await settle(tester);
    expect(find.text('Photos'), findsNothing, reason: 'the options are hidden until Upload video is tapped');
    await tester.tap(find.text('Upload video'));
    await settle(tester);
    for (final option in ['Record', 'Gallery', 'Photos', 'Text card']) {
      expect(find.text(option), findsOneWidget, reason: option);
    }

    await tester.tap(find.text('Text card'));
    await settle(tester);
    expect(find.byType(EditorScreen), findsOneWidget);
    expect(find.text('Reply to @kabir_m'), findsWidgets);

    // the Text tool is the second one
    await tester.tap(find.descendant(of: find.byType(EditorScreen), matching: find.text('Text'))); // not the sheet's own Text pill underneath
    await settle(tester);
    await tester.enterText(find.descendant(of: find.byType(EditorScreen), matching: find.byType(TextField)).first, 'I disagree, and here is why.');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Post'));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    final fake = repo;
    expect(fake.composed, hasLength(1));
    expect(fake.composed.single['parentId'], isNotNull);
    expect(fake.composed.single['title'], isNull, reason: 'a reply has no question of its own');
    expect(find.byType(EditorScreen), findsNothing, reason: 'the editor and the sheet both close');
    expect(find.text('Reply to @kabir_m'), findsNothing);
  });
}
