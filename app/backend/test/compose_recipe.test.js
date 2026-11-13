// The editor's recipe: validation, the ASS text file, and the ffmpeg command. All pure, no ffmpeg needed.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { validateRecipe, textOf, MAX_TEXT } = require('../src/compose/recipe');
const { buildAss, assColor, stamp, esc } = require('../src/compose/ass');
const { buildArgs, backgroundSource, lookFilters } = require('../src/compose/render');

const info = (over = {}) => ({ durationSec: 20, hasAudio: true, ...over });
const textRecipe = (over = {}) => ({ mode: 'TEXT', text: { content: 'Hello' }, ...over });
const fails = (raw, ctx, field) => assert.throws(() => validateRecipe(raw, ctx), (e) => e.status === 400 && (!field || e.extra.field === field), JSON.stringify(raw));

test('a minimal text recipe gets sensible defaults', () => {
  const r = validateRecipe(textRecipe());
  assert.equal(r.durationSec, 8);
  assert.deepEqual(r.text, { content: 'Hello', color: '#ffffff', font: 'sans', size: 64, align: 'center', animation: 'fade' });
  assert.deepEqual(r.background, { type: 'solid', color: '#111111' });
  assert.deepEqual(r.overlays, []);
  assert.equal(r.adjust, null);
  assert.equal(r.crop, undefined, 'crop only exists for video and photo posts');
});

test('the mode and what goes with it are enforced', () => {
  fails(null, {}, 'recipe');
  fails([], {}, 'recipe');
  fails({ mode: 'GIF' }, {}, 'mode');
  fails({}, {}, 'mode');
  fails(textRecipe(), { hasVideo: true }, 'video');
  fails(textRecipe(), { photoCount: 1 }, 'photos');
  fails({ mode: 'VIDEO' }, {}, 'video');
  fails({ mode: 'PHOTOS' }, {}, 'photos');
  fails({ mode: 'PHOTOS' }, { photoCount: 11 }, 'photos');
  fails({ mode: 'VIDEO' }, { hasVideo: true, photoCount: 1, videoInfo: info() }, 'photos');
});

test('text: length is counted in characters, control characters are stripped, empty is refused', () => {
  const ok = validateRecipe(textRecipe({ text: { content: '  line one\r\nline two\u0007  ' } }));
  assert.equal(ok.text.content, 'line one\nline two');
  assert.equal(validateRecipe(textRecipe({ text: { content: '😀'.repeat(MAX_TEXT) } })).text.content.length, MAX_TEXT * 2); // 280 emoji = 280 characters
  fails(textRecipe({ text: { content: '😀'.repeat(MAX_TEXT + 1) } }), {}, 'text.content');
  fails(textRecipe({ text: { content: '   ' } }), {}, 'text.content');
  fails(textRecipe({ text: {} }), {}, 'text.content');
  fails({ mode: 'TEXT' }, {}, 'text');
});

test('colours, fonts, alignment, animation and numbers are whitelisted and range checked', () => {
  fails(textRecipe({ text: { content: 'x', color: 'red' } }), {}, 'text.color');
  fails(textRecipe({ text: { content: 'x', color: '#fff' } }), {}, 'text.color');
  fails(textRecipe({ text: { content: 'x', color: '#ff00zz' } }), {}, 'text.color');
  fails(textRecipe({ text: { content: 'x', font: 'comic' } }), {}, 'text.font');
  fails(textRecipe({ text: { content: 'x', align: 'justify' } }), {}, 'text.align');
  fails(textRecipe({ text: { content: 'x', animation: 'explode' } }), {}, 'text.animation');
  fails(textRecipe({ text: { content: 'x', size: 500 } }), {}, 'text.size');
  fails(textRecipe({ text: { content: 'x', size: 'big' } }), {}, 'text.size');
  fails(textRecipe({ durationSec: 61 }), {}, 'durationSec');
  fails(textRecipe({ durationSec: 1 }), {}, 'durationSec');
  fails(textRecipe({ background: { type: 'image' } }), {}, 'background.type');
  fails(textRecipe({ background: { type: 'gradient', angle: 400 } }), {}, 'background.angle');
  assert.equal(validateRecipe(textRecipe({ text: { content: 'x', color: '#AABBCC' } })).text.color, '#aabbcc');
});

