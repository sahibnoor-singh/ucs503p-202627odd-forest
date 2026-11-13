Fonts used when the server renders text onto posts (text mode and text overlays). They are copied next to each render, so no system fonts are needed (the Linux server has none to offer).

| File | Family name (used in the ASS file) | For | Licence |
|---|---|---|---|
| Roboto-Bold.ttf | Roboto | Latin letters, "Sans" | Apache 2.0 |
| DejaVuSerif-Bold.ttf | DejaVu Serif | Latin letters, "Serif" | Bitstream Vera / DejaVu (free to redistribute) |
| DejaVuSansMono-Bold.ttf | DejaVu Sans Mono | Latin letters, "Mono" | Bitstream Vera / DejaVu (free to redistribute) |
| NotoSansDevanagari-Bold.ttf | Noto Sans Devanagari | Hindi | SIL OFL 1.1 (OFL-NotoSansDevanagari.txt) |
| NotoSansGurmukhi-Bold.ttf | Noto Sans Gurmukhi | Punjabi | SIL OFL 1.1 (OFL-NotoSansGurmukhi.txt) |
| NotoEmoji-Variable.ttf | Noto Emoji | Emoji, in one colour | SIL OFL 1.1 (OFL-NotoEmoji.txt) |

Which letters use which font is decided in `src/compose/scripts.js`: the text keeps its own font (Sans/Serif/Mono), and an ASS `\fn` tag switches to
the Hindi, Punjabi or emoji font for just those letters. libass will not pick them up by itself on the Linux server.

Notes
- Emoji are drawn in the text colour with the usual outline. The colour version (Noto Color Emoji) is a bitmap font that libass cannot draw.
- Other scripts (Tamil, Arabic, Chinese ...) still show as boxes. To add one: put a Bold `.ttf` here (Noto Sans <Script> is a good source),
  add it to `EXTRA_FONTS` and `scriptOf` in `scripts.js`, and add its letter range to the app's warning (`lib/features/editor/letters.dart`).
- The fonts came from github.com/notofonts and github.com/googlefonts/noto-emoji (the monochrome one from github.com/google/fonts, ofl/notoemoji).
