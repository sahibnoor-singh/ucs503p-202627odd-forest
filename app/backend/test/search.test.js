const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { startServer, addUser, addPost, follow } = require('./helpers');
const { openDb } = require('../src/db');

const ids = (list) => list.map((v) => v.id);
const names = (list) => list.map((a) => a.user.username);
const search = (s, user, q, extra = '') => s.api('GET', `/api/search?q=${encodeURIComponent(q)}${extra}`, { user });

async function world(opts) {
  const s = await startServer(opts);
  const me = addUser(s.db, 'me_user');
  const aman = addUser(s.db, 'aman');
  const riya = addUser(s.db, 'riya');
  return { s, me, aman, riya };
}

test('search needs a sign-in, a known type and a sane cursor', async () => {
  const { s } = await world();
  try {
    assert.equal((await s.api('GET', '/api/search?q=phones')).status, 401);
    assert.equal((await search(s, 'me_user', 'phones', '&type=everything')).status, 400);
    assert.equal((await search(s, 'me_user', 'phones', '&type=posts&cursor=garbage')).status, 400);
    assert.equal((await search(s, 'me_user', 'phones', '&type=posts&cursor=' + Buffer.from('o:99999').toString('base64url'))).status, 400);
  } finally { await s.close(); }
});

test('a query that is empty, one letter, or made only of spaces finds nothing', async () => {
  const { s, aman } = await world();
  try {
    addPost(s.db, { userId: aman, title: 'Ban phones in class' });
    for (const q of ['', ' ', 'p', '   a  ']) {
      const r = await search(s, 'me_user', q);
      assert.equal(r.status, 200);
      assert.deepEqual([r.data.accounts, r.data.posts], [[], []], JSON.stringify(q));
    }
  } finally { await s.close(); }
});

test('posts: found by title, caption, what was said, or the summary; every word must match; case does not matter', async () => {
  const { s, aman } = await world();
  try {
    const a = addPost(s.db, { userId: aman, title: 'Ban phones in lecture halls' });
    const b = addPost(s.db, { userId: aman, title: 'Something else', body: 'about Regional Languages', analysis: { transcript: 'we speak of metro prices', overallSummary: 'A talk about rent' } });
    const r1 = await search(s, 'me_user', 'PHONES', '&type=posts');
    assert.deepEqual(ids(r1.data.posts), [a]);
    assert.deepEqual(ids((await search(s, 'me_user', 'regional languages', '&type=posts')).data.posts), [b], 'caption');
    assert.deepEqual(ids((await search(s, 'me_user', 'metro', '&type=posts')).data.posts), [b], 'transcript');
    assert.deepEqual(ids((await search(s, 'me_user', 'rent', '&type=posts')).data.posts), [b], 'summary');
    assert.deepEqual(ids((await search(s, 'me_user', 'metro phones', '&type=posts')).data.posts), [], 'both words must match the same post');
    assert.deepEqual(ids((await search(s, 'me_user', 'transcript', '&type=posts')).data.posts), [], 'the names of JSON fields are not text');
  } finally { await s.close(); }
});

test('posts: only finished videos with a file; replies count, text replies and unfinished or hidden posts do not', async () => {
  const { s, aman } = await world();
  try {
    const root = addPost(s.db, { userId: aman, title: 'Phones opinion' });
    const reply = addPost(s.db, { userId: aman, parentId: root, body: 'phones are fine', stance: 'FOR' });
    addPost(s.db, { userId: aman, parentId: root, kind: 'TEXT', body: 'phones in text only' });
    addPost(s.db, { userId: aman, title: 'phones processing', status: 'PROCESSING' });
    addPost(s.db, { userId: aman, title: 'phones failed', status: 'FAILED' });
    addPost(s.db, { userId: aman, title: 'phones hidden by a moderator', status: 'HIDDEN' });
    const r = await search(s, 'me_user', 'phones', '&type=posts');
    assert.deepEqual(ids(r.data.posts).sort(), [root, reply].sort());
    const v = r.data.posts.find((x) => x.id === reply);
    assert.equal(v.parentVideoId, root, 'a reply says which debate it belongs to');
    assert.ok(!JSON.stringify(r.data).match(/pips/i));
  } finally { await s.close(); }
});

