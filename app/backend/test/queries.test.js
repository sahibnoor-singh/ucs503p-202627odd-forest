const { test } = require('node:test');
const assert = require('node:assert/strict');
const { v4: uuid } = require('uuid');
const { openDb } = require('../src/db');
const { threadCounts, threadCountsBatch, toItems, toItem } = require('../src/queries');
const { addUser, addPost } = require('./helpers');

function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

test('batched thread counts equal the one-post-at-a-time reference on random trees', async () => {
  const db = await openDb();
  const rand = rng(7);
  const users = Array.from({ length: 8 }, (_, i) => addUser(db, `u${i}`));
  const stances = ['FOR', 'AGAINST', 'UNRESOLVED'];
  const nodes = [];
  for (let r = 0; r < 25; r++) {
    const rootId = addPost(db, { userId: users[0], title: `root ${r}`, minutesAgo: 1000 - r });
    nodes.push(rootId);
    const thread = [rootId];
    for (let k = 0; k < 14; k++) {
      // replies can only hang under READY posts (that is a server rule), but a reply may itself be PROCESSING/FAILED
      const readyParents = thread.filter((id) => db.get('SELECT status FROM posts WHERE id = ?', [id]).status === 'READY');
      const parent = readyParents[Math.floor(rand() * readyParents.length)];
      const status = rand() < 0.15 ? 'PROCESSING' : rand() < 0.1 ? 'FAILED' : 'READY';
      const id = addPost(db, {
        userId: users[1 + Math.floor(rand() * 7)], kind: rand() < 0.5 ? 'TEXT' : 'VIDEO', parentId: parent,
        body: 'x', stance: stances[Math.floor(rand() * 3)], status, minutesAgo: 500 - k
      });
      thread.push(id);
      nodes.push(id);
    }
  }
  const rows = db.all('SELECT * FROM posts');
  assert.ok(rows.length >= 300);
  const batch = threadCountsBatch(db, rows);
  for (const row of rows) {
    assert.deepEqual(batch.get(row.id), threadCounts(db, row.id), `counts differ for post ${row.id} (depth ${row.depth})`);
  }
  db.close();
});

test('toItems for a whole page gives the same cards as one at a time, in a fixed number of queries', async () => {
  const db = await openDb();
  const a = addUser(db, 'a'), b = addUser(db, 'b'), me = addUser(db, 'me');
  const root = addPost(db, { userId: a, title: 'root', minutesAgo: 90 });
  const r1 = addPost(db, { userId: b, parentId: root, stance: 'AGAINST', minutesAgo: 80 });
  const r2 = addPost(db, { userId: a, kind: 'TEXT', parentId: r1, body: 'deep', stance: 'FOR', minutesAgo: 70 });
  addPost(db, { userId: b, kind: 'TEXT', parentId: r2, body: 'deeper', minutesAgo: 60 });
  db.run('INSERT INTO likes (user_id, post_id, created_at) VALUES (?, ?, ?)', [me, r1, new Date().toISOString()]);
  const rows = db.all('SELECT * FROM posts ORDER BY created_at DESC');

  let queries = 0;
  const counted = { ...db, all: (...args) => { queries++; return db.all(...args); }, get: (...args) => { queries++; return db.get(...args); } };
  const together = toItems(counted, rows, me);
  const queriesForPage = queries;
  const oneByOne = rows.map((row) => toItem(db, row, me));
  assert.deepEqual(together, oneByOne);

  // a bigger page must not cost more queries
  queries = 0;
  toItems(counted, rows.slice(0, 1), me);
  assert.ok(queriesForPage <= queries + 4, `page of ${rows.length} used ${queriesForPage} queries vs ${queries} for one row`);
  assert.ok(queriesForPage <= 12, `expected a small fixed number of queries, got ${queriesForPage}`);
  assert.equal(together.find((i) => i.post.id === r1).post.likedByMe, true);
  assert.equal(uuid().length, 36);
  db.close();
});
