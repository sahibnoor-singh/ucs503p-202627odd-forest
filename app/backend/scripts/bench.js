// Load benchmark: builds a synthetic database, boots the real app and times
// the endpoints the Home screen hits.
//
//   node scripts/bench.js                       default size, in-memory DB
//   BENCH_FILE=1 node scripts/bench.js          also measure writes to a real DB file
//   USERS=2000 ROOTS=6000 node scripts/bench.js override sizes
//
// Fake Gemini/ffmpeg are used, so it measures the server, not the AI.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { v4: uuid } = require('uuid');
const { openDb } = require('../src/db');
const { createApp } = require('../src/app');

const { buildData, SIZES } = require('./bench_data');
const { USERS, ROOTS, LIKES } = SIZES;
const RUNS = Number(process.env.RUNS) || 40;

async function main() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'forest-bench-'));
  const dbFile = process.env.BENCH_FILE ? path.join(tmp, 'bench.db') : null;
  const db = await openDb({ file: dbFile, saveDelayMs: Number(process.env.SAVE_DELAY_MS) || 0 });
  const { users, postIds, roots, buildMs, pick } = buildData(db);

  // the benchmark user: follows many people, so a full feed page is always available
  const me = users[0];
  db.run('DELETE FROM follows WHERE follower_id = ?', [me]);
  db.tx(() => users.slice(1, 301).forEach((f) =>
    db.run('INSERT INTO follows (follower_id, followee_id, created_at) VALUES (?, ?, ?)', [me, f, new Date().toISOString()])));

  // count queries and time spent inside the database, per request
  const stats = { n: 0, ms: 0 };
  for (const name of ['all', 'get', 'run']) {
    const orig = db[name];
    db[name] = (...args) => {
      const t = process.hrtime.bigint();
      try { return orig(...args); } finally { stats.n++; stats.ms += Number(process.hrtime.bigint() - t) / 1e6; }
    };
  }

  const uploadsDir = path.join(tmp, 'uploads');
  const app = createApp({
    db, uploadsDir, allowDevUser: true, jwtSecret: 'bench-secret-bench-secret-0123456789',
    analyzer: { extractAudio: async () => {}, analyzeAudio: async () => ({}), classifyReplyText: async () => 'FOR' }
  });
  const server = await new Promise((r) => { const s = app.listen(0, '127.0.0.1', () => r(s)); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const H = { 'x-dev-user': 'user_0' };

  async function timed(label, n, fn) {
    const ms = [];
    stats.n = 0; stats.ms = 0;
    for (let i = 0; i < n; i++) {
      const s = process.hrtime.bigint();
      await fn(i);
      ms.push(Number(process.hrtime.bigint() - s) / 1e6);
    }
    ms.sort((a, b) => a - b);
    const q = (p) => ms[Math.min(ms.length - 1, Math.floor(p * ms.length))];
    return { label, n, p50: q(0.5), p95: q(0.95), max: ms[ms.length - 1], queries: stats.n / n, dbMs: stats.ms / n };
  }
  const get = async (u) => { const r = await fetch(base + u, { headers: H }); await r.json(); return r.status; };

  const rows = [];
  rows.push(await timed('GET /api/home?limit=20 (first page)', RUNS, () => get('/api/home?limit=20')));
  let cursor = null;
  rows.push(await timed('GET /api/home (walk pages via cursor)', RUNS, async () => {
    const r = await fetch(`${base}/api/home?limit=20${cursor ? `&cursor=${cursor}` : ''}`, { headers: H });
    cursor = (await r.json()).nextCursor;
  }));
  rows.push(await timed('GET /api/posts/:id (random)', RUNS, () => get(`/api/posts/${postIds[pick(postIds.length)]}`)));
  rows.push(await timed('GET /api/users/suggested', RUNS, () => get('/api/users/suggested?limit=10')));
  rows.push(await timed('GET /api/users/:id (profile)', RUNS, () => get(`/api/users/${users[1 + pick(USERS - 1)]}`)));
  rows.push(await timed('GET thread of a normal post', RUNS, () => get(`/api/posts/${roots[1 + pick(ROOTS - 1)]}/thread`)));
  rows.push(await timed('GET thread of a 500-reply debate', Math.min(RUNS, 20), () => get(`/api/posts/${roots[0]}/thread`)));
  rows.push(await timed('POST like', RUNS, (i) =>
    fetch(`${base}/api/posts/${postIds[(i * 7919) % postIds.length]}/like`, { method: 'POST', headers: H }).then((r) => r.json())));
  rows.push(await timed('POST text reply', RUNS, (i) => {
    const fd = new FormData();
    fd.append('kind', 'TEXT'); fd.append('parentId', roots[i + 2]); fd.append('body', 'benchmark reply');
    return fetch(`${base}/api/posts`, { method: 'POST', headers: H, body: fd }).then((r) => r.json());
  }));

  // many people hitting Home at once
  const conc = 20;
  const s = Date.now();
  await Promise.all(Array.from({ length: conc }, () => get('/api/home?limit=20')));
  const concurrentMs = Date.now() - s;

  const dbBytes = dbFile ? fs.statSync(dbFile).size : Buffer.from(db.raw.export()).length;
  console.log(`\nData: ${USERS} users, ${postIds.length} posts, ${LIKES} likes, ${dbFile ? 'file DB' : 'in-memory DB'}, size ${(dbBytes / 1048576).toFixed(1)} MB (built in ${(buildMs / 1000).toFixed(1)} s)`);
  console.log('| endpoint | n | p50 ms | p95 ms | max ms | queries/req | db ms/req |\n|---|---|---|---|---|---|---|');
  rows.forEach((r) => console.log(`| ${r.label} | ${r.n} | ${r.p50.toFixed(1)} | ${r.p95.toFixed(1)} | ${r.max.toFixed(1)} | ${r.queries.toFixed(0)} | ${r.dbMs.toFixed(1)} |`));
  console.log(`${conc} simultaneous GET /api/home: all done in ${concurrentMs} ms`);

  await new Promise((r) => server.close(r));
  db.close();
  fs.rmSync(tmp, { recursive: true, force: true });
}

main().catch((e) => { console.error(e); process.exit(1); });
