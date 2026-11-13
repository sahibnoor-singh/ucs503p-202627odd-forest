// Which font draws which letters. The three text fonts (Roboto and the two DejaVu ones) only have Latin letters; Hindi
// (Devanagari), Punjabi (Gurmukhi) and emoji come from extra fonts that are switched on for just those letters with an ASS \fn tag.
// libass does not look in the fonts/ folder for a missing letter on its own (on Windows and macOS it finds one in the
// system, on the Linux server there is nothing to find and an empty box is drawn), so the switch is written out.
//
// Colour emoji (Noto Color Emoji) cannot be used: libass cannot draw its bitmap letters. Noto Emoji is the one-colour
// version: emoji come out in the text colour with the usual outline.

/** Extra fonts, by the name used here -> family name inside the file, and the file in assets/fonts. */
const EXTRA_FONTS = {
  deva: { family: 'Noto Sans Devanagari', file: 'NotoSansDevanagari-Bold.ttf' },
  guru: { family: 'Noto Sans Gurmukhi', file: 'NotoSansGurmukhi-Bold.ttf' },
  emoji: { family: 'Noto Emoji', file: 'NotoEmoji-Variable.ttf' }
};

const segmenter = typeof Intl !== 'undefined' && Intl.Segmenter ? new Intl.Segmenter(undefined, { granularity: 'grapheme' }) : null;

const ZWJ = String.fromCodePoint(0x200d); // zero width joiner and non-joiner: invisible, they glue and unglue letters
const ZWNJ = String.fromCodePoint(0x200c);
const VS16 = String.fromCodePoint(0xfe0f); // 'show this as an emoji'
const KEYCAP_SQUARE = String.fromCodePoint(0x20e3);
const VIRAMA = 0x094d;
const isDevaConsonant = (cp) => (cp >= 0x0915 && cp <= 0x0939) || (cp >= 0x0958 && cp <= 0x095f);

/**
 * The text as the letters a person sees: a family emoji is one, and so is a Hindi conjunct such as "स्त" (s + virama + t).
 * Older Unicode data (older Node) cuts a conjunct after its virama, which would pull it apart when it is revealed letter by
 * letter and break its shaping, so such pieces are joined here. Falls back to code points where there is no segmenter.
 */
function graphemes(text) {
  const parts = segmenter ? [...segmenter.segment(text)].map((s) => s.segment) : [...text];
  const out = [];
  for (const part of parts) {
    const last = out[out.length - 1];
    if (last !== undefined) {
      const tail = [...last].filter((ch) => ch !== ZWJ && ch !== ZWNJ).pop();
      if (tail && tail.codePointAt(0) === VIRAMA && isDevaConsonant(part.codePointAt(0))) {
        out[out.length - 1] = last + part;
        continue;
      }
    }
    out.push(part);
  }
  return out;
}

const EMOJI = /\p{Extended_Pictographic}/u;
const KEYCAP = new RegExp(`^[0-9#*]${VS16}?${KEYCAP_SQUARE}`); // 1, 2, # ... with an optional emoji marker and the square

/** 'deva', 'guru', 'emoji', or 'default' (letters the three text fonts can draw, spaces, digits and punctuation). */
function scriptOf(grapheme) {
  const cp = grapheme.codePointAt(0);
  if ((cp >= 0x0900 && cp <= 0x097f) || (cp >= 0xa8e0 && cp <= 0xa8ff)) return 'deva';
  if (cp >= 0x0a00 && cp <= 0x0a7f) return 'guru';
  if (KEYCAP.test(grapheme)) return 'emoji';
  if ((cp >= 0x2190 || cp >= 0x1f000) && EMOJI.test(grapheme)) return 'emoji';
  return 'default';
}

/**
 * Writes text as ASS: control characters made safe by [esc], and a font tag at each change of script (spaces, digits and
 * punctuation count as the text's own font). Keeps track of the font it is in, so text can be handed over a piece at a time
 * (the animations reveal it letter by letter or word by word).
 * [used] collects the extra fonts that were needed, so only those files are copied beside the render.
 */
function fontWriter(family, esc, used = new Set()) {
  let current = 'default';
  const tag = (font) => `{\\fn${font === 'default' ? family : EXTRA_FONTS[font].family}}`;
  return {
    used,
    write(text) {
      let out = '';
      let run = '';
      const flush = () => {
        if (run) out += esc(run);
        run = '';
      };
      for (const g of graphemes(text)) {
        const font = scriptOf(g);
        if (font !== current) {
          flush();
          out += tag(font);
          current = font;
          if (font !== 'default') used.add(font);
        }
        run += g;
      }
      flush();
      return out;
    }
  };
}

module.exports = { EXTRA_FONTS, graphemes, scriptOf, fontWriter };
