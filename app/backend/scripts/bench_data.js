// Synthetic data for the benchmark and profiling scripts (deterministic).
const { v4: uuid } = require('uuid');

const SIZES = {
  USERS: Number(process.env.USERS) || 2000,
  ROOTS: Number(process.env.ROOTS) || 6000,
  REPLIES_PER_ROOT: Number(process.env.REPLIES_PER_ROOT) || 4,
  LIKES: Number(process.env.LIKES) || 120000,
  FOLLOWS_PER_USER: Number(process.env.FOLLOWS_PER_USER) || 60
};

function rng(seed) { // deterministic, so runs are comparable
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Fills [db] and returns { users, postIds, roots, buildMs }. */
function buildData(db) {
  const { USERS, ROOTS, REPLIES_PER_ROOT, LIKES, FOLLOWS_PER_USER } = SIZES;
  const rand = rng(42);
  const pick = (n) => Math.floor(rand() * n);

  // ---- build data (inside one transaction, so a file DB is written once) ----
  const t0 = Date.now();
  const users = [];
  const postIds = [];
  const roots = [];
  db.tx(() => {
    const now = Date.now();
    for (let i = 0; i < USERS; i++) {
      const id = uuid();
      users.push(id);
      db.run('INSERT INTO users (id, username, full_name, is_bot, created_at) VALUES (?, ?, ?, 1, ?)',
        [id, `user_${i}`, `User ${i}`, new Date(now - 9e9).toISOString()]);
    }
    for (const u of users) {
      const seen = new Set();
      for (let k = 0; k < FOLLOWS_PER_USER; k++) {
        const f = users[pick(USERS)];
        if (f === u || seen.has(f)) continue;
        seen.add(f);
        db.run('INSERT INTO follows (follower_id, followee_id, created_at) VALUES (?, ?, ?)', [u, f, new Date().toISOString()]);
      }
    }
    let clock = now - ROOTS * (1 + REPLIES_PER_ROOT) * 1000;
    const insertPost = (id, user, kind, parent, rootId, depth, stance) => {
      clock += 1000;
      db.run(
        `INSERT INTO posts (id, user_id, kind, parent_id, root_id, depth, title, body, media_filename, stance, status, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'READY', ?)`,
        [id, user, kind, parent, rootId, depth, depth ? null : `Opinion ${id.slice(0, 6)}`,
          kind === 'TEXT' ? 'a short text reply with some words in it' : null,
          kind === 'VIDEO' ? 'x.mp4' : null, stance, new Date(clock).toISOString()]
      );
      postIds.push(id);
    };
    const stances = ['FOR', 'AGAINST', 'UNRESOLVED'];
    for (let r = 0; r < ROOTS; r++) {
      const rid = uuid();
      roots.push(rid);
      insertPost(rid, users[pick(USERS)], 'VIDEO', null, rid, 0, 'PARENT');
      const inThread = [{ id: rid, depth: 0 }];
      for (let k = 0; k < REPLIES_PER_ROOT; k++) {
        const parent = inThread[pick(inThread.length)];
        if (parent.depth >= 5) continue;
        const id = uuid();
        insertPost(id, users[pick(USERS)], rand() < 0.5 ? 'VIDEO' : 'TEXT', parent.id, rid, parent.depth + 1, stances[pick(3)]);
        inThread.push({ id, depth: parent.depth + 1 });
      }
    }
    // one deliberately huge debate to stress the thread view
    const big = roots[0];
    const bigThread = [{ id: big, depth: 0 }];
    for (let k = 0; k < 500; k++) {
      const parent = bigThread[pick(bigThread.length)];
      if (parent.depth >= 6) continue;
      const id = uuid();
      insertPost(id, users[pick(USERS)], 'TEXT', parent.id, big, parent.depth + 1, stances[pick(3)]);
      bigThread.push({ id, depth: parent.depth + 1 });
    }
    for (let l = 0; l < LIKES; l++) {
      db.run('INSERT OR IGNORE INTO likes (user_id, post_id, created_at) VALUES (?, ?, ?)',
        [users[pick(USERS)], postIds[pick(postIds.length)], new Date().toISOString()]);
    }
  });

  const buildMs = Date.now() - t0;
  return { users, postIds, roots, buildMs, rand, pick };
}

module.exports = { buildData, SIZES, rng };
