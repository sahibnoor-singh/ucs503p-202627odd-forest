const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { startServer, addUser, addPost, videoForm, jsonForm } = require('./helpers');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const gate = () => { let release; const p = new Promise((r) => { release = r; }); return { p, release }; };
const FAKE_ANALYSIS = { transcript: 't', detectedStance: 'FOR', overallSummary: 's', claims: [] };

// ---------- uploads ----------

test('an .html file labelled as video/mp4 is rejected, and so is an .mp4 labelled text/html', async () => {
  const s = await startServer();
  try {
    addUser(s.db, 'u');
    const before = fs.readdirSync(s.uploadsDir).length;
    let res = await s.api('POST', '/api/posts', {
      user: 'u', form: videoForm({ kind: 'VIDEO', title: 't' }, { name: 'evil.html', type: 'video/mp4' })
    });
    assert.equal(res.status, 400);
    res = await s.api('POST', '/api/posts', {
      user: 'u', form: videoForm({ kind: 'VIDEO', title: 't' }, { name: 'ok.mp4', type: 'text/html' })
    });
    assert.equal(res.status, 400);
    res = await s.api('POST', '/api/posts', {
      user: 'u', form: videoForm({ kind: 'VIDEO', title: 't' }, { name: 'sneaky.mp4.exe', type: 'video/mp4' })
    });
    assert.equal(res.status, 400);
    assert.equal(fs.readdirSync(s.uploadsDir).length, before, 'nothing was stored');
  } finally { await s.close(); }
});

test('accepted uploads get a safe lowercase extension and are served as media that can never run as a page', async () => {
  const s = await startServer();
  try {
    addUser(s.db, 'u');
    // octet-stream is what some phones send; an upper-case extension must not slip past the check
    const res = await s.api('POST', '/api/posts', {
      user: 'u', form: videoForm({ kind: 'VIDEO', title: 't' }, { name: 'My Clip (1).MP4', type: 'application/octet-stream' })
    });
    assert.equal(res.status, 201);
    const url = res.data.post.mediaUrl;
    assert.match(url, /^\/uploads\/\d+-[0-9a-f]{8}-My_Clip__1_\.mp4$/);
    await s.idle();

    const file = await fetch(s.base + url);
    assert.equal(file.status, 200);
    assert.match(file.headers.get('content-type'), /^video\/mp4/);
    assert.equal(file.headers.get('x-content-type-options'), 'nosniff');
    assert.match(file.headers.get('content-security-policy'), /sandbox/);
    assert.match(file.headers.get('cache-control'), /immutable/);
  } finally { await s.close(); }
});

test('API responses are not cacheable and carry basic security headers; unknown paths get JSON', async () => {
  const s = await startServer();
  try {
    const res = await fetch(`${s.base}/api/health`);
    assert.equal(res.headers.get('cache-control'), 'no-store');
    assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
    assert.equal(res.headers.get('x-frame-options'), 'DENY');
    assert.equal(res.headers.get('x-powered-by'), null);
    const nope = await fetch(`${s.base}/something/else`);
    assert.equal(nope.status, 404);
    assert.deepEqual(await nope.json(), { error: 'Not found' });
    assert.equal((await fetch(`${s.base}/uploads/../server.js`)).status, 404);
  } finally { await s.close(); }
});

// ---------- rate limits ----------

test('rate limit: over the limit gets 429 + Retry-After, per person, and recovers after the window', async () => {
  const s = await startServer({ appOptions: { rateLimit: { like: { max: 3, windowMs: 250 } } } });
  try {
    addUser(s.db, 'a'); addUser(s.db, 'b');
    const p = addPost(s.db, { userId: addUser(s.db, 'author'), title: 't' });
    const like = (user) => s.api('POST', `/api/posts/${p}/like`, { user });
    for (let i = 0; i < 3; i++) assert.equal((await like('a')).status, 200);
    const blocked = await fetch(`${s.base}/api/posts/${p}/like`, { method: 'POST', headers: { 'x-dev-user': 'a' } });
    assert.equal(blocked.status, 429);
    assert.ok(Number(blocked.headers.get('retry-after')) >= 1);
    assert.match((await blocked.json()).error, /Too many requests/);
    assert.equal((await like('b')).status, 200, "another person is not affected by a's limit");
    await sleep(300);
    assert.equal((await like('a')).status, 200, 'the window reset');
  } finally { await s.close(); }
});

