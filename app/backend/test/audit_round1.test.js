// Findings from the first security/bug audit, each pinned by a test so it cannot come back.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { startServer, addUser, addPost } = require('./helpers');
const { openDb } = require('../src/db');

let phoneCounter = 0;
const newPhone = () => `+9197${String(20000000 + ++phoneCounter)}`;
const post = (s, url, json, user) => s.api('POST', url, { json, user });

async function startWithClock(extra = {}) {
  const clock = { now: Date.UTC(2026, 9, 17, 12, 0, 0) };
  const s = await startServer({ appOptions: { clock: () => clock.now, ...extra } });
  return { s, clock };
}

/** Real sign-up through the API. Returns { token, user, phone, password }. */
async function signUp(s, username, phone = newPhone()) {
  await post(s, '/api/auth/otp/send', { phone });
  const { code } = s.otpProvider.last(phone);
  const verified = await post(s, '/api/auth/otp/verify', { phone, code });
  const password = 'a decent passphrase';
  const res = await post(s, '/api/auth/signup', {
    signupToken: verified.data.signupToken, fullName: 'Test Person', username, dob: '2000-05-20', password
  });
  assert.equal(res.status, 201, JSON.stringify(res.data));
  return { ...res.data, phone, password };
}

const bearer = (token) => ({ authorization: `Bearer ${token}` });
const withToken = (s, method, url, token, json) => {
  return fetch(s.base + url, {
    method, headers: { ...bearer(token), ...(json ? { 'content-type': 'application/json' } : {}) },
    body: json ? JSON.stringify(json) : undefined
  }).then(async (r) => ({ status: r.status, data: await r.json().catch(() => null) }));
};

// ---------- the dev-user header ----------

test('the dev-user header is refused when the request was forwarded by a proxy', async () => {
  const s = await startServer(); // allowDevUser is on in tests
  try {
    addUser(s.db, 'me_dev');
    const direct = await s.api('GET', '/api/me', { user: 'me_dev' });
    assert.equal(direct.status, 200);
    for (const header of ['x-forwarded-for', 'x-real-ip', 'forwarded']) {
      const res = await fetch(`${s.base}/api/me`, { headers: { 'x-dev-user': 'me_dev', [header]: '203.0.113.9' } });
      assert.equal(res.status, 401, `${header} must disable the shortcut: on a real server that header means a stranger`);
    }
  } finally { await s.close(); }
});

// ---------- account deletion ----------

