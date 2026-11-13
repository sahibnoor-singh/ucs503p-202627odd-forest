const fs = require('fs');
const os = require('os');
const path = require('path');
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { startServer, addUser, addPost } = require('./helpers');
const { openDb } = require('../src/db');
const { createProfiles } = require('../src/profiles');
const { TOPICS, MAX_PICK, SEED_AFFINITY, seedProfile } = require('../src/topics');
const { extractTopics } = require('../src/recommendation');

test('the topic list: unique ids, words the profile can actually match, and nothing that is only the label', () => {
  const ids = TOPICS.map((t) => t.id);
  assert.equal(new Set(ids).size, ids.length);
  assert.ok(TOPICS.length >= 12);
  for (const t of TOPICS) {
    assert.ok(t.words.length >= 6, t.id);
    for (const w of t.words) {
      // exactly what extractTopics would produce from that word, so a seeded word can match a real video
      assert.deepEqual(extractTopics({ title: w }), [w], `${t.id}: "${w}" is not a token the profile would ever see`);
    }
  }
});

test('GET /api/onboarding/topics gives ids and labels only, and how many to pick', async () => {
  const s = await startServer();
  try {
    addUser(s.db, 'riya');
    const r = await s.api('GET', '/api/onboarding/topics', { user: 'riya' });
    assert.equal(r.status, 200);
    assert.deepEqual(r.data.topics[0], { id: TOPICS[0].id, label: TOPICS[0].label });
    assert.equal(r.data.min, 3);
    assert.equal(r.data.max, MAX_PICK);
    assert.equal(r.data.topics.length, TOPICS.length);
    assert.equal((await s.api('GET', '/api/onboarding/topics')).status, 401);
  } finally { await s.close(); }
});

test('choosing topics seeds the taste profile, marks onboarding done, and /api/me says so', async () => {
  const s = await startServer();
  try {
    addUser(s.db, 'riya');
    const before = (await s.api('GET', '/api/me', { user: 'riya' })).data;
    assert.equal(before.account.onboarded, false);

    const r = await s.api('POST', '/api/me/onboarding', { user: 'riya', json: { topics: ['politics', 'tech', 'politics'] } });
    assert.equal(r.status, 200, JSON.stringify(r.data));
    assert.deepEqual(r.data.topics, ['politics', 'tech'], 'duplicates dropped');

    const me = s.db.get('SELECT id, onboarded_at FROM users WHERE username = ?', ['riya']);
    assert.ok(me.onboarded_at);
    const profile = createProfiles(s.db).getProfile(me.id);
    assert.deepEqual(profile.interests, ['politics', 'tech']);
    assert.equal(profile.topics.election, SEED_AFFINITY);
    assert.equal(profile.topics.algorithm, SEED_AFFINITY);
    assert.equal(profile.topics.cricket, undefined, 'topics not chosen are not seeded');
    assert.equal((await s.api('GET', '/api/me', { user: 'riya' })).data.account.onboarded, true);
  } finally { await s.close(); }
});

test('skipping (an empty list) marks it done and seeds nothing', async () => {
  const s = await startServer();
  try {
    addUser(s.db, 'riya');
    const r = await s.api('POST', '/api/me/onboarding', { user: 'riya', json: { topics: [] } });
    assert.equal(r.status, 200);
    assert.deepEqual(r.data.topics, []);
    const me = s.db.get('SELECT id, onboarded_at FROM users WHERE username = ?', ['riya']);
    assert.ok(me.onboarded_at);
    assert.deepEqual(createProfiles(s.db).getProfile(me.id).topics, {});
  } finally { await s.close(); }
});

test('bad input is a 400 on the topics field and changes nothing', async () => {
  const s = await startServer();
  try {
    addUser(s.db, 'riya');
    for (const topics of [undefined, 'politics', ['nonsense'], [5], Array(20).fill('politics')]) {
      const r = await s.api('POST', '/api/me/onboarding', { user: 'riya', json: { topics } });
      assert.equal(r.status, 400, JSON.stringify(topics));
      assert.equal(r.data.field, 'topics');
    }
    assert.equal(s.db.get('SELECT onboarded_at FROM users WHERE username = ?', ['riya']).onboarded_at, null);
    assert.equal((await s.api('POST', '/api/me/onboarding', { json: { topics: [] } })).status, 401);
  } finally { await s.close(); }
});

