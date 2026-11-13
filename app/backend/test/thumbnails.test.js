// Every uploaded video gets a still picture (the Discover grid tile and the poster before it plays).
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { startServer, addUser, videoForm } = require('./helpers');
const { makeThumbnail } = require('../src/services/thumbnailService');

function findFfmpeg() {
  const candidates = [process.env.FFMPEG_PATH];
  try { candidates.push(require('ffmpeg-static')); } catch { /* not installed */ }
  return candidates.filter(Boolean).find((p) => fs.existsSync(p) && spawnSync(p, ['-version']).status === 0) || null;
}
const FF = findFfmpeg();
const skip = FF ? false : 'no working ffmpeg (npm install downloads one)';

async function post(s, user, fields = {}) {
  const res = await s.api('POST', '/api/posts', { user, form: videoForm({ kind: 'VIDEO', title: 'A view', ...fields }) });
  assert.equal(res.status, 201, JSON.stringify(res.data));
  await s.idle();
  return res.data.post.id;
}

test('an uploaded video gets a cover picture, and every place that lists it says where it is', async () => {
  const s = await startServer({
    analyzer: { makeThumbnail: async (video, out) => { fs.writeFileSync(out, 'jpeg-bytes'); return true; } }
  });
  try {
    addUser(s.db, 'aman');
    const id = await post(s, 'aman');
    const row = s.db.get('SELECT media_filename, cover_filename FROM posts WHERE id = ?', [id]);
    assert.ok(row.cover_filename && row.cover_filename.endsWith('-cover.jpg'));
    assert.ok(fs.existsSync(path.join(s.uploadsDir, row.cover_filename)));

    const feed = await s.api('GET', '/api/videos/feed', { user: 'aman' });
    assert.equal(feed.data.videos[0].coverUrl, `/uploads/${row.cover_filename}`, 'the grid reads this');
    const one = await s.api('GET', `/api/posts/${id}`, { user: 'aman' });
    assert.equal(one.data.post.coverUrl, `/uploads/${row.cover_filename}`, 'and so does Home');
    assert.equal((await s.api('GET', `/uploads/${row.cover_filename}`)).status, 200);
  } finally { await s.close(); }
});

test('a thumbnail that cannot be made leaves a post that works, with no cover', async () => {
  const s = await startServer({ analyzer: { makeThumbnail: async () => false } });
  try {
    addUser(s.db, 'aman');
    const id = await post(s, 'aman');
    const row = s.db.get('SELECT status, cover_filename FROM posts WHERE id = ?', [id]);
    assert.equal(row.status, 'READY');
    assert.equal(row.cover_filename, null);
    const feed = await s.api('GET', '/api/videos/feed', { user: 'aman' });
    assert.equal(feed.data.videos[0].coverUrl, null);
  } finally { await s.close(); }
});

test('a thumbnail step that throws also leaves a working post', async () => {
  const s = await startServer({ analyzer: { makeThumbnail: async () => { throw new Error('ffmpeg exploded'); } } });
  try {
    addUser(s.db, 'aman');
    const id = await post(s, 'aman');
    assert.equal(s.db.get('SELECT status FROM posts WHERE id = ?', [id]).status, 'READY');
  } finally { await s.close(); }
});

test('a post that fails after its cover was made does not leave the picture behind', async () => {
  const s = await startServer({
    analyzer: {
      makeThumbnail: async (video, out) => { fs.writeFileSync(out, 'jpeg-bytes'); return true; },
      analyzeAudio: async () => { throw new Error('gemini is down'); }
    }
  });
  try {
    addUser(s.db, 'aman');
    const before = fs.readdirSync(s.uploadsDir).filter((f) => f.endsWith('-cover.jpg'));
    const id = await post(s, 'aman');
    const row = s.db.get('SELECT status, cover_filename FROM posts WHERE id = ?', [id]);
    assert.equal(row.status, 'FAILED');
    assert.equal(row.cover_filename, null);
    assert.deepEqual(fs.readdirSync(s.uploadsDir).filter((f) => f.endsWith('-cover.jpg')), before);
  } finally { await s.close(); }
});

test('makeThumbnail: a real clip gives a JPEG; a clip under a second falls back to its first frame; a non-video gives false', { skip }, async () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'forest-thumb-'));
  try {
    const run = (...a) => assert.equal(spawnSync(FF, ['-y', '-loglevel', 'error', ...a]).status, 0);
    const long = path.join(tmp, 'long.mp4');
    const short = path.join(tmp, 'short.mp4');
    run('-f', 'lavfi', '-i', 'testsrc=size=640x360:rate=25', '-t', '3', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', long);
    run('-f', 'lavfi', '-i', 'testsrc=size=640x360:rate=25', '-t', '0.4', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', short);

    for (const [video, name] of [[long, 'a.jpg'], [short, 'b.jpg']]) {
      const out = path.join(tmp, name);
      assert.equal(await makeThumbnail(video, out), true, name);
      const bytes = fs.readFileSync(out);
      assert.deepEqual([...bytes.subarray(0, 2)], [0xff, 0xd8], 'a JPEG');
      assert.ok(bytes.length > 1000);
    }
    fs.writeFileSync(path.join(tmp, 'junk.mp4'), 'not a video');
    assert.equal(await makeThumbnail(path.join(tmp, 'junk.mp4'), path.join(tmp, 'c.jpg')), false);
    assert.ok(!fs.existsSync(path.join(tmp, 'c.jpg')), 'no half-written file is left');
  } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
});
