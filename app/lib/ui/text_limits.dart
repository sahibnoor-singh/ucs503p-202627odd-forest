import 'package:flutter/services.dart';

/// Reply text limit from docs/api.md. The server counts characters as code
/// points (an emoji is one), so the app does too.
const int maxReplyChars = 280;

int runeCount(String text) => text.runes.length;

/// Stops typing and pasting past [max] characters, counted like the server does.
class RuneLimitFormatter extends TextInputFormatter {
  const RuneLimitFormatter(this.max);

  final int max;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (runeCount(newValue.text) <= max) return newValue;
    final cut = String.fromCharCodes(newValue.text.runes.take(max));
    return TextEditingValue(
      text: cut,
      selection: TextSelection.collapsed(offset: cut.length),
    );
  }
}