test('posts: a word at the start of a title ranks above one buried in what was said; credibility, not popularity, breaks ties', async () => {
  const { s, aman, riya } = await world();
  try {
    const buried = addPost(s.db, { userId: aman, title: 'Campus life', analysis: { transcript: 'nothing about lunch here except lunch', claims: [] }, minutesAgo: 1 });
    const front = addPost(s.db, { userId: aman, title: 'Lunch for everyone', minutesAgo: 600 });
    assert.deepEqual(ids((await search(s, 'me_user', 'lunch', '&type=posts')).data.posts), [front, buried]);

    // same match, same age: the better fact-checked one first, even if the other has more likes
    const solid = addPost(s.db, { userId: aman, title: 'Parking fees', analysis: { transcript: 'x', claims: [{ credibilityScore: 90 }] }, minutesAgo: 100 });
    const shaky = addPost(s.db, { userId: riya, title: 'Parking fees', analysis: { transcript: 'x', claims: [{ credibilityScore: 10 }] }, minutesAgo: 100 });
    for (const name of ['aman', 'riya', 'me_user']) s.db.run('INSERT INTO likes (user_id, post_id, created_at) VALUES (?, ?, ?)', [s.db.get('SELECT id FROM users WHERE username = ?', [name]).id, shaky, new Date().toISOString()]);
    assert.deepEqual(ids((await search(s, 'me_user', 'parking', '&type=posts')).data.posts), [solid, shaky]);
  } finally { await s.close(); }
});

test('% and _ in a query are just characters, not wildcards', async () => {
  const { s, aman } = await world();
  try {
    addPost(s.db, { userId: aman, title: 'Ban phones' });
    const pct = addPost(s.db, { userId: aman, title: 'GDP grew 5% last year' });
    assert.deepEqual((await search(s, 'me_user', '%%', '&type=posts')).data.posts, []);
    assert.deepEqual((await search(s, 'me_user', '__', '&type=posts')).data.posts, []);
    assert.deepEqual(ids((await search(s, 'me_user', '5%', '&type=posts')).data.posts), [pct]);
    assert.equal((await search(s, 'me_user', "'; DROP TABLE posts; --")).status, 200);
    assert.ok(s.db.get('SELECT COUNT(*) n FROM posts').n >= 2);
  } finally { await s.close(); }
});

test('nothing by someone you blocked, someone who blocked you, a suspended or a deleted person', async () => {
  const { s, me, aman, riya } = await world();
  try {
    const kabir = addUser(s.db, 'kabir');
    const dead = addUser(s.db, 'ghost');
    const susp = addUser(s.db, 'sus');
    const ok = addPost(s.db, { userId: aman, title: 'tea opinion' });
    addPost(s.db, { userId: riya, title: 'tea blocked by me' });
    addPost(s.db, { userId: kabir, title: 'tea who blocked me' });
    addPost(s.db, { userId: dead, title: 'tea from a deleted account' });
    addPost(s.db, { userId: susp, title: 'tea from a suspended account' });
    s.db.run('INSERT INTO blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, ?)', [me, riya, 'x']);
    s.db.run('INSERT INTO blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, ?)', [kabir, me, 'x']);
    s.db.run("UPDATE users SET deleted_at = 'x' WHERE id = ?", [dead]);
    s.db.run("UPDATE users SET suspended_at = 'x' WHERE id = ?", [susp]);
    assert.deepEqual(ids((await search(s, 'me_user', 'tea', '&type=posts')).data.posts), [ok]);
    for (const hidden of ['riya', 'kabir', 'ghost', 'sus']) {
      assert.deepEqual((await search(s, 'me_user', hidden, '&type=accounts')).data.accounts, [], `${hidden} is not offered`);
    }
  } finally { await s.close(); }
});

test('deleting an account removes its words from search', async () => {
  const s = await startServer();
  try {
    const aman = addUser(s.db, 'aman');
    addPost(s.db, { userId: aman, title: 'private opinion about zebras', analysis: { transcript: 'zebra talk' } });
    addUser(s.db, 'me_user');
    assert.equal((await search(s, 'me_user', 'zebras')).data.posts.length, 1);
    // what DELETE /api/me does to the words (routes/users.js): the database empties search_text by itself
    s.db.run("UPDATE posts SET title = NULL, analysis = NULL, body = NULL WHERE user_id = ?", [aman]);
    assert.equal(s.db.get('SELECT TRIM(search_text) AS t FROM posts').t, '');
    assert.equal((await search(s, 'me_user', 'zebras')).data.posts.length, 0);
  } finally { await s.close(); }
});