test('deleting an account: password required, data wiped, old tokens dead, other people\'s replies survive', async () => {
  const { s } = await startWithClock();
  try {
    const riya = await signUp(s, 'riya_k');
    const aman = await signUp(s, 'aman_s');
    const rootId = addPost(s.db, { userId: riya.user.id, title: 'Riya opinion', analysis: { transcript: 'secret words' } });
    fs.writeFileSync(path.join(s.uploadsDir, 'x.mp4'), 'video');
    fs.writeFileSync(path.join(s.uploadsDir, 'x-cover.jpg'), 'cover');
    s.db.run("UPDATE posts SET media_filename = 'x.mp4', cover_filename = 'x-cover.jpg' WHERE id = ?", [rootId]);
    const replyId = addPost(s.db, { userId: aman.user.id, parentId: rootId, stance: 'FOR', media: 'other.mp4' });
    const textId = addPost(s.db, { userId: riya.user.id, kind: 'TEXT', parentId: replyId, body: 'my private words', stance: 'AGAINST' });
    s.db.run('INSERT INTO follows (follower_id, followee_id, created_at) VALUES (?, ?, ?)', [aman.user.id, riya.user.id, 't']);
    s.db.run('INSERT INTO likes (user_id, post_id, created_at) VALUES (?, ?, ?)', [riya.user.id, replyId, 't']);

    // wrong or missing password: nothing happens
    assert.equal((await withToken(s, 'DELETE', '/api/me', riya.token, { password: 'wrong wrong wrong' })).status, 403);
    assert.equal((await withToken(s, 'DELETE', '/api/me', riya.token, {})).status, 403);
    assert.equal((await withToken(s, 'GET', '/api/me', riya.token)).status, 200);

    s.db.run("INSERT INTO shares (id, sender_id, recipient_id, post_id, created_at) VALUES ('sh1', ?, ?, ?, 'x')", [riya.user.id, aman.user.id, rootId]);
    const [lo, hi] = [riya.user.id, aman.user.id].sort();
    s.db.run("INSERT INTO conversations (id, user_lo, user_hi, created_at, last_message_at) VALUES ('cv1', ?, ?, 'x', 'x')", [lo, hi]);
    s.db.run("INSERT INTO messages (id, conversation_id, sender_id, kind, body, created_at) VALUES ('mg1', 'cv1', ?, 'TEXT', 'secret chat', 'x')", [riya.user.id]);
    s.db.run("INSERT INTO message_reactions (message_id, user_id, emoji, created_at) VALUES ('mg1', ?, '👍', 'x')", [aman.user.id]);
    s.db.run("INSERT INTO conversation_reads (conversation_id, user_id, read_at) VALUES ('cv1', ?, 'x')", [aman.user.id]);
    const del = await withToken(s, 'DELETE', '/api/me', riya.token, { password: riya.password });
    assert.deepEqual(del.data, { deleted: true });

    // the old token and the password both stop working at once
    assert.equal((await withToken(s, 'GET', '/api/me', riya.token)).status, 401);
    assert.equal((await post(s, '/api/auth/login', { identifier: 'riya_k', password: riya.password })).status, 401);
    assert.equal((await post(s, '/api/auth/login', { identifier: riya.phone, password: riya.password })).status, 401);

    // personal data is gone
    const row = s.db.get('SELECT * FROM users WHERE id = ?', [riya.user.id]);
    assert.match(row.username, /^deleted_/);
    for (const col of ['phone', 'email', 'dob', 'password_hash', 'avatar_url', 'bio']) assert.equal(row[col], null, col);
    assert.equal(row.full_name, 'Deleted user');
    assert.ok(row.deleted_at);
    assert.equal(s.db.get('SELECT COUNT(*) n FROM likes WHERE user_id = ?', [riya.user.id]).n, 0);
    assert.equal(s.db.get('SELECT COUNT(*) n FROM follows').n, 0);
    assert.equal(s.db.get('SELECT COUNT(*) n FROM shares').n, 0, 'videos she sent or was sent are gone');
    for (const table of ['conversations', 'messages', 'message_reactions', 'conversation_reads']) {
      assert.equal(s.db.get(`SELECT COUNT(*) n FROM ${table}`).n, 0, `${table}: her conversations are gone for both people`);
    }

    // her post is emptied but still anchors Aman's reply, and the counts did not change
    const root = s.db.get('SELECT * FROM posts WHERE id = ?', [rootId]);
    assert.equal(root.media_filename, null);
    assert.equal(root.cover_filename, null);
    assert.ok(!fs.existsSync(path.join(s.uploadsDir, 'x-cover.jpg')), 'the cover picture is deleted with the video');
    assert.equal(root.title, null);
    assert.equal(root.analysis, null);
    assert.ok(!/secret|riya/.test(root.search_text), 'what she said is gone from search too');
    assert.equal(s.db.get('SELECT body FROM posts WHERE id = ?', [textId]).body, '[deleted]'); // her words are gone
    const thread = await withToken(s, 'GET', `/api/posts/${rootId}/thread`, aman.token);
    assert.ok(!JSON.stringify(thread.data).includes('my private words'));
    assert.equal(thread.data.replies.length, 2); // Aman's reply and her emptied one
    assert.equal(thread.data.item.post.replyCount, 2);
    assert.equal(thread.data.item.actor.fullName, 'Deleted user');

    // she is not discoverable, followable, or shown in Discover
    assert.equal((await withToken(s, 'GET', `/api/users/${riya.user.id}`, aman.token)).status, 404);
    assert.equal((await withToken(s, 'POST', `/api/users/${riya.user.id}/follow`, aman.token)).status, 404);
    const feed = await s.api('GET', '/api/videos/feed');
    assert.ok(!feed.data.videos.some((v) => v.id === rootId));

    // her phone number can be used for a new account
    const again = await signUp(s, 'riya_new', riya.phone);
    assert.equal(again.user.username, 'riya_new');
  } finally { await s.close(); }
});

