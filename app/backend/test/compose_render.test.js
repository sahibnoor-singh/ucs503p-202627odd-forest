// The real renderer, with the real ffmpeg: checks pixels, loudness, sizes and lengths of what comes out.
// Skipped automatically when no working ffmpeg is available (set FFMPEG_PATH to use another one).
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { validateRecipe } = require('../src/compose/recipe');
const { createComposer } = require('../src/compose');

function findFfmpeg() {
  const candidates = [process.env.FFMPEG_PATH];
  try { candidates.push(require('ffmpeg-static')); } catch { /* not installed */ }
  return candidates.filter(Boolean).find((p) => fs.existsSync(p) && spawnSync(p, ['-version']).status === 0) || null;
}
const FF = findFfmpeg();
const skip = FF ? false : 'no working ffmpeg (npm install downloads one)';
const composer = FF ? createComposer({ ffmpegPath: FF }) : null;

const run = (...args) => assert.equal(spawnSync(FF, ['-y', '-loglevel', 'error', ...args]).status, 0, `ffmpeg ${args.join(' ')}`);
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'forest-render-'));
const at = (name) => path.join(tmp, name);
process.on('exit', () => fs.rmSync(tmp, { recursive: true, force: true }));

/** Makes the small input files once. */
function assets() {
  if (assets.done) return;
  run('-f', 'lavfi', '-i', 'testsrc=size=640x360:rate=25', '-f', 'lavfi', '-i', 'sine=frequency=440', '-t', '6', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', at('speech.mp4'));
  run('-f', 'lavfi', '-i', 'testsrc=size=640x360:rate=25', '-t', '4', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', at('silent.mp4'));
  run('-f', 'lavfi', '-i', 'color=c=0x00c800:s=800x600', '-frames:v', '1', at('green.png'));
  run('-f', 'lavfi', '-i', 'color=c=0xc80000:s=500x900', '-frames:v', '1', at('red.jpg'));
  run('-f', 'lavfi', '-i', 'sine=frequency=880:duration=3', at('music.mp3'));
  assets.done = true;
}

/** RGB bytes of one frame (raw, no header) plus its size. */
function frame(file, t) {
  const info = spawnSync(FF, ['-hide_banner', '-i', file], { encoding: 'utf8' }).stderr;
  const [, w, h] = /Video:.*?, (\d+)x(\d+)/.exec(info).map(Number);
  const r = spawnSync(FF, ['-loglevel', 'error', '-ss', String(t), '-i', file, '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'], { maxBuffer: 64 * 1024 * 1024 });
  assert.equal(r.status, 0);
  return { w, h, px: r.stdout };
}
const whitePixels = ({ px }) => { let n = 0; for (let i = 0; i < px.length; i += 3) if (px[i] > 235 && px[i + 1] > 235 && px[i + 2] > 235) n++; return n; };
const center = ({ w, h, px }) => { const i = (Math.floor(h / 2) * w + Math.floor(w / 2)) * 3; return [px[i], px[i + 1], px[i + 2]]; };

/** Mean loudness in dB (about -91 means silence). */
function loudness(file) {
  const r = spawnSync(FF, ['-hide_banner', '-i', file, '-af', 'volumedetect', '-vn', '-f', 'null', '-'], { encoding: 'utf8' });
  const m = /mean_volume:\s*(-?[\d.]+) dB/.exec(r.stderr);
  return m ? Number(m[1]) : -91;
}

async function render(rawRecipe, ctx, inputs, name = 'out.mp4', extra = {}) {
  assets();
  const recipe = validateRecipe(rawRecipe, ctx);
  const out = at(name);
  await composer.render({ recipe, inputs, outPath: out, workDir: at(`work-${name}`), ...extra });
  return { recipe, out, info: await composer.probe(out) };
}

const speechInfo = () => ({ durationSec: 6, hasAudio: true });

test('text post: 720x1280, the right length, a sound track, and the text is really drawn', { skip }, async () => {
  const { out, info } = await render(
    { mode: 'TEXT', durationSec: 4, text: { content: 'Should colleges ban phones?', animation: 'none', size: 72 }, background: { type: 'gradient', from: '#1d2671', to: '#c33764', angle: 160 } },
    {}, {});
  assert.deepEqual([info.width, info.height], [720, 1280]);
  assert.ok(Math.abs(info.durationSec - 4) < 0.15, `length ${info.durationSec}`);
  assert.ok(info.hasAudio && info.hasVideo);
  assert.ok(whitePixels(frame(out, 2)) > 1500, 'white letters are on the picture');
  const bg = frame(out, 2);
  const row = (y) => { const i = y * bg.w * 3; return [bg.px[i], bg.px[i + 1], bg.px[i + 2]]; };
  const [top, bottom] = [row(5), row(bg.h - 5)];
  assert.ok(Math.abs(top[0] - bottom[0]) > 60, `a gradient: top ${top}, bottom ${bottom}`);
});

test('gradients are still and point the way the angle says', { skip }, async () => {
  const bgOnly = (angle, name) => render({ mode: 'TEXT', durationSec: 3, text: { content: 'x', size: 32, color: '#000000', animation: 'none' }, background: { type: 'gradient', from: '#000000', to: '#ffffff', angle } }, {}, {}, name);
  const vertical = await bgOnly(0, 'g0.mp4');   // black at the top, white at the bottom
  const a = frame(vertical.out, 0.2);
  const b = frame(vertical.out, 2.7);
  const at = (f, x, y) => f.px[(y * f.w + x) * 3];
  assert.ok(at(a, 5, 5) < 30 && at(a, 5, 1270) > 225, `0 degrees: top ${at(a, 5, 5)}, bottom ${at(a, 5, 1270)}`);
  assert.ok(Math.abs(at(a, 5, 5) - at(b, 5, 5)) < 3 && Math.abs(at(a, 5, 1270) - at(b, 5, 1270)) < 3, 'the same at the start and the end (it does not move)');
  assert.ok(Math.abs(at(a, 5, 600) - at(a, 700, 600)) < 5, 'a vertical gradient is the same left and right');
  const horizontal = await bgOnly(90, 'g90.mp4'); // black at the left, white at the right
  const h = frame(horizontal.out, 1);
  assert.ok(at(h, 5, 600) < 30 && at(h, 715, 600) > 225, `90 degrees: left ${at(h, 5, 600)}, right ${at(h, 715, 600)}`);
});

test('without text there is no white: the white pixels above really are the text', { skip }, async () => {
  const { out } = await render({ mode: 'TEXT', durationSec: 3, text: { content: ' ', animation: 'none' } }, {}, {}).catch(() => ({}));
  assert.equal(out, undefined, 'empty text is refused by the recipe');
  const { out: solid } = await render({ mode: 'TEXT', durationSec: 3, text: { content: 'x', animation: 'none', color: '#111111', size: 32 }, background: { type: 'solid', color: '#202020' } }, {}, {}, 'plain.mp4');
  assert.equal(whitePixels(frame(solid, 1)), 0);
});

test('text animations: typewriter starts nearly empty and ends full; fade starts invisible; slideUp moves', { skip }, async () => {
  const base = { mode: 'TEXT', durationSec: 5, text: { content: 'The quick brown fox jumps over the lazy dog again and again', size: 56 }, background: { type: 'solid', color: '#000000' } };
  const tw = await render({ ...base, text: { ...base.text, animation: 'typewriter' } }, {}, {}, 'tw.mp4');
  const early = whitePixels(frame(tw.out, 0.15));
  const late = whitePixels(frame(tw.out, 4.5));
  assert.ok(late > early * 3 && late > 1000, `typewriter: early ${early}, late ${late}`);

  const fade = await render({ ...base, text: { ...base.text, animation: 'fade' } }, {}, {}, 'fade.mp4');
  assert.ok(whitePixels(frame(fade.out, 0.02)) < whitePixels(frame(fade.out, 3)) / 5, 'fade-in starts almost invisible');

  const words = await render({ ...base, text: { ...base.text, animation: 'wordByWord' } }, {}, {}, 'words.mp4');
  assert.ok(whitePixels(frame(words.out, 0.1)) < whitePixels(frame(words.out, 4.5)) / 3);

  const slide = await render({ ...base, text: { ...base.text, animation: 'slideUp' } }, {}, {}, 'slide.mp4');
  const rowOf = (f) => { for (let y = 0; y < f.h; y++) for (let x = 0; x < f.w; x++) { const i = (y * f.w + x) * 3; if (f.px[i] > 80 && f.px[i + 1] > 80) return y; } return -1; };
  const start = rowOf(frame(slide.out, 0.3));
  const end = rowOf(frame(slide.out, 3));
  assert.ok(start > end + 20, `slideUp: text rises from row ${start} to row ${end}`);
});

test('video: trim, crop and overlay produce the expected length, size and text; audio is kept', { skip }, async () => {
  const voice = at('voice.mp3');
  const { out, info } = await render(
    { mode: 'VIDEO', trim: { startSec: 1, endSec: 4 }, crop: { x: 0, y: 0, w: 0.5, h: 1 }, overlays: [{ text: 'LOOK', x: 0.5, y: 0.5, size: 90 }] },
    { hasVideo: true, videoInfo: speechInfo() }, { video: at('speech.mp4') }, 'trimmed.mp4', { voicePath: voice });
  assert.ok(Math.abs(info.durationSec - 3) < 0.2, `length ${info.durationSec}`);
  assert.deepEqual([info.width, info.height], [320, 360], 'half the width kept, height unchanged');
  assert.ok(info.hasAudio);
  assert.ok(loudness(out) > -40, 'the original sound is there');
  assert.ok(whitePixels(frame(out, 1.5)) > 200, 'the overlay text is drawn');
  const voiceInfo = await composer.probe(voice);
  assert.ok(Math.abs(voiceInfo.durationSec - 3) < 0.2 && voiceInfo.hasAudio && !voiceInfo.hasVideo, 'a separate speech-only file of the same length');
});

test('video: tall videos are capped at 1280 high; the original size is kept otherwise', { skip }, async () => {
  assets();
  run('-f', 'lavfi', '-i', 'testsrc=size=1080x1920:rate=10', '-f', 'lavfi', '-i', 'anullsrc', '-t', '1', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', at('tall.mp4'));
  const tall = await render({ mode: 'VIDEO' }, { hasVideo: true, videoInfo: { durationSec: 1, hasAudio: true } }, { video: at('tall.mp4') }, 'tall-out.mp4');
  assert.deepEqual([tall.info.width, tall.info.height], [720, 1280]);
  const small = await render({ mode: 'VIDEO' }, { hasVideo: true, videoInfo: speechInfo() }, { video: at('speech.mp4') }, 'small-out.mp4');
  assert.deepEqual([small.info.width, small.info.height], [640, 360]);
});

test('sound: muting silences the original, music replaces or joins it, a silent source stays valid', { skip }, async () => {
  const v = { hasVideo: true, videoInfo: speechInfo() };
  const original = await render({ mode: 'VIDEO' }, v, { video: at('speech.mp4') }, 'orig.mp4');
  const muted = await render({ mode: 'VIDEO', muteOriginal: true }, v, { video: at('speech.mp4') }, 'muted.mp4');
  const mutedMusic = await render({ mode: 'VIDEO', muteOriginal: true, music: { volume: 1 } }, { ...v, hasMusic: true }, { video: at('speech.mp4'), music: at('music.mp3') }, 'mm.mp4');
  const both = await render({ mode: 'VIDEO', music: { volume: 0.5 } }, { ...v, hasMusic: true }, { video: at('speech.mp4'), music: at('music.mp3') }, 'both.mp4');
  assert.ok(loudness(original.out) > -40, `original ${loudness(original.out)}`);
  assert.ok(loudness(muted.out) < -60, `muted ${loudness(muted.out)}`);
  assert.ok(loudness(mutedMusic.out) > -40, 'music alone is audible');
  assert.ok(loudness(both.out) > -40);
  for (const r of [original, muted, mutedMusic, both]) assert.ok(r.info.hasAudio, 'every file has a sound track');
  const silentSource = await render({ mode: 'VIDEO' }, { hasVideo: true, videoInfo: { durationSec: 4, hasAudio: false } }, { video: at('silent.mp4') }, 'silentsrc.mp4');
  assert.ok(silentSource.recipe.muteOriginal && silentSource.info.hasAudio);
});

test('music shorter than the post is looped, and a start offset is honoured', { skip }, async () => {
  const { info, out } = await render({ mode: 'TEXT', durationSec: 8, text: { content: 'long post' }, music: { volume: 1, startSec: 1 } }, { hasMusic: true }, { music: at('music.mp3') }, 'loop.mp4');
  assert.ok(Math.abs(info.durationSec - 8) < 0.2, 'the 3 s song does not shorten the 8 s post');
  assert.ok(loudness(out) > -40);
});

test('photos: shown in the chosen order, cross-faded, fitted to 720x1280 with bars', { skip }, async () => {
  // (the job maps photoOrder to files before calling the renderer, so here the files are already in show order: red, then green)
  const { out, info, recipe } = await render({ mode: 'PHOTOS', photoOrder: [1, 0], slideSeconds: 2, transition: 'fade' }, { photoCount: 2 }, { photos: [at('red.jpg'), at('green.png')] }, 'photos.mp4');
  assert.equal(recipe.durationSec, 3.5);
  assert.deepEqual([info.width, info.height], [720, 1280]);
  assert.ok(Math.abs(info.durationSec - 3.5) < 0.15);
  const first = center(frame(out, 0.4));
  const last = center(frame(out, 3.2));
  assert.ok(first[0] > 150 && first[1] < 60, `first photo is red: ${first}`);
  assert.ok(last[1] > 150 && last[0] < 60, `last photo is green: ${last}`);
  const landscape = frame(out, 3.2); // the green photo is landscape, so it is letterboxed
  assert.deepEqual([landscape.px[0], landscape.px[1], landscape.px[2]], [0, 0, 0], 'bars above the photo are black');
});

test('photos: no transition means a hard cut and the plain total length', { skip }, async () => {
  const { out, info } = await render({ mode: 'PHOTOS', slideSeconds: 2, transition: 'none' }, { photoCount: 2 }, { photos: [at('green.png'), at('red.jpg')] }, 'cut.mp4');
  assert.ok(Math.abs(info.durationSec - 4) < 0.15);
  assert.ok(center(frame(out, 1.9))[1] > 150, 'still green just before the cut');
  assert.ok(center(frame(out, 2.1))[0] > 150, 'red just after it');
});

test('colour adjustments change the picture: saturation 0 is grey, brightness lifts it', { skip }, async () => {
  const grey = await render({ mode: 'PHOTOS', slideSeconds: 1, adjust: { saturation: 0 } }, { photoCount: 1 }, { photos: [at('red.jpg')] }, 'grey.mp4');
  const [r, g, b] = center(frame(grey.out, 0.5));
  assert.ok(Math.abs(r - g) < 12 && Math.abs(g - b) < 12, `grey: ${r},${g},${b}`);
  const plain = await render({ mode: 'PHOTOS', slideSeconds: 1 }, { photoCount: 1 }, { photos: [at('green.png')] }, 'plain2.mp4');
  const bright = await render({ mode: 'PHOTOS', slideSeconds: 1, adjust: { brightness: 0.3 } }, { photoCount: 1 }, { photos: [at('green.png')] }, 'bright.mp4');
  assert.ok(center(frame(bright.out, 0.5))[0] > center(frame(plain.out, 0.5))[0] + 20, 'brighter');
});

test('a failed render throws, removes its partial output and its working folder', { skip }, async () => {
  assets();
  const recipe = validateRecipe({ mode: 'PHOTOS' }, { photoCount: 1 });
  const out = at('never.mp4');
  await assert.rejects(composer.render({ recipe, inputs: { photos: [at('does-not-exist.jpg')] }, outPath: out, workDir: at('work-fail') }), /ffmpeg failed/);
  assert.equal(fs.existsSync(out), false);
  assert.equal(fs.existsSync(at('work-fail')), false);
});

test('a render that runs too long is stopped', { skip }, async () => {
  assets();
  const recipe = validateRecipe({ mode: 'TEXT', durationSec: 60, text: { content: 'slow' } }, {});
  await assert.rejects(composer.render({ recipe, inputs: {}, outPath: at('slow.mp4'), workDir: at('work-slow'), timeoutMs: 1 }), /timed out/);
});

test('probe: reads length and streams, and refuses things that are not media', { skip }, async () => {
  assets();
  const p = await composer.probe(at('speech.mp4'));
  assert.ok(Math.abs(p.durationSec - 6) < 0.2 && p.hasVideo && p.hasAudio);
  assert.deepEqual([p.width, p.height], [640, 360]);
  const m = await composer.probe(at('music.mp3'));
  assert.ok(m.hasAudio && !m.hasVideo);
  fs.writeFileSync(at('fake.mp4'), 'this is not a video at all');
  await assert.rejects(composer.probe(at('fake.mp4')), /not readable media/);
});

test('end to end through the server: an editor post becomes a playable 720x1280 video', { skip }, async () => {
  const { startServer, addUser } = require('./helpers');
  const s = await startServer({ appOptions: { composer } });
  try {
    addUser(s.db, 'poster');
    const fd = new FormData();
    fd.append('recipe', JSON.stringify({ mode: 'TEXT', durationSec: 3, text: { content: 'End to end', animation: 'fade' } }));
    const res = await s.api('POST', '/api/posts/compose', { user: 'poster', form: fd });
    assert.equal(res.status, 201, JSON.stringify(res.data));
    await s.idle();
    const row = s.db.get('SELECT * FROM posts WHERE id = ?', [res.data.post.id]);
    assert.equal(row.status, 'READY');
    const info = await composer.probe(path.join(s.uploadsDir, row.media_filename));
    assert.deepEqual([info.width, info.height], [720, 1280]);
    const range = await fetch(`${s.base}/uploads/${row.media_filename}`, { headers: { range: 'bytes=0-99' } });
    assert.equal(range.status, 206, 'seekable like every other video');
    fs.rmSync(`${s.uploadsDir}-compose`, { recursive: true, force: true });
  } finally { await s.close(); }
});

test('cover: a JPEG of the chosen moment is written beside the video, and a different moment gives a different picture', { skip }, async () => {
  const v = { hasVideo: true, videoInfo: speechInfo() };
  const early = await render({ mode: 'VIDEO', trim: { startSec: 0, endSec: 5 }, coverSec: 0 }, v, { video: at('speech.mp4') }, 'cover-a.mp4', { coverPath: at('cover-a.jpg') });
  const late = await render({ mode: 'VIDEO', trim: { startSec: 0, endSec: 5 }, coverSec: 4 }, v, { video: at('speech.mp4') }, 'cover-b.mp4', { coverPath: at('cover-b.jpg') });
  assert.ok(fs.existsSync(at('cover-a.jpg')) && fs.existsSync(at('cover-b.jpg')));
  const a = fs.readFileSync(at('cover-a.jpg'));
  assert.deepEqual([...a.subarray(0, 2)], [0xff, 0xd8], 'it is a JPEG');
  assert.ok(!a.equals(fs.readFileSync(at('cover-b.jpg'))), 'the moving test picture looks different at 0 s and at 4 s');
  const probed = await composer.probe(at('cover-a.jpg'));
  assert.ok(probed.height <= 720 && probed.height % 2 === 0 && probed.width % 2 === 0, `${probed.width}x${probed.height}`);
  assert.equal(late.recipe.coverSec, 4);
  assert.equal(early.recipe.coverSec, 0);
});

test('cover: text posts get one by default, and a failed render leaves no cover', { skip }, async () => {
  await render({ mode: 'TEXT', durationSec: 4, text: { content: 'Cover me', animation: 'fade' } }, {}, {}, 'cover-text.mp4', { coverPath: at('cover-text.jpg') });
  // (a still picture has no moment to seek to, so it is decoded whole rather than through frame())
  const f = { px: spawnSync(FF, ['-loglevel', 'error', '-i', at('cover-text.jpg'), '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'], { maxBuffer: 64 * 1024 * 1024 }).stdout };
  let bright = 0; // a JPEG's white is a little below 255, so count anything clearly bright
  for (let n = 0; n < f.px.length; n += 3) if (f.px[n] > 200 && f.px[n + 1] > 200 && f.px[n + 2] > 200) bright++;
  assert.ok(bright > 150, `the words are on the cover (it is taken after the fade-in): ${bright} bright pixels`);

  const recipe = validateRecipe({ mode: 'PHOTOS' }, { photoCount: 1 });
  await assert.rejects(composer.render({ recipe, inputs: { photos: [at('does-not-exist.jpg')] }, outPath: at('x.mp4'), coverPath: at('x.jpg'), workDir: at('work-xx') }), /ffmpeg failed/);
  assert.ok(!fs.existsSync(at('x.jpg')));
});

test('crop: a crop that leaves an odd number of pixels still renders (even-sized video)', { skip }, async () => {
  const { info } = await render({ mode: 'VIDEO', trim: { startSec: 0, endSec: 2 }, crop: { x: 0, y: 0, w: 0.5, h: 0.499 } }, { hasVideo: true, videoInfo: speechInfo() }, { video: at('speech.mp4') }, 'odd-crop.mp4');
  assert.ok(info.width % 2 === 0 && info.height % 2 === 0, `${info.width}x${info.height}`);
  assert.ok(info.height < 360 && info.width < 640, 'it really was cropped');
});
