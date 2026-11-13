// POST /api/posts/compose and the render jobs, with a fake renderer (no ffmpeg needed). Real ffmpeg is in compose_render.test.js.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { startServer, addUser, addPost } = require('./helpers');

/** A renderer that writes tiny placeholder files and records what it was asked to do. Content prefixes steer probe(). */
function fakeComposer() {
  const c = {
    calls: { probe: [], render: [] },
    failRender: false,
    noCover: false,
    gate: null,
    async probe(file) {
      c.calls.probe.push(path.basename(file));
      const head = fs.readFileSync(file, 'utf8').slice(0, 12);
      if (head.startsWith('NOT-MEDIA')) throw new Error('unreadable');
      if (head.startsWith('SILENT')) return { durationSec: 10, hasVideo: true, hasAudio: false };
      if (head.startsWith('AUDIO-ONLY')) return { durationSec: 5, hasVideo: false, hasAudio: true };
      if (head.startsWith('PICTURE-ONLY')) return { durationSec: 5, hasVideo: true, hasAudio: false };
      return { durationSec: 10, hasVideo: true, hasAudio: true };
    },
    async render(o) {
      c.calls.render.push(o);
      if (c.gate) await c.gate;
      if (c.failRender) throw new Error('render exploded');
      fs.writeFileSync(o.outPath, 'FAKE-MP4');
      if (o.voicePath) fs.writeFileSync(o.voicePath, 'voice');
      if (o.coverPath && !c.noCover) fs.writeFileSync(o.coverPath, 'FAKE-JPG');
      return { cover: !!o.coverPath && !c.noCover };
    }
  };
  return c;
}

async function boot(opts = {}) {
  const composer = fakeComposer();
  const s = await startServer({ ...opts, appOptions: { composer, moderationToken: 'tok', ...(opts.appOptions || {}) } });
  const composeDir = `${s.uploadsDir}-compose`;
  const close = s.close;
  s.close = async () => { await close(); fs.rmSync(composeDir, { recursive: true, force: true }); };
  addUser(s.db, 'poster');
  return { s, composer, composeDir };
}

function form({ recipe, photos = [], music, video, parentId, title, body }) {
  const fd = new FormData();
  if (recipe !== undefined) fd.append('recipe', typeof recipe === 'string' ? recipe : JSON.stringify(recipe));
  const blob = (f) => new Blob([f.content || 'IMAGE-BYTES'], { type: f.type });
  photos.forEach((p) => fd.append('photos', blob(p), p.name));
  if (music) fd.append('music', blob(music), music.name);
  if (video) fd.append('video', blob(video), video.name);
  for (const [k, v] of Object.entries({ parentId, title, body })) if (v !== undefined) fd.append(k, v);
  return fd;
}
const jpg = (name = 'a.jpg', content) => ({ name, type: 'image/jpeg', content });
const mp3 = (content) => ({ name: 'song.mp3', type: 'audio/mpeg', content });
const mp4 = (content) => ({ name: 'clip.mp4', type: 'video/mp4', content });
const send = (s, f, user = 'poster') => s.api('POST', '/api/posts/compose', { user, form: f });
const TEXT = { mode: 'TEXT', text: { content: 'Phones should be banned in class' } };
const filesIn = (dir) => fs.readdirSync(dir);

test('compose needs a signed-in user', async () => {
  const { s } = await boot();
  try {
    const res = await s.api('POST', '/api/posts/compose', { form: form({ recipe: TEXT }) });
    assert.equal(res.status, 401);
  } finally { await s.close(); }
});