test('adjust and crop: ranges, and "no change" collapses to nothing', () => {
  assert.equal(validateRecipe(textRecipe({ adjust: { brightness: 0, contrast: 1 } })).adjust, null);
  assert.equal(validateRecipe(textRecipe({ adjust: { saturation: 1.5 } })).adjust.saturation, 1.5);
  fails(textRecipe({ adjust: { brightness: 2 } }), {}, 'adjust.brightness');
  fails(textRecipe({ adjust: { blur: 99 } }), {}, 'adjust.blur');
  fails(textRecipe({ adjust: 'bright' }), {}, 'adjust');
  const v = { hasVideo: true, videoInfo: info() };
  assert.equal(validateRecipe({ mode: 'VIDEO', crop: { x: 0, y: 0, w: 1, h: 1 } }, v).crop, null);
  assert.deepEqual(validateRecipe({ mode: 'VIDEO', crop: { x: 0.1, y: 0.2, w: 0.5, h: 0.5 } }, v).crop, { x: 0.1, y: 0.2, w: 0.5, h: 0.5 });
  fails({ mode: 'VIDEO', crop: { x: 0.6, w: 0.6 } }, v, 'crop');
  fails({ mode: 'VIDEO', crop: { w: 0.01 } }, v, 'crop.w');
});

test('cover: a moment inside the video; the default is the start for video and a moment in for text and photos', () => {
  const v = { hasVideo: true, videoInfo: info() };
  assert.equal(validateRecipe({ mode: 'VIDEO', trim: { startSec: 0, endSec: 8 } }, v).coverSec, 0);
  assert.equal(validateRecipe({ mode: 'VIDEO', trim: { startSec: 0, endSec: 8 }, coverSec: 3.456 }, v).coverSec, 3.46);
  assert.equal(validateRecipe({ mode: 'VIDEO', trim: { startSec: 0, endSec: 8 }, coverSec: 8 }, v).coverSec, 7.9, 'the very last instant has no picture');
  fails({ mode: 'VIDEO', trim: { startSec: 0, endSec: 8 }, coverSec: 9 }, v, 'coverSec');
  fails({ mode: 'VIDEO', trim: { startSec: 0, endSec: 8 }, coverSec: -1 }, v, 'coverSec');
  fails({ mode: 'VIDEO', trim: { startSec: 0, endSec: 8 }, coverSec: 'soon' }, v, 'coverSec');
  assert.equal(validateRecipe(textRecipe({ durationSec: 8 })).coverSec, 2);
  assert.equal(validateRecipe(textRecipe({ durationSec: 3 })).coverSec, 1.5);
  assert.equal(validateRecipe(textRecipe({ durationSec: 8, coverSec: 5 })).coverSec, 5);
});

test('video: trim must fit the file, be at least half a second and at most 60 s; sound follows the source', () => {
  const v = (extra, i = info()) => validateRecipe({ mode: 'VIDEO', ...extra }, { hasVideo: true, videoInfo: i });
  assert.deepEqual(v({}).trim, { startSec: 0, endSec: 20 });
  assert.equal(v({}).durationSec, 20);
  assert.deepEqual(v({ trim: { startSec: 5, endSec: 12 } }).trim, { startSec: 5, endSec: 12 });
  assert.equal(v({ trim: { startSec: 5, endSec: 12 } }).durationSec, 7);
  assert.equal(v({ trim: { startSec: 5, endSec: 20.3 } }).trim.endSec, 20, 'an end a hair past the file is clamped to it');
  assert.equal(v({}, info({ durationSec: 90 })).durationSec, 60, 'a long video with no trim is cut at 60 s');
  fails({ mode: 'VIDEO', trim: { startSec: 5, endSec: 5.2 } }, { hasVideo: true, videoInfo: info() }, 'trim');
  fails({ mode: 'VIDEO', trim: { startSec: 30 } }, { hasVideo: true, videoInfo: info() }, 'trim.startSec');
  fails({ mode: 'VIDEO', trim: { startSec: 0, endSec: 500 } }, { hasVideo: true, videoInfo: info() }, 'trim.endSec');
  fails({ mode: 'VIDEO', trim: { startSec: 0, endSec: 70 } }, { hasVideo: true, videoInfo: info({ durationSec: 100 }) }, 'trim');
  assert.equal(v({}).muteOriginal, false);
  assert.equal(v({ muteOriginal: true }).muteOriginal, true);
  assert.equal(v({}, info({ hasAudio: false })).muteOriginal, true, 'a silent source is simply treated as muted');
});

