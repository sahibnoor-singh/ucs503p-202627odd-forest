const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const initSqlJs = require('sql.js');
const { startServer, addUser, follow } = require('./helpers');
const { seed, DEV_LOGIN } = require('../scripts/seed');
const { importLegacy } = require('../scripts/import_legacy');

test('seed: gives the dev user a Home feed, every sample person is a labelled bot', async () => {
  const s = await startServer();
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'forest-seed-'));
  try {
    const media = path.join(tmp, 'clips');
    fs.mkdirSync(media);
    fs.writeFileSync(path.join(media, 'a.mp4'), 'a');
    fs.writeFileSync(path.join(media, 'notes.txt'), 'ignored');
    const out = await seed(s.db, { mediaDir: media, uploadsDir: path.join(tmp, 'up') });
    assert.equal(out.clips, 1);
    assert.ok(fs.existsSync(path.join(tmp, 'up', 'seed-a.mp4')));

    const feed = (await s.api('GET', '/api/home?limit=50', { user: 'dev' })).data;
    assert.ok(feed.items.length >= 5);
    const types = new Set(feed.items.map((i) => i.type));
    assert.deepEqual([...types].sort(), ['POST', 'TEXT_REPLY', 'VIDEO_REPLY']);
    // reply-to-reply exists (depth 2) and carries the root debate
    assert.ok(feed.items.some((i) => i.post.depth === 2 && i.root));
    // the only non-bot is the developer
    const people = s.db.all('SELECT username, is_bot FROM users');
    assert.deepEqual(people.filter((p) => !p.is_bot).map((p) => p.username), ['dev']);
    assert.ok(feed.items.every((i) => i.actor.isBot));

    // the developer account can really log in, with a username or its phone number
    for (const identifier of [DEV_LOGIN.username, DEV_LOGIN.phone]) {
      const login = await s.api('POST', '/api/auth/login', { json: { identifier, password: DEV_LOGIN.password } });
      assert.equal(login.status, 200, identifier);
      assert.equal(login.data.user.username, 'dev');
    }
    // sample people are bots with no password, so nobody can log in as them
    assert.equal((await s.api('POST', '/api/auth/login', { json: { identifier: 'aman_s', password: 'anything-here' } })).status, 401);

    await assert.rejects(seed(s.db), /already has users/);
  } finally { fs.rmSync(tmp, { recursive: true, force: true }); await s.close(); }
});

test('import-legacy: moves READY videos across, parents first, safe to repeat', async () => {
  const s = await startServer();
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'forest-legacy-'));
  try {
    const SQL = await initSqlJs();
    const old = new SQL.Database();
    old.run(`CREATE TABLE videos (id TEXT PRIMARY KEY, title TEXT, filename TEXT NOT NULL, status TEXT NOT NULL,
             role TEXT, parent_video_id TEXT, stance TEXT, transcript TEXT, created_at TEXT NOT NULL, user_id TEXT)`);
    const ins = (r) => old.run('INSERT INTO videos VALUES (?,?,?,?,?,?,?,?,?,?)', r);
    // child listed BEFORE its parent on purpose
    ins(['c1', 'reply', 'c1.mp4', 'READY', 'CHILD', 'p1', 'EVIDENCE', null, '2026-01-02T00:00:00Z', 'Test User']);
    ins(['p1', 'opinion', 'p1.mp4', 'READY', 'PARENT', null, 'PARENT', '{"overallSummary":"sum"}', '2026-01-01T00:00:00Z', 'test_user']);
    ins(['f1', 'broken', 'f1.mp4', 'FAILED', 'PARENT', null, 'PARENT', null, '2026-01-03T00:00:00Z', 'test_user']);
    ins(['o1', 'orphan', 'o1.mp4', 'READY', 'CHILD', 'gone', 'FOR', null, '2026-01-04T00:00:00Z', 'x']);
    const legacyFile = path.join(tmp, 'FOREST.db');
    fs.writeFileSync(legacyFile, Buffer.from(old.export()));
    const oldUploads = path.join(tmp, 'old-uploads');
    fs.mkdirSync(oldUploads);
    fs.writeFileSync(path.join(oldUploads, 'p1.mp4'), 'video');

    const out = await importLegacy(s.db, legacyFile, { uploadsFrom: oldUploads, uploadsDir: path.join(tmp, 'new-uploads') });
    assert.deepEqual(out, { imported: 3, skippedExisting: 0, skippedNotReady: 1, missingMedia: 2, orphanedReplies: 1 });
    assert.ok(fs.existsSync(path.join(tmp, 'new-uploads', 'p1.mp4')));

    const p1 = s.db.get("SELECT * FROM posts WHERE id = 'p1'");
    const c1 = s.db.get("SELECT * FROM posts WHERE id = 'c1'");
    assert.equal(p1.depth, 0);
    assert.equal(c1.parent_id, 'p1');
    assert.equal(c1.root_id, 'p1');
    assert.equal(c1.depth, 1);
    assert.equal(c1.stance, 'UNRESOLVED'); // EVIDENCE is not a stance we store
    assert.equal(s.db.get("SELECT depth FROM posts WHERE id = 'o1'").depth, 0); // orphan becomes a root
    assert.equal(s.db.get("SELECT is_bot FROM users WHERE username = 'test_user'").is_bot, 1);
    assert.equal(s.db.get("SELECT COUNT(*) AS n FROM users WHERE username = 'test_user'").n, 1); // 'Test User' → 'test_user' shared

    const again = await importLegacy(s.db, legacyFile);
    assert.equal(again.imported, 0);
    assert.equal(again.skippedExisting, 3);
    assert.equal(s.db.get('SELECT COUNT(*) AS n FROM posts').n, 3);
    assert.ok(addUser && follow);
  } finally { fs.rmSync(tmp, { recursive: true, force: true }); await s.close(); }
});
