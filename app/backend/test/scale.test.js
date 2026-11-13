// Guards against the mistakes that only hurt once there are many users:
//  * an endpoint that runs more SQL queries the more rows it returns (the "N+1" trap),
//  * an endpoint that gets slow as the tables grow.
// The thresholds are generous on purpose (slow CI machines); a regression is a change in SHAPE, not a few ms.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { startServer, addUser, addPost } = require('./helpers');

/** How many SQL statements `fn` causes. */
async function countQueries(db, fn) {
  let n = 0;
  const wrap = (name) => {
    const orig = db[name];
    db[name] = (...args) => { n++; return orig(...args); };
    return () => { db[name] = orig; };
  };
  const undo = ['all', 'get', 'run'].map(wrap);
  try { await fn(); } finally { undo.forEach((u) => u()); }
  return n;
}

function seedDebate(s, { roots, repliesPerRoot = 0 }) {
  const authors = Array.from({ length: 10 }, (_, i) => addUser(s.db, `author${Date.now() % 1e6}_${i}_${Math.random().toString(36).slice(2, 6)}`));
  const rootIds = [];
  s.db.tx(() => {
    for (let r = 0; r < roots; r++) {
      const root = addPost(s.db, { userId: authors[r % 10], title: `Opinion number ${r} about topic${r % 7}`, minutesAgo: r + 1 });
      rootIds.push(root);
      for (let k = 0; k < repliesPerRoot; k++) {
        addPost(s.db, { userId: authors[(r + k + 1) % 10], parentId: root, stance: k % 2 ? 'FOR' : 'AGAINST', minutesAgo: r + 1 });
      }
    }
  });
  return rootIds;
}

test('Discover feed: the number of queries does not grow with the number of videos', async () => {
  const s = await startServer();
  try {
    addUser(s.db, 'viewer');
    seedDebate(s, { roots: 5 });
    const few = await countQueries(s.db, () => s.api('GET', '/api/videos/feed?limit=30', { user: 'viewer' }));
    seedDebate(s, { roots: 300 });
    const many = await countQueries(s.db, () => s.api('GET', '/api/videos/feed?limit=30', { user: 'viewer' }));
    assert.equal(many, few, `feed ran ${few} queries for 5 videos but ${many} for 305`);
    assert.ok(many <= 15, `feed uses ${many} queries; something is being loaded one row at a time`);
  } finally { await s.close(); }
});

test('Discover replies and tree: queries stay flat as a debate gets bigger', async () => {
  const s = await startServer();
  try {
    addUser(s.db, 'viewer');
    const [small] = seedDebate(s, { roots: 1, repliesPerRoot: 3 });
    const [big] = seedDebate(s, { roots: 1, repliesPerRoot: 90 });
    for (const path of ['replies', 'strongest-reply?side=FOR', 'tree']) {
      const a = await countQueries(s.db, () => s.api('GET', `/api/videos/${small}/${path}`, { user: 'viewer' }));
      const b = await countQueries(s.db, () => s.api('GET', `/api/videos/${big}/${path}`, { user: 'viewer' }));
      assert.equal(b, a, `${path}: ${a} queries for 3 replies, ${b} for 90`);
    }
  } finally { await s.close(); }
});

test('Home feed and thread: queries do not grow with page size or thread size', async () => {
  const s = await startServer();
  try {
    const me = addUser(s.db, 'viewer_home');
    const roots = seedDebate(s, { roots: 3, repliesPerRoot: 2 });
    const authors = s.db.all("SELECT id FROM users WHERE username != 'viewer_home'").map((u) => u.id);
    authors.forEach((id) => s.db.run('INSERT INTO follows (follower_id, followee_id, created_at) VALUES (?, ?, ?)', [me, id, 't']));
    const small = await countQueries(s.db, () => s.api('GET', '/api/home?limit=50', { user: 'viewer_home' }));
    seedDebate(s, { roots: 40, repliesPerRoot: 3 });
    s.db.all("SELECT id FROM users WHERE id != ?", [me]).forEach((u) =>
      s.db.run('INSERT OR IGNORE INTO follows (follower_id, followee_id, created_at) VALUES (?, ?, ?)', [me, u.id, 't']));
    const big = await countQueries(s.db, () => s.api('GET', '/api/home?limit=50', { user: 'viewer_home' }));
    assert.equal(big, small, `Home ran ${small} queries for a small page but ${big} for a big one`);

    const bigRoot = seedDebate(s, { roots: 1, repliesPerRoot: 80 })[0];
    const threadSmall = await countQueries(s.db, () => s.api('GET', `/api/posts/${roots[0]}/thread`, { user: 'viewer_home' }));
    const threadBig = await countQueries(s.db, () => s.api('GET', `/api/posts/${bigRoot}/thread`, { user: 'viewer_home' }));
    assert.equal(threadBig, threadSmall, 'thread queries must not depend on the number of replies');
  } finally { await s.close(); }
});

test('with a few thousand posts the main read endpoints still answer quickly', async () => {
  const s = await startServer();
  try {
    addUser(s.db, 'viewer');
    seedDebate(s, { roots: 400, repliesPerRoot: 6 }); // 2800 posts
    const timed = async (url) => {
      const t0 = process.hrtime.bigint();
      const res = await s.api('GET', url, { user: 'viewer' });
      assert.equal(res.status, 200, url);
      return Number(process.hrtime.bigint() - t0) / 1e6;
    };
    for (const url of ['/api/videos/feed?limit=10', '/api/videos/feed?limit=30']) {
      const ms = await timed(url);
      assert.ok(ms < 800, `${url} took ${Math.round(ms)} ms with 2800 posts`);
    }
  } finally { await s.close(); }
});

test('the website snapshot stays bounded however big the database gets', async () => {
  const s = await startServer();
  try {
    seedDebate(s, { roots: 1700, repliesPerRoot: 0 });
    const { buildSnapshot } = require('../src/websiteSync');
    const snap = buildSnapshot(s.db);
    assert.ok(snap.nodes.length <= 1500);
    assert.ok(JSON.stringify(snap).length < 600 * 1024, 'it must fit the website\'s 1 MB request limit with room to spare');
  } finally { await s.close(); }
});