test('photos: order must be a permutation, and the slideshow may not run past 60 s', () => {
  const p = (extra, n = 3) => validateRecipe({ mode: 'PHOTOS', ...extra }, { photoCount: n });
  assert.deepEqual(p({}).photoOrder, [0, 1, 2]);
  assert.deepEqual(p({ photoOrder: [2, 0, 1] }).photoOrder, [2, 0, 1]);
  fails({ mode: 'PHOTOS', photoOrder: [0, 0, 1] }, { photoCount: 3 }, 'photoOrder');
  fails({ mode: 'PHOTOS', photoOrder: [0, 1] }, { photoCount: 3 }, 'photoOrder');
  fails({ mode: 'PHOTOS', photoOrder: [0, 1, 5] }, { photoCount: 3 }, 'photoOrder');
  // 3 photos x 3 s with 0.5 s cross-fades = 8 s
  assert.equal(p({}).durationSec, 8);
  assert.equal(p({ transition: 'none' }).durationSec, 9);
  assert.equal(p({}, 1).durationSec, 3);
  fails({ mode: 'PHOTOS', slideSeconds: 8 }, { photoCount: 10 }, 'slideSeconds'); // 80 s
  assert.equal(validateRecipe({ mode: 'PHOTOS', slideSeconds: 6.4, transition: 'none' }, { photoCount: 9 }).durationSec, 57.6);
});

test('overlays: count, text, position, timing; times must lie inside the video', () => {
  const o = (list) => validateRecipe(textRecipe({ overlays: list }));
  assert.equal(o([{ text: 'hi' }]).overlays[0].endSec, 8);
  assert.equal(o([{ text: 'hi', x: 0.2, y: 0.9, startSec: 1, endSec: 3 }]).overlays[0].y, 0.9);
  fails(textRecipe({ overlays: Array.from({ length: 6 }, () => ({ text: 'x' })) }), {}, 'overlays');
  fails(textRecipe({ overlays: [{ text: 'x'.repeat(121) }] }), {}, 'overlays[0].text');
  fails(textRecipe({ overlays: [{ text: 'x', x: 1.5 }] }), {}, 'overlays[0].x');
  fails(textRecipe({ overlays: [{ text: 'x', startSec: 5, endSec: 5 }] }), {}, 'overlays');
  fails(textRecipe({ overlays: [{ text: 'x', endSec: 99 }] }), {}, 'overlays[0].endSec');
  fails(textRecipe({ overlays: 'text' }), {}, 'overlays');
  fails(textRecipe({ overlays: ['text'] }), {}, 'overlays');
});

test('music settings need a music file, and have defaults and limits', () => {
  assert.deepEqual(validateRecipe(textRecipe(), { hasMusic: true }).music, { volume: 0.8, startSec: 0 });
  assert.deepEqual(validateRecipe(textRecipe({ music: { volume: 0.3, startSec: 12 } }), { hasMusic: true }).music, { volume: 0.3, startSec: 12 });
  fails(textRecipe({ music: { volume: 0.3 } }), {}, 'music');
  fails(textRecipe({ music: { volume: 1.5 } }), { hasMusic: true }, 'music.volume');
  assert.equal(validateRecipe(textRecipe()).music, undefined);
});

test('textOf: everything the person wrote, for the AI and the word screen', () => {
  const r = validateRecipe(textRecipe({ text: { content: 'Main words' }, overlays: [{ text: 'overlay words' }] }));
  assert.equal(textOf(r, 'a caption'), 'Main words\noverlay words\na caption');
  assert.equal(textOf(validateRecipe({ mode: 'PHOTOS' }, { photoCount: 1 }), null), '');
});

// ---------- ASS ----------

test('ASS colours are blue-first and times are h:mm:ss.cc', () => {
  assert.equal(assColor('#ff8000'), '&H0080FF&');
  assert.equal(stamp(0), '0:00:00.00');
  assert.equal(stamp(61.5), '0:01:01.50');
  assert.equal(stamp(3725.04), '1:02:05.04');
});

