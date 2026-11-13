// Which letters the editor tells people the server can draw.

import 'package:flutter_test/flutter_test.dart';

import 'package:forest_app/features/editor/letters.dart';

void main() {
  test('English, Hindi, Punjabi, numbers and punctuation are fine and need no message', () {
    for (final text in ['Hello, world! 100% (yes) - "quoted" Rs. 5', 'नमस्ते दुनिया।', 'ਸਤ ਸ੍ਰੀ ਅਕਾਲ', 'café naïve', 'it’s – ok …']) {
      final c = checkLetters(text);
      expect(c.unsupported, isFalse, reason: text);
      expect(c.hasEmoji, isFalse, reason: text);
      expect(c.message, isNull, reason: text);
    }
  });

  test('emoji are allowed but the person is told they lose their colour', () {
    for (final text in ['great 👍', '❤️', '👨‍👩‍👧', '1️⃣ first', 'ok 👍🏽']) {
      final c = checkLetters(text);
      expect(c.unsupported, isFalse, reason: text);
      expect(c.hasEmoji, isTrue, reason: text);
      expect(c.message, contains('one colour'), reason: text);
    }
  });

  test('letters with no font on the server are called out, and win over the emoji note', () {
    for (final text in ['வணக்கம்', 'مرحبا', '你好', 'Привет', 'hi வணக்கம் 😀']) {
      final c = checkLetters(text);
      expect(c.unsupported, isTrue, reason: text);
      expect(c.message, contains('boxes'), reason: text);
    }
  });
}