test('bad requests are refused with the field that is wrong, and no input file is left behind', async () => {
  const { s, composeDir } = await boot();
  try {
    const cases = [
      [form({ recipe: 'not json' }), 'recipe'],
      [form({}), 'recipe'],
      [form({ recipe: { mode: 'GIF' } }), 'mode'],
      [form({ recipe: { mode: 'TEXT' } }), 'text'],
      [form({ recipe: TEXT, photos: [jpg()] }), 'photos'],
      [form({ recipe: { mode: 'PHOTOS' } }), 'photos'],
      [form({ recipe: { mode: 'PHOTOS' }, photos: [{ name: 'a.gif', type: 'image/gif' }] }), 'photos'],
      [form({ recipe: { mode: 'PHOTOS' }, photos: [{ name: 'a.jpg', type: 'text/html' }] }), 'photos'],
      [form({ recipe: { mode: 'PHOTOS' }, photos: Array.from({ length: 11 }, (_, i) => jpg(`${i}.jpg`)) }), null],
      [form({ recipe: TEXT, music: { name: 'song.exe', type: 'audio/mpeg' } }), 'music'],
      [form({ recipe: TEXT, music: mp3('AUDIO-ONLY') }), null, 201],
      [form({ recipe: TEXT, music: mp3('PICTURE-ONLY') }), 'music'],
      [form({ recipe: TEXT, music: mp3('NOT-MEDIA') }), 'music'],
      [form({ recipe: { mode: 'VIDEO' }, video: mp4('NOT-MEDIA') }), 'video'],
      [form({ recipe: { mode: 'VIDEO' }, video: mp4('AUDIO-ONLY') }), 'video'],
      [form({ recipe: { mode: 'VIDEO' } }), 'video'],
      [form({ recipe: TEXT, video: mp4() }), 'video'],
      [form({ recipe: TEXT, body: 'x'.repeat(281) }), 'body'],
      [form({ recipe: TEXT, title: 'x'.repeat(121) }), 'title'],
      [form({ recipe: TEXT, parentId: 'does-not-exist' }), null, 404]
    ];
    for (const [fd, field, expect = 400] of cases) {
      const res = await send(s, fd);
      assert.equal(res.status, expect, JSON.stringify(res.data));
      if (expect === 400 && field) assert.equal(res.data.field, field, JSON.stringify(res.data));
    }
    // only the one accepted case (AUDIO-ONLY music with a text post) may have left inputs behind
    assert.equal(filesIn(composeDir).filter((f) => !f.endsWith('-music.mp3')).length, 0);
  } finally { await s.close(); }
});

test('a text post: accepted at once as PROCESSING, rendered, analysed from its words, inputs gone', async () => {
  const { s, composer, composeDir } = await boot();
  try {
    const res = await send(s, form({ recipe: { ...TEXT, text: { content: 'Phones should be banned in class', animation: 'typewriter' } }, title: 'Phones in class?' }));
    assert.equal(res.status, 201, JSON.stringify(res.data));
    assert.equal(res.data.post.status, 'PROCESSING');
    assert.equal(res.data.post.mediaUrl, null);
    assert.equal(res.data.post.title, 'Phones in class?');
    assert.equal(res.data.type, 'POST');
    await s.idle();

    const row = s.db.get('SELECT * FROM posts WHERE id = ?', [res.data.post.id]);
    assert.equal(row.status, 'READY');
    assert.match(row.media_filename, /-composed\.mp4$/);
    assert.equal(row.recipe, null, 'the recipe is not kept once rendered');
    assert.equal(JSON.parse(row.analysis).transcript, 'Phones should be banned in class');
    assert.equal(JSON.parse(row.analysis).source, 'TEXT');
    assert.equal(row.stance, 'PARENT');
    assert.equal(s.calls.analyze.length, 0, 'there was no speech to send to Gemini');
    assert.equal(composer.calls.render[0].recipe.text.animation, 'typewriter');
    assert.equal(filesIn(composeDir).length, 0);

    const served = await fetch(`${s.base}/uploads/${row.media_filename}`);
    assert.equal(served.status, 200);
    const feed = await s.api('GET', '/api/videos/feed');
    assert.equal(feed.data.videos[0].id, res.data.post.id);
  } finally { await s.close(); }
});

test('a rendered post gets a cover picture, served beside its video and named in coverUrl', async () => {
  const { s, composer } = await boot();
  try {
    const res = await send(s, form({ recipe: { ...TEXT, coverSec: 1.5 } }));
    assert.equal(res.status, 201, JSON.stringify(res.data));
    assert.equal(res.data.post.coverUrl, null, 'not there until it is rendered');
    await s.idle();
    assert.equal(composer.calls.render[0].recipe.coverSec, 1.5);
    assert.match(composer.calls.render[0].coverPath, /-composed-cover\.jpg$/);

    const row = s.db.get('SELECT * FROM posts WHERE id = ?', [res.data.post.id]);
    assert.equal(row.cover_filename, row.media_filename.replace(/\.mp4$/, '-cover.jpg'));
    const item = await s.api('GET', `/api/posts/${res.data.post.id}`);
    assert.equal(item.data.post.coverUrl, `/uploads/${row.cover_filename}`);
    const served = await fetch(`${s.base}/uploads/${row.cover_filename}`);
    assert.equal(served.status, 200);
  } finally { await s.close(); }
});