test('ASS escaping: braces and backslashes cannot start a tag, new lines become \\N', () => {
  assert.equal(esc('a{\\b1}c'), 'a(/b1)c');
  assert.equal(esc('one\ntwo'), 'one\\Ntwo');
  const r = validateRecipe(textRecipe({ text: { content: '{\\fs200}HUGE', animation: 'none' } }));
  const line = buildAss(r).ass.split('\n').find((l) => l.startsWith('Dialogue: 0'));
  assert.ok(line.endsWith('(/fs200)HUGE'), line);
  assert.ok(!/\{\\fs200/.test(line));
});

test('ASS: each animation builds the tags it promises', () => {
  const line = (animation, extra = {}) => buildAss(validateRecipe(textRecipe({ text: { content: 'ab cd', animation, ...extra }, durationSec: 10 })))
    .ass.split('\n').find((l) => l.startsWith('Dialogue: 0'));
  assert.match(line('none'), /\\pos\(360,640\)\}ab cd$/);
  assert.match(line('fade'), /\\fad\(700,0\)/);
  assert.match(line('slideUp'), /\\move\(360,730,360,640,0,700\)/);
  const tw = line('typewriter');
  assert.equal((tw.match(/\\alpha&HFF&/g) || []).length, 4, 'one reveal per visible character (4), none for the space');
  assert.match(tw, /\\t\(0,1,\\alpha&H00&\)\}a/);
  assert.match(tw, /\\t\(60,61,/); // second character 60 ms later
  const words = line('wordByWord');
  assert.equal((words.match(/\\alpha&HFF&/g) || []).length, 2, 'one reveal per word');
  assert.match(words, /\\t\(350,351,\\alpha&H00&\)\}cd$/);
  assert.match(line('none', { align: 'left' }), /\\an4.*\\pos\(70,640\)/);
  assert.match(line('none', { align: 'right' }), /\\an6.*\\pos\(650,640\)/);
});

