// Hindi and emoji in server-drawn text: which letters get which font, how animations cut text up, which font files are copied.

const test = require('node:test');
const assert = require('node:assert/strict');

const { graphemes, scriptOf, fontWriter, EXTRA_FONTS } = require('../src/compose/scripts');
const { buildAss } = require('../src/compose/ass');

const esc = (s) => s.replace(/\n/g, '\\N');

test('letters are sorted into the three scripts', () => {
  assert.equal(scriptOf('a'), 'default');
  assert.equal(scriptOf(' '), 'default');
  assert.equal(scriptOf('7'), 'default');
  assert.equal(scriptOf('©'), 'default', 'the Latin fonts have ©');
  assert.equal(scriptOf('न'), 'deva');
  assert.equal(scriptOf('।'), 'deva');
  assert.equal(scriptOf('ਪ'), 'guru', 'Punjabi');
  assert.equal(scriptOf('😀'), 'emoji');
  assert.equal(scriptOf('❤️'), 'emoji');
  assert.equal(scriptOf('1️⃣'), 'emoji', 'keycap');
});

test('graphemes keep a Hindi conjunct and a family emoji whole', () => {
  assert.deepEqual(graphemes('abc'), ['a', 'b', 'c']);
  const word = graphemes('नमस्ते');
  assert.equal(word.length, 3, `न, म, स्ते: ${JSON.stringify(word)}`);
  assert.equal(word[2], 'स्ते'.slice(0, 'स्ते'.length)); // conjunct स्त plus the vowel sign
  assert.equal(graphemes('👨‍👩‍👧').length, 1);
});

test('the writer switches font only where the script changes', () => {
  const used = new Set();
  const w = fontWriter('Roboto', esc, used);
  const out = w.write('Hi नमस्ते 😀 ok');
  assert.match(out, /^Hi \{\\fnNoto Sans Devanagari\}नमस्ते\{\\fnRoboto\} \{\\fnNoto Emoji\}😀\{\\fnRoboto\} ok$/);
  assert.deepEqual([...used].sort(), ['deva', 'emoji']);
  assert.equal(fontWriter('Roboto', esc).write('plain text'), 'plain text', 'Latin text gets no tags');
});

test('the writer remembers its font between pieces (animations hand text over a letter at a time)', () => {
  const w = fontWriter('Roboto', esc);
  assert.equal(w.write('न'), '{\\fnNoto Sans Devanagari}न');
  assert.equal(w.write('म'), 'म', 'still in the Hindi font');
  assert.equal(w.write(' '), '{\\fnRoboto} ');
});

test('buildAss puts a font tag in the text and asks for the font files only when they are needed', () => {
  const base = { mode: 'TEXT', durationSec: 8, text: { content: 'hello', color: '#ffffff', font: 'sans', size: 64, align: 'center', animation: 'none' }, overlays: [] };
  assert.deepEqual(buildAss(base).fonts, ['Roboto-Bold.ttf']);

  const hindi = buildAss({ ...base, text: { ...base.text, content: 'नमस्ते 😀' } });
  assert.deepEqual(hindi.fonts.sort(), [EXTRA_FONTS.deva.file, EXTRA_FONTS.emoji.file, 'Roboto-Bold.ttf'].sort());
  assert.match(hindi.ass, /\{\\fnNoto Sans Devanagari\}नमस्ते/);

  const overlayOnly = buildAss({ ...base, text: undefined, mode: 'PHOTOS', overlays: [{ text: 'सत्य', x: 0.5, y: 0.5, size: 40, color: '#ffffff', font: 'serif', startSec: 0, endSec: 8 }] });
  assert.ok(overlayOnly.fonts.includes(EXTRA_FONTS.deva.file));
  assert.match(overlayOnly.ass, /\\fnNoto Sans Devanagari\}सत्य/);
});

test('Punjabi text gets the Gurmukhi font', () => {
  const base = { mode: 'TEXT', durationSec: 8, text: { content: 'ਸਤ ਸ੍ਰੀ ਅਕਾਲ', color: '#ffffff', font: 'sans', size: 64, align: 'center', animation: 'none' }, overlays: [] };
  const built = buildAss(base);
  assert.ok(built.fonts.includes(EXTRA_FONTS.guru.file));
  assert.match(built.ass, /\{\\fnNoto Sans Gurmukhi\}ਸਤ/);
});

test('typewriter reveals Hindi a whole conjunct at a time, never a lone virama', () => {
  const t = { content: 'नमस्ते', color: '#ffffff', font: 'sans', size: 64, align: 'center', animation: 'typewriter' };
  const ass = buildAss({ mode: 'TEXT', durationSec: 8, text: t, overlays: [] }).ass;
  const line = ass.split('\n').find((l) => l.startsWith('Dialogue'));
  const revealed = line.split(/\{\\alpha&HFF&\\t\([^)]*\)\}/).slice(1).map((s) => s.replace(/\{[^}]*\}/g, ''));
  assert.deepEqual(revealed, ['न', 'म', 'स्ते']);
});
