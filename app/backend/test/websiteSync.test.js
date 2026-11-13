const { test } = require('node:test');
const assert = require('node:assert/strict');
const { openDb } = require('../src/db');
const { buildSnapshot, createWebsiteSync } = require('../src/websiteSync');
const { addUser, addPost } = require('./helpers');

async function seeded() {
  const db = await openDb();
  const u = addUser(db, 'private_name');
  db.run("UPDATE users SET phone = '+919999912345', email = 'secret@example.com', dob = '1999-01-01', password_hash = 'HASH' WHERE id = ?", [u]);
  const bot = addUser(db, 'a_bot', { bot: true });
  const root = addPost(db, { userId: u, title: 'My private opinion title', analysis: { transcript: 'SECRET WORDS' } });
  const reply = addPost(db, { userId: bot, parentId: root, stance: 'AGAINST' });
  addPost(db, { userId: u, kind: 'TEXT', parentId: reply, body: 'secret text body', stance: 'FOR' });
  addPost(db, { userId: u, status: 'PROCESSING' });
  return { db, root, reply };
}

test('snapshot: counts, structure, nothing personal, titles only when asked', async () => {
  const { db, root, reply } = await seeded();
  const snap = buildSnapshot(db);
  assert.equal(snap.stats.users, 1);
  assert.equal(snap.stats.bots, 1);
  assert.equal(snap.stats.opinions, 1);
  assert.equal(snap.stats.videoReplies, 1);
  assert.equal(snap.stats.textReplies, 1);
  assert.equal(snap.stats.processing, 1);
  assert.equal(snap.nodes.length, 3); // READY only
  assert.equal(snap.edges.length, 2);
  const json = JSON.stringify(snap);
  for (const secret of ['private_name', 'a_bot', '+9199999', 'secret@example.com', '1999-01-01', 'HASH', 'SECRET WORDS',
    'secret text body', 'My private opinion title', root, reply, 'x.mp4']) {
    assert.ok(!json.includes(secret), `leaked: ${secret}`);
  }
  assert.ok(snap.nodes.some((n) => n.isBot));
  assert.ok(JSON.stringify(buildSnapshot(db, { includeTitles: true })).includes('My private opinion title'));
  db.close();
});

test('push: sends with the bearer token, skips when nothing changed, resends after a change', async () => {
  const { db, root } = await seeded();
  const sent = [];
  const fetchImpl = async (url, init) => { sent.push({ url, init }); return { ok: true, status: 200 }; };
  const sync = createWebsiteSync({ db, url: 'http://site/api/app-sync', token: 'tok', fetchImpl });
  assert.deepEqual((await sync.pushOnce()).pushed, true);
  assert.equal(sent[0].init.headers.authorization, 'Bearer tok');
  assert.equal(sent[0].url, 'http://site/api/app-sync');
  assert.equal((await sync.pushOnce()).skipped, 'unchanged');
  assert.equal(sent.length, 1);
  addPost(db, { userId: db.get('SELECT id FROM users LIMIT 1').id, parentId: root, stance: 'FOR' });
  assert.equal((await sync.pushOnce()).pushed, true);
  assert.equal(sent.length, 2);
  db.close();
});

test('push: a down or unhappy website is logged once and retried, never thrown', async () => {
  const { db } = await seeded();
  let mode = 'down';
  const warnings = [];
  const fetchImpl = async () => {
    if (mode === 'down') throw new Error('ECONNREFUSED');
    return { ok: mode === 'ok', status: 503 };
  };
  const sync = createWebsiteSync({ db, url: 'u', token: 't', fetchImpl, log: { warn: (m) => warnings.push(m), log() {} } });
  assert.ok((await sync.pushOnce()).error);
  assert.ok((await sync.pushOnce()).error);
  assert.equal(warnings.length, 1); // same problem, one log line
  mode = 'ok';
  assert.equal((await sync.pushOnce()).pushed, true); // failure did not mark it as sent
  db.close();
});