test('ASS: the reveal always finishes within 60% of the video, however long the text', () => {
  const long = 'x'.repeat(280);
  const r = validateRecipe(textRecipe({ text: { content: long, animation: 'typewriter' }, durationSec: 3 }));
  const times = [...buildAss(r).ass.matchAll(/\\t\((\d+),/g)].map((m) => Number(m[1]));
  assert.ok(Math.max(...times) <= 3 * 0.6 * 1000 + 5, `last letter at ${Math.max(...times)} ms`);
});

test('ASS: overlays are positioned by fraction, timed, and list the fonts to ship', () => {
  const r = validateRecipe(textRecipe({ overlays: [{ text: 'Look', x: 0.25, y: 0.75, startSec: 1, endSec: 2.5, size: 40, color: '#ff0000', font: 'mono' }] }));
  const built = buildAss(r);
  assert.match(built.ass, /Dialogue: 1,0:00:01.00,0:00:02.50,mono,,0,0,0,,\{\\an5\\pos\(180,960\)\\fs40\\c&H0000FF&/);
  assert.deepEqual(built.fonts.sort(), ['DejaVuSansMono-Bold.ttf', 'Roboto-Bold.ttf']);
  assert.equal(buildAss(validateRecipe({ mode: 'PHOTOS' }, { photoCount: 1 })), null, 'nothing to draw -> no file');
});

// ---------- ffmpeg arguments ----------

const baseInputs = { video: '/c/v.mp4', music: '/c/m.mp3', photos: ['/c/a.jpg', '/c/b.png'] };

test('the command never contains what the person typed, and is an argument list (no shell)', () => {
  const r = validateRecipe(textRecipe({ text: { content: "'; rm -rf / #$(whoami)" }, overlays: [{ text: '"; touch pwned' }] }));
  const args = buildArgs({ recipe: r, inputs: {}, out: '/u/o.mp4', hasAss: true });
  assert.ok(Array.isArray(args));
  assert.ok(!args.join(' ').includes('rm -rf'));
  assert.ok(!args.join(' ').includes('whoami'));
  assert.ok(!args.join(' ').includes('pwned'));
});

test('gradient source: a still pixel formula (not ffmpeg\'s rotating `gradients`), scaled to 720x1280', () => {
  for (let angle = 0; angle <= 360; angle += 15) {
    const src = backgroundSource({ type: 'gradient', from: '#102030', to: '#a0b0c0', angle }, 5);
    assert.ok(!src.includes('gradients='), 'the rotating source is not used');
    assert.match(src, /^color=c=black:s=72x128:r=25:d=5,format=gbrp,geq=r='/);
    assert.match(src, /scale=720:1280:flags=bilinear$/);
    assert.match(src, /r='16\+\(160-16\)\*clip\(/); // from #10 = 16 to #a0 = 160
    assert.match(src, /b='48\+\(192-48\)\*clip\(/);
  }
  assert.match(backgroundSource({ type: 'gradient', from: '#000000', to: '#ffffff', angle: 0 }, 4), /\(X-W\/2\)\*0\+\(Y-H\/2\)\*1\)/);
  assert.match(backgroundSource({ type: 'gradient', from: '#000000', to: '#ffffff', angle: 90 }, 4), /\(X-W\/2\)\*1\+\(Y-H\/2\)\*0\)/);
  assert.match(backgroundSource({ type: 'solid', color: '#ff0000' }, 4), /^color=c=0xff0000:s=720x1280/);
});

test('video command: seek+length, scale cap, ass only when needed, music mixed with the original', () => {
  const rec = validateRecipe({ mode: 'VIDEO', trim: { startSec: 2, endSec: 9 }, music: { volume: 0.4 }, overlays: [{ text: 'x' }] }, { hasVideo: true, hasMusic: true, videoInfo: info() });
  const args = buildArgs({ recipe: rec, inputs: baseInputs, out: '/u/o.mp4', hasAss: true, voicePath: '/c/voice.mp3' });
  const s = args.join(' ');
  assert.match(s, /-ss 2 -t 7 -i \/c\/v\.mp4/);
  assert.match(s, /scale=-2:'min\(1280,trunc\(ih\/2\)\*2\)'/);
  assert.match(s, /ass=filename=overlay\.ass:fontsdir=fonts/);
  assert.match(s, /amix=inputs=2:duration=first/);
  assert.match(s, /volume=0\.4/);
  assert.match(s, /-stream_loop -1 -i \/c\/m\.mp3/);
  assert.match(s, /-map \[voice\] -c:a libmp3lame -ar 16000 -ac 1 -t 7 \/c\/voice\.mp3/);
  assert.equal(args[args.length - 1], '/c/voice.mp3');
  assert.ok(args.includes('/u/o.mp4'));
});

test('video command: muted original -> only music or silence, and no voice file', () => {
  const muted = validateRecipe({ mode: 'VIDEO', muteOriginal: true }, { hasVideo: true, videoInfo: info() });
  let s = buildArgs({ recipe: muted, inputs: baseInputs, out: '/u/o.mp4', hasAss: false, voicePath: '/c/voice.mp3' }).join(' ');
  assert.match(s, /anullsrc/);
  assert.ok(!s.includes('voice.mp3') && !s.includes('amix'));
  assert.ok(!s.includes('overlay.ass'));
  const mutedMusic = validateRecipe({ mode: 'VIDEO', muteOriginal: true }, { hasVideo: true, hasMusic: true, videoInfo: info() });
  s = buildArgs({ recipe: mutedMusic, inputs: baseInputs, out: '/u/o.mp4', hasAss: false }).join(' ');
  assert.ok(!s.includes('anullsrc') && !s.includes('amix'));
  assert.match(s, /\[1:a\]aresample/);
});

test('photo command: one looped input each, fit to 720x1280, cross-fades with the right offsets', () => {
  const rec = validateRecipe({ mode: 'PHOTOS', slideSeconds: 4, adjust: { saturation: 2 } }, { photoCount: 3 });
  const s = buildArgs({ recipe: rec, inputs: { photos: ['/c/1.jpg', '/c/2.jpg', '/c/3.jpg'] }, out: '/u/o.mp4', hasAss: false }).join(' ');
  assert.equal((s.match(/-loop 1 -framerate 25 -t 4 -i/g) || []).length, 3);
  assert.equal((s.match(/force_original_aspect_ratio=decrease/g) || []).length, 3);
  assert.match(s, /xfade=transition=fade:duration=0\.5:offset=3\.5/);
  assert.match(s, /xfade=transition=fade:duration=0\.5:offset=7/);
  assert.equal((s.match(/eq=brightness/g) || []).length, 3, 'the look is applied once per photo, not again on the joined clip');
  const none = validateRecipe({ mode: 'PHOTOS', transition: 'none' }, { photoCount: 2 });
  assert.match(buildArgs({ recipe: none, inputs: { photos: ['/c/1.jpg', '/c/2.jpg'] }, out: 'o', hasAss: false }).join(' '), /concat=n=2:v=1:a=0/);
});

test('look filters: crop expressions and colour filters appear only when set', () => {
  assert.deepEqual(lookFilters({ crop: null, adjust: null }), []);
  const f = lookFilters({ crop: { x: 0.1, y: 0.2, w: 0.5, h: 0.6 }, adjust: { brightness: 0.1, contrast: 1, saturation: 1, hue: 20, blur: 3 } });
  assert.equal(f[0], 'crop=w=iw*0.5:h=ih*0.6:x=iw*0.1:y=ih*0.2');
  assert.match(f[1], /^eq=brightness=0\.1/);
  assert.equal(f[2], 'hue=h=20');
  assert.match(f[3], /^boxblur=luma_radius=3/);
});