test('rate limit: anonymous callers are limited per IP, and limits are off unless enabled', async () => {
  const limited = await startServer({ appOptions: { rateLimit: { api: { max: 4, windowMs: 5000 } } } });
  const open = await startServer();
  try {
    const codes = [];
    for (let i = 0; i < 6; i++) codes.push((await limited.api('GET', '/api/videos/all')).status);
    assert.deepEqual(codes, [200, 200, 200, 200, 429, 429]);
    for (let i = 0; i < 50; i++) assert.equal((await open.api('GET', '/api/videos/all')).status, 200);
    // health checks are never throttled, even when limits are on
    for (let i = 0; i < 8; i++) assert.equal((await limited.api('GET', '/api/health')).status, 200);
  } finally { await limited.close(); await open.close(); }
});

test('rate limit: new posts are limited more tightly than reads', async () => {
  const s = await startServer({ appOptions: { rateLimit: { post: { max: 2, windowMs: 5000 } } } });
  try {
    addUser(s.db, 'u');
    const p = addPost(s.db, { userId: addUser(s.db, 'a'), title: 't' });
    const reply = () => s.api('POST', '/api/posts', { user: 'u', form: jsonForm({ kind: 'TEXT', parentId: p, body: 'hi' }) });
    assert.equal((await reply()).status, 201);
    assert.equal((await reply()).status, 201);
    assert.equal((await reply()).status, 429);
    assert.equal((await s.api('GET', `/api/posts/${p}`, { user: 'u' })).status, 200);
  } finally { await s.close(); }
});

// ---------- queue protection ----------

test('one person cannot queue more than 5 unfinished videos', async () => {
  const g = gate();
  const s = await startServer({ analyzer: { analyzeAudio: async () => { await g.p; return FAKE_ANALYSIS; } } });
  try {
    addUser(s.db, 'u'); addUser(s.db, 'v');
    const send = (user) => s.api('POST', '/api/posts', { user, form: videoForm({ kind: 'VIDEO', title: 't' }) });
    for (let i = 0; i < 5; i++) assert.equal((await send('u')).status, 201);
    const sixth = await send('u');
    assert.equal(sixth.status, 429);
    assert.match(sixth.data.error, /being processed/);
    assert.equal((await send('v')).status, 201, 'a different person is not blocked');
    g.release();
    await s.idle();
    assert.equal((await send('u')).status, 201, 'room again once they finish');
  } finally { g.release(); await s.close(); }
});

test('a hung analysis step times out, marks that video FAILED, and the queue keeps moving', async () => {
  let calls = 0;
  const s = await startServer({
    appOptions: { jobTimeoutMs: 100 },
    analyzer: { analyzeAudio: async () => { calls++; return calls === 1 ? new Promise(() => {}) : FAKE_ANALYSIS; } }
  });
  try {
    addUser(s.db, 'u');
    const send = () => s.api('POST', '/api/posts', { user: 'u', form: videoForm({ kind: 'VIDEO', title: 't' }) });
    const stuck = (await send()).data.post.id;
    const next = (await send()).data.post.id;
    await s.idle();
    const status = (id) => s.db.get('SELECT status FROM posts WHERE id = ?', [id]).status;
    assert.equal(status(stuck), 'FAILED');
    assert.equal(status(next), 'READY');
    assert.equal(fs.readdirSync(require('os').tmpdir()).filter((f) => f.startsWith(`forest-${stuck}`)).length, 0);
  } finally { await s.close(); }
});