test('deleting an account removes the video files from disk', async () => {
  const { s } = await startWithClock();
  try {
    const riya = await signUp(s, 'riya_k');
    const file = path.join(s.uploadsDir, 'riya-clip.mp4');
    fs.writeFileSync(file, 'video');
    addPost(s.db, { userId: riya.user.id, media: 'riya-clip.mp4' });
    // a path trick in the stored name must not delete anything outside uploads
    const outside = path.join(os.tmpdir(), `outside-${Date.now()}.txt`);
    fs.writeFileSync(outside, 'keep me');
    addPost(s.db, { userId: riya.user.id, media: `../../../../..${outside}` });
    await withToken(s, 'DELETE', '/api/me', riya.token, { password: riya.password });
    assert.equal(fs.existsSync(file), false);
    assert.equal(fs.existsSync(outside), true);
    fs.rmSync(outside);
  } finally { await s.close(); }
});

test('replying to a deleted person\'s post still works; deleted authors vanish from Discover replies', async () => {
  const { s } = await startWithClock();
  try {
    const riya = await signUp(s, 'riya_k');
    const aman = await signUp(s, 'aman_s');
    const root = addPost(s.db, { userId: aman.user.id, title: 'Opinion' });
    const reply = addPost(s.db, { userId: riya.user.id, parentId: root, stance: 'FOR' });
    assert.equal((await s.api('GET', `/api/videos/${root}/replies`)).data.length, 1);
    await withToken(s, 'DELETE', '/api/me', riya.token, { password: riya.password });
    assert.equal((await s.api('GET', `/api/videos/${root}/replies`)).data.length, 0);
    assert.equal(s.db.get('SELECT status FROM posts WHERE id = ?', [reply]).status, 'READY');
  } finally { await s.close(); }
});

// ---------- SMS cost caps ----------

test('SMS cap per address: asking for codes to many numbers from one connection stops', async () => {
  const { s } = await startWithClock({ otpPerIpPerDay: 3 });
  try {
    for (let i = 0; i < 3; i++) assert.equal((await post(s, '/api/auth/otp/send', { phone: newPhone() })).status, 200);
    const blocked = await post(s, '/api/auth/otp/send', { phone: newPhone() });
    assert.equal(blocked.status, 429);
    assert.equal(s.otpProvider.sent.length, 3, 'no fourth SMS was paid for');
  } finally { await s.close(); }
});

test('SMS daily budget: sign-up pauses when spent, and comes back the next day', async () => {
  const { s, clock } = await startWithClock({ otpDailyBudget: 2, otpPerIpPerDay: 100 });
  try {
    assert.equal((await post(s, '/api/auth/otp/send', { phone: newPhone() })).status, 200);
    assert.equal((await post(s, '/api/auth/otp/send', { phone: newPhone() })).status, 200);
    const paused = await post(s, '/api/auth/otp/send', { phone: newPhone() });
    assert.equal(paused.status, 503);
    assert.match(paused.data.error, /paused/);
    clock.now += 24 * 3600 * 1000;
    assert.equal((await post(s, '/api/auth/otp/send', { phone: newPhone() })).status, 200);
  } finally { await s.close(); }
});

test('a failed SMS does not use up the budget', async () => {
  const { s } = await startWithClock({ otpDailyBudget: 1, otpPerIpPerDay: 1 });
  try {
    const real = s.otpProvider.send;
    s.otpProvider.send = async () => { throw new Error('gateway down'); };
    assert.equal((await post(s, '/api/auth/otp/send', { phone: newPhone() })).status, 502);
    s.otpProvider.send = real;
    assert.equal((await post(s, '/api/auth/otp/send', { phone: newPhone() })).status, 200);
  } finally { await s.close(); }
});

// ---------- Discover write limits ----------