test('more than the maximum is cut to the first ones', async () => {
  const s = await startServer();
  try {
    addUser(s.db, 'riya');
    const ids = TOPICS.map((t) => t.id).slice(0, MAX_PICK + 1);
    const r = await s.api('POST', '/api/me/onboarding', { user: 'riya', json: { topics: ids } });
    assert.equal(r.status, 200);
    assert.deepEqual(r.data.topics, ids.slice(0, MAX_PICK));
  } finally { await s.close(); }
});

test('choosing again later changes the topics but keeps the first finish time and what was learned from watching', async () => {
  const s = await startServer();
  try {
    addUser(s.db, 'riya');
    await s.api('POST', '/api/me/onboarding', { user: 'riya', json: { topics: ['politics'] } });
    const me = s.db.get('SELECT id, onboarded_at FROM users WHERE username = ?', ['riya']);
    const profiles = createProfiles(s.db);
    const learned = profiles.getProfile(me.id);
    learned.topics.election = 0.95; // watching raised it above the seed
    profiles.saveProfile(learned);

    await s.api('POST', '/api/me/onboarding', { user: 'riya', json: { topics: ['politics', 'sports'] } });
    const after = profiles.getProfile(me.id);
    assert.equal(after.topics.election, 0.95, 'a seed never lowers what the person earned');
    assert.equal(after.topics.cricket, SEED_AFFINITY);
    assert.deepEqual(after.interests, ['politics', 'sports']);
    assert.equal(s.db.get('SELECT onboarded_at FROM users WHERE id = ?', [me.id]).onboarded_at, me.onboarded_at);

    await s.api('POST', '/api/me/onboarding', { user: 'riya', json: { topics: [] } });
    assert.deepEqual(profiles.getProfile(me.id).interests, ['politics', 'sports'], 'a skip later does not wipe the choice');
  } finally { await s.close(); }
});

test('seeding a profile never lowers what is already there and is safe to repeat', () => {
  const p = seedProfile({ topics: { tax: 0.9 } }, ['economy']);
  assert.equal(p.topics.tax, 0.9);
  assert.equal(p.topics.inflation, SEED_AFFINITY);
  const again = seedProfile(p, ['economy']);
  assert.equal(again.topics.inflation, SEED_AFFINITY);
});

test('an old database is upgraded: everyone who already had an account counts as done, and running it twice is harmless', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'forest-onboarding-'));
  const file = path.join(dir, 'old.db');
  try {
    const SQL = await require('sql.js')();
    const old = new SQL.Database();
    old.run(`CREATE TABLE users (id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE COLLATE NOCASE, full_name TEXT NOT NULL,
      is_bot INTEGER NOT NULL DEFAULT 0, avatar_url TEXT, bio TEXT, phone TEXT, phone_verified INTEGER NOT NULL DEFAULT 0,
      email TEXT, dob TEXT, password_hash TEXT, created_at TEXT NOT NULL)`);
    old.run("INSERT INTO users (id, username, full_name, created_at) VALUES ('u1', 'veteran', 'Old User', '2026-01-01T00:00:00Z')");
    fs.writeFileSync(file, Buffer.from(old.export()));
    old.close();

    const db = await openDb({ file });
    assert.equal(db.get("SELECT onboarded_at FROM users WHERE id = 'u1'").onboarded_at, '2026-01-01T00:00:00Z');
    db.run("INSERT INTO users (id, username, full_name, created_at) VALUES ('u2', 'newcomer', 'New', '2026-10-21T00:00:00Z')");
    db.close();
    const again = await openDb({ file });
    assert.equal(again.get("SELECT onboarded_at FROM users WHERE id = 'u2'").onboarded_at, null, 'a later start must not mark newcomers as done');
    again.close();
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});

test('after picking politics, a new person is shown the politics video before the cricket one', async () => {
  const s = await startServer();
  try {
    const author = addUser(s.db, 'author');
    addUser(s.db, 'riya');
    const cricket = addPost(s.db, { userId: author, title: 'Cricket match team selection', minutesAgo: 10 });
    const politics = addPost(s.db, { userId: author, title: 'Election reform and the vote', minutesAgo: 10 });
    await s.api('POST', '/api/me/onboarding', { user: 'riya', json: { topics: ['politics'] } });
    const { status, data } = await s.api('GET', '/api/videos/feed', { user: 'riya' });
    assert.equal(status, 200);
    assert.deepEqual(data.videos.map((v) => v.id), [politics, cricket]);
  } finally { await s.close(); }
});