test('retry: the author can re-run a failed video; nobody else can; other states are refused', async () => {
  let fail = true;
  const s = await startServer({ analyzer: { analyzeAudio: async () => { if (fail) throw new Error('boom'); return FAKE_ANALYSIS; } } });
  try {
    addUser(s.db, 'u'); addUser(s.db, 'other');
    const id = (await s.api('POST', '/api/posts', { user: 'u', form: videoForm({ kind: 'VIDEO', title: 't' }) })).data.post.id;
    await s.idle();
    assert.equal(s.db.get('SELECT status FROM posts WHERE id = ?', [id]).status, 'FAILED');

    assert.equal((await s.api('POST', `/api/posts/${id}/retry`)).status, 401);
    assert.equal((await s.api('POST', `/api/posts/${id}/retry`, { user: 'other' })).status, 404);

    fail = false;
    const res = await s.api('POST', `/api/posts/${id}/retry`, { user: 'u' });
    assert.equal(res.status, 200);
    assert.equal(res.data.post.status, 'PROCESSING');
    await s.idle();
    assert.equal((await s.api('GET', `/api/posts/${id}`, { user: 'u' })).data.post.status, 'READY');

    assert.equal((await s.api('POST', `/api/posts/${id}/retry`, { user: 'u' })).status, 409); // not failed any more

    // the file vanished: tell the user to upload again instead of looping forever
    s.db.run("UPDATE posts SET status = 'FAILED' WHERE id = ?", [id]);
    fs.rmSync(path.join(s.uploadsDir, s.db.get('SELECT media_filename FROM posts WHERE id = ?', [id]).media_filename));
    assert.equal((await s.api('POST', `/api/posts/${id}/retry`, { user: 'u' })).status, 410);
  } finally { await s.close(); }
});

// ---------- production switches ----------

test('legacy unauthenticated upload and public video list can be switched off, and then store/show nothing', async () => {
  const s = await startServer({ appOptions: { allowLegacyUpload: false } });
  try {
    const before = fs.readdirSync(s.uploadsDir).length;
    const res = await s.api('POST', '/api/videos/upload', { form: videoForm({ role: 'PARENT' }) });
    assert.equal(res.status, 404);
    assert.equal(fs.readdirSync(s.uploadsDir).length, before);
    assert.equal((await s.api('GET', '/api/videos/all')).status, 404); // the public list (with transcripts) goes too
  } finally { await s.close(); }
});

test('CORS: open in dev, an allow-list when given, and none at all when disabled', async () => {
  const ask = async (appOptions) => {
    const s = await startServer({ appOptions });
    try {
      const res = await fetch(`${s.base}/api/health`, { headers: { origin: 'https://evil.example' } });
      return res.headers.get('access-control-allow-origin');
    } finally { await s.close(); }
  };
  assert.equal(await ask({ corsOrigins: '*' }), '*');
  assert.equal(await ask({ corsOrigins: ['https://forest.example'] }), null); // evil.example is not on the list
  assert.equal(await ask({ corsOrigins: false }), null);
});

test('the legacy video list is capped to the newest N, still oldest-first', async () => {
  const s = await startServer({ appOptions: { legacyListLimit: 3 } });
  try {
    const u = addUser(s.db, 'u');
    const ids = [5, 4, 3, 2, 1].map((m) => addPost(s.db, { userId: u, title: `t${m}`, minutesAgo: m * 10 }));
    const { data } = await s.api('GET', '/api/videos/all');
    assert.equal(data.length, 3);
    assert.deepEqual(data.map((v) => v.id), [ids[2], ids[3], ids[4]]); // the 3 newest, oldest of them first
  } finally { await s.close(); }
});

test('access log: one line per request with the path but never the query string, the body or a token', async () => {
  const lines = [];
  const s = await startServer({ appOptions: { accessLog: (l) => lines.push(l) } });
  try {
    addUser(s.db, 'aman');
    await s.api('GET', '/api/search?q=secret%20words', { user: 'aman' });
    await s.api('POST', '/api/auth/login', { json: { identifier: 'aman', password: 'hunter2 hunter2' } });
    assert.ok(lines.length >= 2);
    assert.match(lines[0], /^\d{4}-\d\d-\d\dT.* GET \/api\/search 200 \d+ms user=[0-9a-f]{8}$/);
    const all = lines.join('\n');
    assert.ok(!/secret|hunter2|Bearer|q=/.test(all), 'no query, no body, no credentials in the log');
  } finally { await s.close(); }
});
