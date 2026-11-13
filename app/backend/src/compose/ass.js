// Draws the editor's text (the big text of a text post, and the small text overlays on any post) by writing an ASS
// subtitle file that ffmpeg's `ass` filter burns into the video. Why ASS and not ffmpeg's `drawtext`: the ffmpeg binary
// we ship (ffmpeg-static) is built without drawtext, but it has libass, which also does word wrapping, outlines and
// animation (fade, move, per-letter reveal) for us. One text engine, same result on every machine.
//
// The picture is always 720 x 1280 for text/photo posts, so sizes and positions below are in those pixels.

const { EXTRA_FONTS, graphemes, fontWriter } = require('./scripts');

const W = 720;
const H = 1280;

/** font option -> the family name inside the file, and the file in assets/fonts (copied beside each render). */
const FONTS = {
  sans: { family: 'Roboto', file: 'Roboto-Bold.ttf' },
  serif: { family: 'DejaVu Serif', file: 'DejaVuSerif-Bold.ttf' },
  mono: { family: 'DejaVu Sans Mono', file: 'DejaVuSansMono-Bold.ttf' }
};

/** "#rrggbb" -> ASS "&HBBGGRR&" (ASS stores colours blue-first). */
function assColor(hex) {
  const h = hex.replace('#', '');
  return `&H${h.slice(4, 6)}${h.slice(2, 4)}${h.slice(0, 2)}&`.toUpperCase();
}

/** h:mm:ss.cc */
function stamp(sec) {
  const cs = Math.max(0, Math.round(sec * 100));
  const h = Math.floor(cs / 360000);
  const m = Math.floor((cs % 360000) / 6000);
  const s = Math.floor((cs % 6000) / 100);
  return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}.${String(cs % 100).padStart(2, '0')}`;
}

/** Makes user text safe inside an ASS line: braces would start a tag, a backslash starts an escape. */
function esc(s) {
  return s.replace(/\\/g, '/').replace(/\{/g, '(').replace(/\}/g, ')').replace(/\n/g, '\\N');
}

const reveal = (ms) => `{\\alpha&HFF&\\t(${ms},${ms + 1},\\alpha&H00&)}`;

/** The text with an animation applied (see recipe.ANIMATIONS). Returns the "{tags}text" body of one dialogue line.
 *  [writer] (scripts.fontWriter) writes the letters with a font tag wherever Hindi or emoji start or stop. */
function animatedBody(t, durationSec, x, y, writer) {
  const an = { left: 4, center: 5, right: 6 }[t.align];
  const base = `\\an${an}\\fs${t.size}\\c${assColor(t.color)}`;
  const pos = `\\pos(${x},${y})`;
  switch (t.animation) {
    case 'fade':
      return `{${base}${pos}\\fad(700,0)}${writer.write(t.content)}`;
    case 'slideUp':
      return `{${base}\\move(${x},${y + 90},${x},${y},0,700)\\fad(700,0)}${writer.write(t.content)}`;
    case 'typewriter': {
      const chars = graphemes(t.content); // letters as people see them: a Hindi conjunct is revealed whole
      const step = Math.min(0.06, (durationSec * 0.6) / chars.length);
      const body = chars.map((ch, i) => (/\s/.test(ch) ? writer.write(ch) : `${reveal(Math.round(i * step * 1000))}${writer.write(ch)}`)).join('');
      return `{${base}${pos}}${body}`;
    }
    case 'wordByWord': {
      const parts = t.content.split(/(\s+)/).filter((p) => p !== '');
      const words = parts.filter((p) => !/^\s+$/.test(p)).length;
      const step = Math.min(0.35, (durationSec * 0.6) / words);
      let i = 0;
      const body = parts.map((p) => (/^\s+$/.test(p) ? writer.write(p) : `${reveal(Math.round(i++ * step * 1000))}${writer.write(p)}`)).join('');
      return `{${base}${pos}}${body}`;
    }
    default:
      return `{${base}${pos}}${writer.write(t.content)}`;
  }
}

const styleLine = (name, family) =>
  `Style: ${name},${family},64,&H00FFFFFF,&H00FFFFFF,&H00000000,&H64000000,-1,0,0,0,100,100,0,0,1,3,1,5,60,60,0,1`;

/**
 * @param recipe  a normalised recipe (recipe.js)
 * @returns {{ass: string, fonts: string[]} | null}  null when there is nothing to draw
 */
function buildAss(recipe) {
  const lines = [];
  const used = new Set();
  const extra = new Set(); // the Hindi / emoji fonts that some text needed

  if (recipe.mode === 'TEXT') {
    const t = recipe.text;
    used.add(t.font);
    const x = { left: 70, center: W / 2, right: W - 70 }[t.align];
    const writer = fontWriter(FONTS[t.font].family, esc, extra);
    lines.push(`Dialogue: 0,${stamp(0)},${stamp(recipe.durationSec)},${t.font},,0,0,0,,${animatedBody(t, recipe.durationSec, x, H / 2, writer)}`);
  }
  for (const o of recipe.overlays) {
    used.add(o.font);
    const x = Math.round(o.x * W);
    const y = Math.round(o.y * H);
    const writer = fontWriter(FONTS[o.font].family, esc, extra);
    lines.push(`Dialogue: 1,${stamp(o.startSec)},${stamp(o.endSec)},${o.font},,0,0,0,,` +
      `{\\an5\\pos(${x},${y})\\fs${o.size}\\c${assColor(o.color)}\\fad(200,200)}${writer.write(o.text)}`);
  }
  if (!lines.length) return null;

  const ass = [
    '[Script Info]', 'ScriptType: v4.00+', `PlayResX: ${W}`, `PlayResY: ${H}`, 'WrapStyle: 0', 'ScaledBorderAndShadow: yes', '',
    '[V4+ Styles]',
    'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding',
    ...Object.entries(FONTS).map(([name, f]) => styleLine(name, f.family)), '',
    '[Events]', 'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text',
    ...lines, ''
  ].join('\n');
  return { ass, fonts: [...used].map((f) => FONTS[f].file).concat([...extra].map((f) => EXTRA_FONTS[f].file)) };
}

module.exports = { buildAss, assColor, stamp, esc, FONTS, W, H };
