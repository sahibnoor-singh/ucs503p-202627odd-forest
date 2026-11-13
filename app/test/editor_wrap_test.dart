// Text wraps in the preview the way the server's renderer wraps it: evened out, and never after a hyphen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:forest_app/features/editor/overlay_layer.dart';

void main() {
  test('serverWrap stops a line breaking after a hyphen, and leaves other text alone', () {
    expect(serverWrap('open-book'), 'open-⁠book');
    expect(serverWrap('plain words'), 'plain words');
    expect(serverWrap('trailing-'), 'trailing-');
  });

  testWidgets('a two-line text is laid out in the narrowest width that still takes two lines', (tester) async {
    const style = TextStyle(fontSize: 20); // the test font gives every letter the same width: 20 px
    final text = serverWrap('Exams should be open-book');
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300, // fits "Exams should be" (15 letters) on the first line when filled greedily
            child: Align(
              alignment: Alignment.center,
              child: BalancedBox(text: text, style: style, child: Text(text, key: const Key('t'), style: style, textAlign: TextAlign.center)),
            ),
          ),
        ),
      ),
    );
    final size = tester.getSize(find.byKey(const Key('t')));
    // evened out: "Exams should" over "be open-book", 12 letters a line, not 15 over 9
    expect(size.width, lessThan(260));
    expect(size.width, greaterThanOrEqualTo(240));
    expect(size.height, closeTo(2 * 20 * 1.0, 40), reason: 'still two lines');
  });

  testWidgets('a text that fits on one line keeps its own width', (tester) async {
    const style = TextStyle(fontSize: 20);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            child: Align(child: BalancedBox(text: 'short', style: style, child: Text('short', key: const Key('t'), style: style))),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(const Key('t'))).width, closeTo(100, 3));
  });
}