test('watch-time pings are rate limited so they cannot flood the database', async () => {
  const s = await startServer({ appOptions: { rateLimit: { interact: { max: 3, windowMs: 60000 } } } });
  try {
    addUser(s.db, 'viewer');
    const author = addUser(s.db, 'author');
    const video = addPost(s.db, { userId: author, title: 'x' });
    const ping = () => s.api('POST', `/api/videos/${video}/views`, { user: 'viewer', json: { watchedMs: 1 } });
    for (let i = 0; i < 3; i++) assert.equal((await ping()).status, 200);
    const limited = await ping();
    assert.equal(limited.status, 429);
    assert.ok(limited.data.retryAfterSec >= 1);
    assert.equal(s.db.get('SELECT COUNT(*) n FROM post_views').n, 3);
  } finally { await s.close(); }
});

// ---------- old database files ----------

test('an existing database from before account deletion is upgraded in place, keeping its data', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'forest-migrate-'));
  const file = path.join(dir, 'old.db');
  try {
    // Build a file with the OLD users table (no deleted_at) and one user in it.
    const initSqlJs = require('sql.js');
    const SQL = await initSqlJs();
    const old = new SQL.Database();
    old.run(`CREATE TABLE users (id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE COLLATE NOCASE, full_name TEXT NOT NULL,
      is_bot INTEGER NOT NULL DEFAULT 0, avatar_url TEXT, bio TEXT, phone TEXT, phone_verified INTEGER NOT NULL DEFAULT 0,
      email TEXT, dob TEXT, password_hash TEXT, created_at TEXT NOT NULL)`);
    old.run("INSERT INTO users (id, username, full_name, created_at) VALUES ('u1', 'veteran', 'Old User', 't')");
    fs.writeFileSync(file, Buffer.from(old.export()));
    old.close();

    const db = await openDb({ file });
    assert.equal(db.get("SELECT username FROM users WHERE id = 'u1'").username, 'veteran');
    assert.equal(db.get("SELECT deleted_at FROM users WHERE id = 'u1'").deleted_at, null);
    db.close();
    const again = await openDb({ file }); // running it twice is harmless
    assert.equal(again.get('SELECT COUNT(*) n FROM users').n, 1);
    again.close();
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});

// ---------- found in audit round 3 ----------

test('analysis that finishes after the author deleted their account is thrown away, not written back', async () => {
  let release;
  const gate = new Promise((r) => { release = r; });
  const s = await startServer({
    analyzer: {
      analyzeAudio: async () => { await gate; return { transcript: 'private spoken words', detectedStance: 'FOR', overallSummary: 's', claims: [] }; }
    }
  });
  try {
    const riya = await signUp(s, 'riya_k');
    const form = new FormData();
    form.append('kind', 'VIDEO');
    form.append('title', 'My opinion');
    form.append('video', new Blob(['fake'], { type: 'video/mp4' }), 'clip.mp4');
    const created = await fetch(`${s.base}/api/posts`, { method: 'POST', headers: bearer(riya.token), body: form });
    assert.equal(created.status, 201);
    const postId = (await created.json()).post.id;

    // she deletes her account while the AI is still working on the video
    const del = await withToken(s, 'DELETE', '/api/me', riya.token, { password: riya.password });
    assert.equal(del.status, 200);
    release();
    await s.idle();

    const row = s.db.get('SELECT * FROM posts WHERE id = ?', [postId]);
    assert.equal(row.analysis, null, 'her transcript must not come back after deletion');
    assert.equal(row.media_filename, null);
    assert.equal(row.status, 'FAILED', 'the emptied post is not published, and no longer holds a place in the processing queue');
    assert.equal(s.db.get("SELECT COUNT(*) n FROM posts WHERE status = 'PROCESSING'").n, 0);
  } finally { await s.close(); }
});

test('nobody can register a name that a deleted account is renamed to', async () => {
  const { s } = await startWithClock();
  try {
    const ask = (u) => s.api('GET', `/api/auth/username-available?u=${u}`);
    assert.deepEqual((await ask('deleted_0123456789')).data, { available: false, reason: 'RESERVED' });
    assert.deepEqual((await ask('Deleted.user')).data, { available: false, reason: 'RESERVED' });
  } finally { await s.close(); }
});
