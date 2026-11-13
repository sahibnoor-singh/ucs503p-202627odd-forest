const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { startServer, addUser, addPost, videoForm } = require('./helpers');
const { openDb } = require('../src/db');

test('legacy GET /api/videos/all keeps the old row shape the Flutter app parses', async () => {
  const s = await startServer();
  try {
    const u = addUser(s.db, 'aman');
    const p = addPost(s.db, { userId: u, title: 'Opinion', minutesAgo: 10,
      analysis: { transcript: 't', overallSummary: 'sum', claims: [] } });
    const r = addPost(s.db, { userId: u, parentId: p, stance: 'AGAINST', minutesAgo: 5 });
    addPost(s.db, { userId: u, kind: 'TEXT', parentId: p, body: 'text replies are not videos' });

    const { status, data } = await s.api('GET', '/api/videos/all'); // no sign-in, like before
    assert.equal(status, 200);
    assert.equal(data.length, 2); // text replies are not legacy videos
    assert.deepEqual(Object.keys(data[0]).sort(), [
      'created_at', 'filename', 'id', 'parent_video_id', 'role', 'stance', 'status', 'title', 'transcript', 'user_id'
    ]);
    assert.equal(data[0].id, p);
    assert.equal(data[0].role, 'PARENT');
    assert.equal(data[0].user_id, 'aman');
    assert.equal(data[0].transcript.overallSummary, 'sum');
    assert.equal(data[1].role, 'CHILD');
    assert.equal(data[1].parent_video_id, p);
    assert.equal(data[1].stance, 'AGAINST');
  } finally { await s.close(); }
});

test('legacy upload: no sign-in, creates a bot-labelled user, replies need a parent', async () => {
  const s = await startServer();
  try {
    let res = await s.api('POST', '/api/videos/upload', {
      form: videoForm({ role: 'PARENT', title: 'From the Upload tab', userId: 'Test User!' })
    });
    assert.equal(res.status, 201);
    assert.equal(res.data.video.role, 'PARENT');
    assert.equal(res.data.video.status, 'PROCESSING');
    assert.equal(res.data.video.user_id, 'test_user_');
    assert.equal(s.db.get('SELECT is_bot FROM users WHERE username = ?', ['test_user_']).is_bot, 1);
    const parentId = res.data.video.id;
    await s.idle();

    res = await s.api('POST', '/api/videos/upload', { form: videoForm({ role: 'CHILD', parentVideoId: parentId }) });
    assert.equal(res.status, 201);
    assert.equal(res.data.video.role, 'CHILD');
    assert.equal(res.data.video.parent_video_id, parentId);
    await s.idle();

    const before = fs.readdirSync(s.uploadsDir).length;
    res = await s.api('POST', '/api/videos/upload', { form: videoForm({ role: 'CHILD' }) });
    assert.equal(res.status, 400);
    assert.equal(fs.readdirSync(s.uploadsDir).length, before); // no orphan file

    res = await s.api('POST', '/api/videos/upload', { form: new FormData() });
    assert.equal(res.status, 400);
  } finally { await s.close(); }
});

test('legacy upload can never post as a real (non-bot) account', async () => {
  const s = await startServer();
  try {
    addUser(s.db, 'me_dev'); // a real person
    const res = await s.api('POST', '/api/videos/upload', { form: videoForm({ role: 'PARENT', userId: 'me_dev' }) });
    assert.equal(res.status, 201);
    assert.equal(res.data.video.user_id, 'legacy_upload'); // not me_dev
    assert.equal(s.db.get("SELECT COUNT(*) AS n FROM posts WHERE user_id = (SELECT id FROM users WHERE username = 'me_dev')").n, 0);
    assert.equal(s.db.get("SELECT is_bot FROM users WHERE username = 'legacy_upload'").is_bot, 1);
    await s.idle();
  } finally { await s.close(); }
});

test('database file persists across restarts (atomic write, schema is idempotent)', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'forest-db-'));
  const file = path.join(dir, 'nested', 'app.db');
  try {
    let db = await openDb({ file });
    const u = addUser(db, 'persisted');
    addPost(db, { userId: u, title: 'still here' });
    db.close();
    assert.ok(fs.existsSync(file));
    assert.ok(!fs.existsSync(`${file}.tmp`));

    db = await openDb({ file }); // schema runs again on an existing file
    assert.equal(db.get('SELECT COUNT(*) AS n FROM users').n, 1);
    assert.equal(db.get('SELECT title FROM posts').title, 'still here');

    // a failed transaction leaves nothing behind
    assert.throws(() => db.tx(() => {
      db.run("INSERT INTO users (id, username, full_name, created_at) VALUES ('z', 'zed', 'zed', 'now')");
      db.run("INSERT INTO users (id, username, full_name, created_at) VALUES ('z2', 'ZED', 'dup', 'now')"); // NOCASE unique
    }));
    assert.equal(db.get("SELECT COUNT(*) AS n FROM users WHERE username = 'zed'").n, 0);
    db.close();
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});

test('usernames are unique case-insensitively', async () => {
  const db = await openDb();
  addUser(db, 'Aman');
  assert.throws(() => addUser(db, 'aman'));
  db.close();
});
