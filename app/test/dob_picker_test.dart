import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:forest_app/features/auth/dob_picker.dart';
import 'package:forest_app/theme/forest_theme.dart';

/// A button that opens the sheet and remembers what came back.
Widget _host(void Function(DateTime?) got, {DateTime? initial, ThemeData? theme}) => MaterialApp(
      theme: theme ?? ForestTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('open'),
              onPressed: () async => got(await pickDateOfBirth(context, initial: initial, today: DateTime(2026, 10, 21))),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

void main() {
  test('dates read as 21 Oct 2006', () {
    expect(friendlyDate(DateTime(2006, 10, 21)), '21 Oct 2006');
    expect(friendlyDate(DateTime(1999, 1, 5)), '5 Jan 1999');
  });

  testWidgets('opens on about twenty years ago, and Done without touching the wheels keeps that date', (tester) async {
    DateTime? got;
    await tester.pumpWidget(_host((d) => got = d));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    expect(find.text('Date of birth'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dob-done')));
    await tester.pumpAndSettle();
    expect(got, DateTime(2006, 10, 21));
  });

  testWidgets('it opens on the date already chosen, and a date in the future is pulled back to today', (tester) async {
    DateTime? got;
    await tester.pumpWidget(_host((d) => got = d, initial: DateTime(1999, 3, 14)));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dob-done')));
    await tester.pumpAndSettle();
    expect(got, DateTime(1999, 3, 14));

    await tester.pumpWidget(_host((d) => got = d, initial: DateTime(2030, 1, 1)));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dob-done')));
    await tester.pumpAndSettle();
    expect(got, DateTime(2026, 10, 21));
  });

  testWidgets('dragging the year wheel changes the date that Done returns', (tester) async {
    DateTime? got;
    await tester.pumpWidget(_host((d) => got = d));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    final year = find.text('2006');
    expect(year, findsOneWidget);
    await tester.drag(year, const Offset(0, 120)); // drag down: earlier years
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dob-done')));
    await tester.pumpAndSettle();
    expect(got!.year, lessThan(2006));
    expect(got!.month, 10);
  });

  testWidgets('dismissing the sheet returns nothing, and it works in dark mode too', (tester) async {
    DateTime? got = DateTime(2000);
    await tester.pumpWidget(_host((d) => got = d, theme: ForestTheme.dark));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10)); // the dimmed area above the sheet
    await tester.pumpAndSettle();
    expect(got, isNull);
  });
}
