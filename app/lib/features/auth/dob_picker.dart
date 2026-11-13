import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../theme/forest_theme.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// `21 Oct 2006`, how the chosen date reads in the form (the server gets `2006-10-21`, see SignupController.formatDob).
String friendlyDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// A bottom sheet with three wheels (month, day, year) that you drag up or down, instead of a calendar grid.
/// Returns the date when the person taps **Done**, or null when they dismiss the sheet. It opens on [initial] (about 20 years ago
/// if none), and Done without touching the wheels keeps that date, so the person always sees what they are choosing.
Future<DateTime?> pickDateOfBirth(BuildContext context, {DateTime? initial, DateTime? today}) {
  final now = today ?? DateTime.now();
  final latest = DateTime(now.year, now.month, now.day);
  final earliest = DateTime(now.year - 100, now.month, now.day);
  var chosen = initial ?? DateTime(now.year - 20, now.month, now.day);
  if (chosen.isAfter(latest)) chosen = latest;
  if (chosen.isBefore(earliest)) chosen = earliest;
  final t = context.forest;
  final theme = Theme.of(context);

  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: t.raised,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(child: Text('Date of birth', style: TextStyle(color: t.fg, fontSize: 20, fontWeight: FontWeight.w800))),
              TextButton(
                key: const Key('dob-done'),
                onPressed: () => Navigator.of(sheetContext).pop(chosen),
                child: Text('Done', style: TextStyle(color: t.accent, fontSize: 17, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 4),
            SizedBox(
              height: 216,
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: theme.brightness,
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(color: t.fg, fontSize: 21, fontFamily: theme.textTheme.bodyMedium?.fontFamily),
                  ),
                ),
                child: CupertinoDatePicker(
                  key: const Key('dob-wheels'),
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: chosen,
                  minimumDate: earliest,
                  maximumDate: latest,
                  backgroundColor: t.raised,
                  onDateTimeChanged: (d) => chosen = DateTime(d.year, d.month, d.day),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