test('when the cover could not be made the post is still fine, just without one', async () => {
  const { s, composer } = await boot();
  try {
    composer.noCover = true;
    const res = await send(s, form({ recipe: TEXT }));
    await s.idle();
    const row = s.db.get('SELECT * FROM posts WHERE id = ?', [res.data.post.id]);
    assert.equal(row.status, 'READY');
    assert.equal(row.cover_filename, null);
    const item = await s.api('GET', `/api/posts/${res.data.post.id}`);
    assert.equal(item.data.post.coverUrl, null);
  } finally { await s.close(); }
});

test('a post that fails after rendering leaves no cover behind', async () => {
  const { s, composer } = await boot({ appOptions: { analyzer: undefined } });
  try {
    const res = await send(s, form({ recipe: TEXT }));
    await s.idle();
    const ok = s.db.get('SELECT * FROM posts WHERE id = ?', [res.data.post.id]);
    assert.equal(ok.status, 'READY');
    composer.failRender = true;
    const failed = await send(s, form({ recipe: { ...TEXT, text: { content: 'second' } } }));
    await s.idle();
    const row = s.db.get('SELECT * FROM posts WHERE id = ?', [failed.data.post.id]);
    assert.equal(row.status, 'FAILED');
    assert.equal(row.cover_filename, null);
    const covers = fs.readdirSync(s.uploadsDir).filter((f) => f.endsWith('-cover.jpg'));
    assert.deepEqual(covers, [ok.cover_filename], 'only the good post has a cover file');
  } finally { await s.close(); }
});

test('the editor\'s input files are never served publicly', async () => {
  // A short deadline: the render below never finishes, so the job gives up after 0.3 s and the test can end.
  const { s, composer, composeDir } = await boot({ appOptions: { jobTimeoutMs: 300 } });
  try {
    composer.gate = new Promise(() => {}); // the render never finishes, so the inputs stay in place
    const res = await send(s, form({ recipe: { mode: 'PHOTOS' }, photos: [jpg()] }));
    assert.equal(res.status, 201);
    const names = filesIn(composeDir);
    assert.ok(names.length >= 1);
    for (const n of names) assert.equal((await fetch(`${s.base}/uploads/${n}`)).status, 404);
    for (const n of names) assert.equal((await fetch(`${s.base}/${n}`)).status, 404);
  } finally { await s.close(); }
});

test('a text reply is classified by the AI against the post it answers', async () => {
  const { s } = await boot({ textStance: 'AGAINST' });
  try {
    const author = addUser(s.db, 'author');
    const root = addPost(s.db, { userId: author, title: 'Should phones be banned?', analysis: { transcript: 'Phones distract students' } });
    const res = await send(s, form({ recipe: { mode: 'TEXT', text: { content: 'No, they are useful tools' } }, parentId: root }));
    assert.equal(res.status, 201);
    assert.equal(res.data.type, 'VIDEO_REPLY');
    await s.idle();
    assert.equal(s.db.get('SELECT stance FROM posts WHERE id = ?', [res.data.post.id]).stance, 'AGAINST');
    assert.equal(s.calls.classify[0].text, 'No, they are useful tools');
    assert.match(s.calls.classify[0].ctx, /Phones distract students/);
  } finally { await s.close(); }
});

test('if the AI cannot be reached a reply stays UNRESOLVED instead of failing', async () => {
  const { s } = await boot({ analyzer: { classifyReplyText: async () => { throw new Error('quota'); } } });
  try {
    const author = addUser(s.db, 'author');
    const root = addPost(s.db, { userId: author, title: 'Q' });
    const res = await send(s, form({ recipe: TEXT, parentId: root }));
    await s.idle();
    const row = s.db.get('SELECT * FROM posts WHERE id = ?', [res.data.post.id]);
    assert.equal(row.status, 'READY');
    assert.equal(row.stance, 'UNRESOLVED');
  } finally { await s.close(); }
});

test('a video with speech: the voice-only track goes to Gemini, the caption and overlay text are added to the transcript', async () => {
  const { s, composer } = await boot();
  try {
    const res = await send(s, form({
      recipe: { mode: 'VIDEO', trim: { startSec: 1, endSec: 6 }, overlays: [{ text: 'overlay says hi' }], music: { volume: 0.3 } },
      video: mp4(), music: mp3(), body: 'my caption'
    }));
    assert.equal(res.status, 201, JSON.stringify(res.data));
    await s.idle();
    const call = composer.calls.render[0];
    assert.equal(call.recipe.trim.endSec, 6);
    assert.ok(call.voicePath, 'asks for a separate speech track');
    assert.ok(call.inputs.video && call.inputs.music);
    assert.equal(s.calls.analyze.length, 1, 'speech was analysed');
    const analysis = JSON.parse(s.db.get('SELECT analysis FROM posts WHERE id = ?', [res.data.post.id]).analysis);
    assert.match(analysis.transcript, /spoken words/);
    assert.match(analysis.transcript, /overlay says hi/);
    assert.match(analysis.transcript, /my caption/);
  } finally { await s.close(); }
});