test('accounts: matched on username, name or bio; exact and prefix first; people you follow before strangers; no private fields', async () => {
  const { s, me, aman, riya } = await world();
  try {
    const sam = addUser(s.db, 'sam');
    const samir = addUser(s.db, 'samir');
    const other = addUser(s.db, 'zed');
    s.db.run("UPDATE users SET full_name = 'Samira Khan', bio = 'loves chess', phone = '+919999999999', email = 'x@y.z' WHERE id = ?", [other]);
    s.db.run("UPDATE users SET bio = 'sam is my friend' WHERE id = ?", [aman]);
    const bot = addUser(s.db, 'sam_bot', { bot: true });
    follow(s.db, me, samir);

    const r = await search(s, 'me_user', 'sam', '&type=accounts');
    assert.equal(names(r.data.accounts)[0], 'sam', 'exact username first');
    assert.ok(names(r.data.accounts).indexOf('samir') < names(r.data.accounts).indexOf('sam_bot'), 'the one you follow before the stranger');
    assert.ok(names(r.data.accounts).includes('zed'), 'found by full name');
    assert.ok(names(r.data.accounts).includes('aman'), 'found by bio');
    assert.equal((await search(s, 'me_user', 'chess', '&type=accounts')).data.accounts[0].user.username, 'zed');
    const flat = JSON.stringify(r.data);
    assert.ok(!flat.includes('9999999999') && !flat.includes('x@y.z'), 'no phone or email');
    const botRow = r.data.accounts.find((a) => a.user.username === 'sam_bot');
    assert.equal(botRow.user.isBot, true, 'bots are always marked');
    assert.equal(r.data.accounts.find((a) => a.user.username === 'samir').followedByMe, true);
    assert.ok(sam && bot && riya);

    const own = await search(s, 'me_user', 'me_user', '&type=accounts');
    assert.equal(own.data.accounts[0].isMe, true);
  } finally { await s.close(); }
});

test('all: a few accounts and the best posts together, with no cursor; accounts and posts pages never repeat', async () => {
  const { s, aman } = await world();
  try {
    for (let i = 0; i < 8; i++) addUser(s.db, `chai_fan_${i}`);
    for (let i = 0; i < 5; i++) addPost(s.db, { userId: aman, title: `chai opinion ${i}`, minutesAgo: i });
    const all = await search(s, 'me_user', 'chai');
    assert.equal(all.data.accounts.length, 5, 'only the best five accounts in the mixed view');
    assert.equal(all.data.posts.length, 5);
    assert.equal(all.data.nextCursor, null);

    const first = await search(s, 'me_user', 'chai', '&type=posts&limit=2');
    assert.equal(first.data.posts.length, 2);
    assert.ok(first.data.nextCursor);
    const second = await search(s, 'me_user', 'chai', `&type=posts&limit=2&cursor=${first.data.nextCursor}`);
    const third = await search(s, 'me_user', 'chai', `&type=posts&limit=2&cursor=${second.data.nextCursor}`);
    const seen = [...ids(first.data.posts), ...ids(second.data.posts), ...ids(third.data.posts)];
    assert.equal(new Set(seen).size, 5, 'five different posts over three pages');
    assert.equal(third.data.nextCursor, null);

    const people = await search(s, 'me_user', 'chai_fan', '&type=accounts&limit=3');
    const more = await search(s, 'me_user', 'chai_fan', `&type=accounts&limit=3&cursor=${people.data.nextCursor}`);
    assert.equal(new Set([...names(people.data.accounts), ...names(more.data.accounts)]).size, 6);
  } finally { await s.close(); }
});

test('a query containing a word on the moderation blocklist finds nothing at all', async () => {
  const { s, aman } = await world({ appOptions: { moderationBlocklist: ['badword'] } });
  try {
    addPost(s.db, { userId: aman, title: 'a badword opinion about tea' });
    addUser(s.db, 'badword_fan');
    const r = await search(s, 'me_user', 'badword');
    assert.deepEqual([r.data.accounts, r.data.posts], [[], []]);
    assert.equal((await search(s, 'me_user', 'tea')).data.posts.length, 1, 'other searches are untouched');
  } finally { await s.close(); }
});

test('search is rate limited like other reads', async () => {
  const { s } = await world({ appOptions: { rateLimit: { search: { max: 3, windowMs: 60000 } } } });
  try {
    for (let i = 0; i < 3; i++) assert.equal((await search(s, 'me_user', 'tea')).status, 200);
    assert.equal((await search(s, 'me_user', 'tea')).status, 429);
  } finally { await s.close(); }
});

test('an older database file gets the search column and its words filled in when it is opened', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'forest-search-'));
  const file = path.join(dir, 'old.db');
  try {
    const db1 = await openDb({ file });
    db1.run("INSERT INTO users (id, username, full_name, created_at) VALUES ('u', 'aman', 'Aman', 'x')");
    db1.run(`INSERT INTO posts (id, user_id, kind, root_id, title, media_filename, status, analysis, created_at)
             VALUES ('p', 'u', 'VIDEO', 'p', 'Old Post', 'x.mp4', 'READY', '{"transcript":"From Before"}', 'x')`);
    db1.run('DROP TRIGGER posts_search_insert');
    db1.run('DROP TRIGGER posts_search_update');
    db1.run('ALTER TABLE posts DROP COLUMN search_text'); // what a database made before search looks like
    db1.close();
    const db2 = await openDb({ file });
    assert.equal(db2.get("SELECT search_text FROM posts WHERE id = 'p'").search_text, 'old post  from before ');
    db2.close();
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});
