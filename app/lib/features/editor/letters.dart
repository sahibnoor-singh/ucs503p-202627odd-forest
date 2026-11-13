/// Which letters the server can draw on a picture (see `app/backend/assets/fonts/README.md`): Latin letters, Hindi (Devanagari),
/// Punjabi (Gurmukhi) and emoji. Anything else would come out as empty boxes in the posted video.
class LetterCheck {
  const LetterCheck({required this.unsupported, required this.hasEmoji});

  /// Some letter has no font on the server.
  final bool unsupported;

  /// The text has emoji. They are drawn in one colour (the text's), not in colour as on the phone.
  final bool hasEmoji;

  /// A message for the person, or null when there is nothing to say.
  String? get message {
    if (unsupported) return 'Only English, Hindi, Punjabi and emoji can be drawn on the picture. Other letters would show as boxes.';
    if (hasEmoji) return 'Emoji are drawn in one colour in the posted video.';
    return null;
  }
}

/// Emoji and the symbols that the server draws with its emoji font (an approximation of Unicode's "Extended Pictographic").
bool _isEmoji(int cp) =>
    (cp >= 0x1f000 && cp <= 0x1faff) || // pictures, faces, hands, food, transport ...
    (cp >= 0x2600 && cp <= 0x27bf) || // sun, heart, check marks, stars, scissors ...
    (cp >= 0x2300 && cp <= 0x23ff) || // watch, hourglass, play buttons
    (cp >= 0x2b00 && cp <= 0x2bff) || // big stars and squares
    (cp >= 0x2194 && cp <= 0x21aa) || // some arrows
    cp == 0x2934 ||
    cp == 0x2935 ||
    cp == 0x3030 ||
    cp == 0x303d ||
    cp == 0x3297 ||
    cp == 0x3299;

bool _inRanges(int cp) =>
    cp <= 0x024f || // Latin, digits, punctuation
    (cp >= 0x0300 && cp <= 0x036f) || // accents that sit on a letter
    (cp >= 0x0900 && cp <= 0x097f) || // Hindi
    (cp >= 0xa8e0 && cp <= 0xa8ff) ||
    (cp >= 0x0a00 && cp <= 0x0a7f) || // Punjabi
    (cp >= 0x2000 && cp <= 0x206f) || // general punctuation (quotes, dashes, joiners)
    (cp >= 0x20a0 && cp <= 0x20cf); // currency

LetterCheck checkLetters(String text) {
  var unsupported = false;
  var emoji = false;
  for (final cp in text.runes) {
    if (cp == 0x20e3) {
      emoji = true; // the square round a keycap digit
      continue;
    }
    if (cp == 0x200d || cp == 0xfe0f || (cp >= 0x1f3fb && cp <= 0x1f3ff)) {
      continue; // pieces of an emoji
    }
    if (_isEmoji(cp)) {
      emoji = true;
      continue;
    }
    if (!_inRanges(cp)) unsupported = true;
  }
  return LetterCheck(unsupported: unsupported, hasEmoji: emoji);
}