test('a muted video, or one with no sound, is analysed from the words instead of audio', async () => {
  const { s, composer } = await boot();
  try {
    await send(s, form({ recipe: { mode: 'VIDEO', muteOriginal: true }, video: mp4(), body: 'muted caption' }));
    await send(s, form({ recipe: { mode: 'VIDEO' }, video: mp4('SILENT-VIDEO'), body: 'silent caption' }));
    await s.idle();
    assert.equal(s.calls.analyze.length, 0);
    assert.equal(composer.calls.render[0].voicePath, null);
    const texts = s.db.all('SELECT analysis FROM posts ORDER BY created_at').map((r) => JSON.parse(r.analysis).transcript);
    assert.deepEqual(texts, ['muted caption', 'silent caption']);
  } finally { await s.close(); }
});

test('photos are rendered in the order the person chose', async () => {
  const { s, composer } = await boot();
  try {
    const res = await send(s, form({
      recipe: { mode: 'PHOTOS', photoOrder: [2, 0, 1], slideSeconds: 2 },
      photos: [jpg('one.jpg'), jpg('two.png'), jpg('three.webp')].map((p, i) => ({ ...p, type: ['image/jpeg', 'image/png', 'image/webp'][i] }))
    }));
    assert.equal(res.status, 201, JSON.stringify(res.data));
    await s.idle();
    const { inputs } = composer.calls.render[0];
    assert.deepEqual(inputs.photos.map((p) => path.basename(p).split('-').pop()), ['photos.webp', 'photos.jpg', 'photos.png']);
    assert.equal(s.db.get('SELECT status FROM posts').status, 'READY');
  } finally { await s.close(); }
});

test('the automatic word screen also covers what was typed in the editor', async () => {
  const { s } = await boot({ appOptions: { moderationBlocklist: ['badword'] } });
  try {
    const res = await send(s, form({ recipe: { mode: 'TEXT', text: { content: 'this is a BADWORD post' } } }));
    await s.idle();
    assert.equal(s.db.get('SELECT status FROM posts WHERE id = ?', [res.data.post.id]).status, 'HIDDEN');
    const clean = await send(s, form({ recipe: TEXT, body: 'a badword in the caption' }));
    await s.idle();
    assert.equal(s.db.get('SELECT status FROM posts WHERE id = ?', [clean.data.post.id]).status, 'HIDDEN');
  } finally { await s.close(); }
});

test('a failed render marks the post FAILED, leaves no video file, keeps the inputs, and Retry finishes it', async () => {
  const { s, composer, composeDir } = await boot();
  try {
    composer.failRender = true;
    const res = await send(s, form({ recipe: { mode: 'PHOTOS' }, photos: [jpg()] }));
    await s.idle();
    assert.equal(s.db.get('SELECT status FROM posts WHERE id = ?', [res.data.post.id]).status, 'FAILED');
    assert.equal(filesIn(s.uploadsDir).length, 0);
    assert.equal(filesIn(composeDir).length, 1, 'the photo is kept so Retry can use it');

    composer.failRender = false;
    const retry = await s.api('POST', `/api/posts/${res.data.post.id}/retry`, { user: 'poster' });
    assert.equal(retry.status, 200, JSON.stringify(retry.data));
    await s.idle();
    assert.equal(s.db.get('SELECT status FROM posts WHERE id = ?', [res.data.post.id]).status, 'READY');
    assert.equal(filesIn(composeDir).length, 0);
  } finally { await s.close(); }
});

test('Retry says the file is gone when the editor inputs were lost', async () => {
  const { s, composer, composeDir } = await boot();
  try {
    composer.failRender = true;
    const res = await send(s, form({ recipe: { mode: 'PHOTOS' }, photos: [jpg()] }));
    await s.idle();
    for (const f of filesIn(composeDir)) fs.rmSync(path.join(composeDir, f));
    assert.equal((await s.api('POST', `/api/posts/${res.data.post.id}/retry`, { user: 'poster' })).status, 410);
  } finally { await s.close(); }
});

