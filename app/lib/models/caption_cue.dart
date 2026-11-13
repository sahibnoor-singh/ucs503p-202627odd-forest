/// One subtitle line, shown while the video position is in [start] ≤ position < [end].
class CaptionCue {
  const CaptionCue({required this.start, required this.end, required this.text});

  final Duration start;
  final Duration end;
  final String text;

  /// Reads the server's `[{ "start": 1.5, "end": 3, "text": "…" }]` (seconds). Anything that is not a usable line is
  /// skipped, and the result is sorted by start. Anything that is not a list gives an empty list.
  static List<CaptionCue> listFrom(Object? raw) {
    if (raw is! List) return const [];
    final cues = <CaptionCue>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final start = item['start'];
      final end = item['end'];
      final text = item['text'];
      if (start is! num || end is! num || text is! String) continue;
      if (!start.isFinite || !end.isFinite || end <= start || text.trim().isEmpty) continue;
      cues.add(CaptionCue(
        start: Duration(milliseconds: (start * 1000).round()),
        end: Duration(milliseconds: (end * 1000).round()),
        text: text.trim(),
      ));
    }
    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  /// The line to show at [position], or null in the gaps between lines. [cues] must be sorted by start.
  static CaptionCue? at(List<CaptionCue> cues, Duration position) {
    var lo = 0;
    var hi = cues.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final cue = cues[mid];
      if (position < cue.start) {
        hi = mid - 1;
      } else if (position >= cue.end) {
        lo = mid + 1;
      } else {
        return cue;
      }
    }
    return null;
  }
}

/// A language subtitles can be shown in. The server sends the same list with every captions response.
class CaptionLanguage {
  const CaptionLanguage(this.code, this.name, this.native);

  final String code;
  final String name;
  final String native;

  /// "हिन्दी (Hindi)", or just "English".
  String get label => native == name ? name : '$native ($name)';
}

const List<CaptionLanguage> kCaptionLanguages = [
  CaptionLanguage('en', 'English', 'English'),
  CaptionLanguage('hi', 'Hindi', 'हिन्दी'),
  CaptionLanguage('pa', 'Punjabi', 'ਪੰਜਾਬੀ'),
  CaptionLanguage('bn', 'Bengali', 'বাংলা'),
  CaptionLanguage('ta', 'Tamil', 'தமிழ்'),
  CaptionLanguage('te', 'Telugu', 'తెలుగు'),
  CaptionLanguage('mr', 'Marathi', 'मराठी'),
  CaptionLanguage('gu', 'Gujarati', 'ગુજરાતી'),
];

/// English name of a language code ("hi" → "Hindi"). Unknown codes are shown upper-case.
String captionLanguageName(String? code) {
  if (code == null || code.isEmpty) return '';
  for (final l in kCaptionLanguages) {
    if (l.code == code) return l.name;
  }
  const more = {'ur': 'Urdu', 'es': 'Spanish', 'fr': 'French', 'de': 'German', 'ar': 'Arabic', 'ne': 'Nepali', 'kn': 'Kannada', 'ml': 'Malayalam'};
  return more[code] ?? code.toUpperCase();
}

/// The subtitle lines of one post in one language, as the server sends them.
class CaptionTrack {
  const CaptionTrack({required this.cues, this.language});

  final List<CaptionCue> cues;

  /// What is spoken in the video (ISO 639-1), when the server knows.
  final String? language;

  static CaptionTrack fromJson(Object? body) {
    if (body is! Map) return const CaptionTrack(cues: []);
    final language = body['language'];
    return CaptionTrack(
      cues: CaptionCue.listFrom(body['captions']),
      language: language is String && language.isNotEmpty ? language : null,
    );
  }
}