test('deleting the account while a post is rendering: the video and the inputs do not survive', async () => {
  const { s, composer, composeDir } = await boot();
  try {
    const { hashPassword } = require('../src/auth/password');
    s.db.run("UPDATE users SET password_hash = ? WHERE username = 'poster'", [await hashPassword('a decent passphrase')]);
    let release;
    composer.gate = new Promise((r) => { release = r; });
    const res = await send(s, form({ recipe: { mode: 'PHOTOS' }, photos: [jpg()] }));
    assert.equal(res.status, 201);
    assert.equal(filesIn(composeDir).length, 1, 'the photo is waiting in the compose folder');
    await new Promise((r) => setTimeout(r, 30)); // the job is now inside the (gated) render
    const del = await s.api('DELETE', '/api/me', { user: 'poster', json: { password: 'a decent passphrase' } });
    assert.equal(del.status, 200);
    release();
    await s.idle();
    const row = s.db.get('SELECT * FROM posts WHERE id = ?', [res.data.post.id]);
    assert.equal(row.media_filename, null);
    assert.equal(row.analysis, null);
    assert.equal(row.recipe, null);
    assert.equal(row.status, 'FAILED');
    assert.equal(filesIn(s.uploadsDir).length, 0, 'the rendered file was thrown away');
    assert.equal(filesIn(composeDir).length, 0);
  } finally { await s.close(); }
});

test('the per-person queue limit applies to editor posts too, and the refused one leaves no files', async () => {
  const { s, composer, composeDir } = await boot({ appOptions: { jobTimeoutMs: 300 } });
  try {
    composer.gate = new Promise(() => {}); // renders never finish (until the 0.3 s deadline): the posts stay PROCESSING meanwhile
    for (let i = 0; i < 5; i++) assert.equal((await send(s, form({ recipe: { mode: 'PHOTOS' }, photos: [jpg()] }))).status, 201);
    const before = filesIn(composeDir).length;
    const sixth = await send(s, form({ recipe: { mode: 'PHOTOS' }, photos: [jpg()] }));
    assert.equal(sixth.status, 429);
    assert.equal(filesIn(composeDir).length, before);
  } finally { await s.close(); }
});

test('replying to someone who blocked you is refused and cleans up', async () => {
  const { s, composeDir } = await boot();
  try {
    const author = addUser(s.db, 'author');
    const poster = s.db.get("SELECT id FROM users WHERE username = 'poster'").id;
    const root = addPost(s.db, { userId: author, title: 'Q' });
    s.db.run('INSERT INTO blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, ?)', [author, poster, 't']);
    const res = await send(s, form({ recipe: { mode: 'PHOTOS' }, photos: [jpg()], parentId: root }));
    assert.equal(res.status, 403);
    assert.equal(filesIn(composeDir).length, 0);
  } finally { await s.close(); }
});

test('after a restart, editor posts that were waiting are rendered', async () => {
  const { s, composeDir } = await boot();
  try {
    const poster = s.db.get("SELECT id FROM users WHERE username = 'poster'").id;
    fs.writeFileSync(path.join(composeDir, 'waiting-photos.jpg'), 'IMAGE-BYTES');
    const recipe = JSON.stringify({ render: { mode: 'PHOTOS', photoOrder: [0], slideSeconds: 3, durationSec: 3, overlays: [], transition: 'fade' }, files: { photos: ['waiting-photos.jpg'] } });
    s.db.run(
      `INSERT INTO posts (id, user_id, kind, parent_id, root_id, depth, title, body, media_filename, stance, status, recipe, created_at)
       VALUES ('waiting', ?, 'VIDEO', NULL, 'waiting', 0, NULL, NULL, NULL, 'PARENT', 'PROCESSING', ?, ?)`, [poster, recipe, new Date().toISOString()]);
    s.app.locals.jobs.resumePending();
    await s.idle();
    assert.equal(s.db.get("SELECT status FROM posts WHERE id = 'waiting'").status, 'READY');
  } finally { await s.close(); }
});

test('compose is rate limited like other posts', async () => {
  const { s } = await boot({ appOptions: { rateLimit: { post: { max: 2, windowMs: 60000 } } } });
  try {
    assert.equal((await send(s, form({ recipe: TEXT }))).status, 201);
    assert.equal((await send(s, form({ recipe: TEXT }))).status, 201);
    assert.equal((await send(s, form({ recipe: TEXT }))).status, 429);
  } finally { await s.close(); }
});
