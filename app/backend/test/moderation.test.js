const { test } = require('node:test');
const assert = require('node:assert/strict');
const { startServer, addUser, addPost, follow } = require('./helpers');

const TOKEN = 'mod-token-for-tests';
const admin = (s, method, url, json) => fetch(s.base + url, {
  method, headers: { authorization: `Bearer ${TOKEN}`, 'content-type': 'application/json' }, body: json ? JSON.stringify(json) : undefined
}).then(async (r) => ({ status: r.status, data: await r.json().catch(() => null), type: r.headers.get('content-type') }));

const boot = (extra = {}) => startServer({ appOptions: { moderationToken: TOKEN, ...extra } });

test('the admin page and API do not exist without a token configured, and need it when configured', async () => {
  const off = await startServer();
  try {
    assert.equal((await off.api('GET', '/admin')).status, 404);
    assert.equal((await off.api('GET', '/api/admin/reports')).status, 404);
  } finally { await off.close(); }

  const s = await boot();
  try {
    assert.equal((await fetch(`${s.base}/api/admin/reports`)).status, 401);
    assert.equal((await fetch(`${s.base}/api/admin/reports`, { headers: { authorization: 'Bearer wrong' } })).status, 401);
    assert.equal((await admin(s, 'GET', '/api/admin/reports')).status, 200);
    const page = await fetch(`${s.base}/admin`);
    assert.equal(page.status, 200);
    assert.match(page.headers.get('content-security-policy'), /default-src 'none'/);
    assert.ok(!(await page.text()).includes(TOKEN));
  } finally { await s.close(); }
});

test('guessing the moderation token is throttled', async () => {
  const s = await boot();
  try {
    for (let i = 0; i < 10; i++) {
      assert.equal((await fetch(`${s.base}/api/admin/log`, { headers: { authorization: `Bearer guess${i}` } })).status, 401);
    }
    assert.equal((await fetch(`${s.base}/api/admin/log`, { headers: { authorization: 'Bearer guess11' } })).status, 429);
    assert.equal((await admin(s, 'GET', '/api/admin/log')).status, 429, 'even the right token waits out the window');
  } finally { await s.close(); }
});

test('report -> admin sees it -> hide removes the post everywhere -> restore brings it back; all logged', async () => {
  const s = await boot();
  try {
    const author = addUser(s.db, 'author');
    const fan = addUser(s.db, 'fan');
    follow(s.db, fan, author);
    const post = addPost(s.db, { userId: author, title: 'Spicy opinion' });
    addUser(s.db, 'reporter');

    await s.api('POST', `/api/posts/${post}/report`, { user: 'reporter', json: { reason: 'harassment' } });
    const list = await admin(s, 'GET', '/api/admin/reports');
    assert.equal(list.data.reports.length, 1);
    assert.equal(list.data.reports[0].author, 'author');
    assert.deepEqual(list.data.reports[0].reasons, { HARASSMENT: 1 });
    assert.equal(list.data.reports[0].openCount, 1);

    const homeBefore = await s.api('GET', '/api/home', { user: 'fan' });
    assert.equal(homeBefore.data.items.length, 1);
    assert.equal((await admin(s, 'POST', `/api/admin/posts/${post}/hide`, { reason: 'HARASSMENT', note: 'clear case' })).status, 200);
    assert.equal((await s.api('GET', '/api/home', { user: 'fan' })).data.items.length, 0);
    assert.equal((await s.api('GET', '/api/videos/feed')).data.videos.length, 0);
    assert.equal((await s.api('GET', `/api/posts/${post}`, { user: 'fan' })).status, 404);
    assert.equal((await admin(s, 'GET', '/api/admin/reports')).data.reports[0].openCount, 0); // reports closed as actioned
    assert.equal((await admin(s, 'POST', `/api/admin/posts/${post}/hide`)).status, 409); // already hidden

    assert.equal((await admin(s, 'POST', `/api/admin/posts/${post}/restore`)).status, 200);
    assert.equal((await s.api('GET', '/api/home', { user: 'fan' })).data.items.length, 1);
    assert.equal((await admin(s, 'POST', `/api/admin/posts/${post}/restore`)).status, 409);

    const log = (await admin(s, 'GET', '/api/admin/log')).data.log;
    assert.deepEqual(log.map((e) => e.action), ['RESTORE', 'HIDE']);
    assert.equal(log[1].note, 'clear case');
    assert.equal(log[1].actor, 'admin');
  } finally { await s.close(); }
});

test('dismissing reports keeps the post up and records why nothing was done', async () => {
  const s = await boot();
  try {
    const author = addUser(s.db, 'author');
    const post = addPost(s.db, { userId: author, title: 'Fine opinion' });
    addUser(s.db, 'r1');
    await s.api('POST', `/api/posts/${post}/report`, { user: 'r1', json: { reason: 'SPAM' } });
    assert.equal((await admin(s, 'POST', `/api/admin/posts/${post}/dismiss`, { note: 'not spam' })).data.dismissed, 1);
    assert.equal((await s.api('GET', '/api/videos/feed')).data.videos.length, 1);
    assert.equal(s.db.get('SELECT status FROM reports').status, 'DISMISSED');
    assert.equal((await admin(s, 'GET', '/api/admin/log')).data.log[0].action, 'DISMISS');
  } finally { await s.close(); }
});

test('copyright is a report reason in both APIs, and unknown hide reasons are refused', async () => {
  const s = await boot();
  try {
    const author = addUser(s.db, 'author');
    const post = addPost(s.db, { userId: author, title: 'Uses a song' });
    addUser(s.db, 'owner');
    assert.equal((await s.api('POST', `/api/posts/${post}/report`, { user: 'owner', json: { reason: 'COPYRIGHT' } })).status, 201);
    addUser(s.db, 'owner2');
    await s.api('POST', `/api/videos/${post}/report`, { user: 'owner2', json: { reason: 'copyright' } });
    assert.deepEqual(s.db.all('SELECT reason FROM reports ORDER BY reason').map((r) => r.reason), ['COPYRIGHT', 'COPYRIGHT']);
    assert.equal((await admin(s, 'POST', `/api/admin/posts/${post}/hide`, { reason: 'BECAUSE' })).status, 400);
  } finally { await s.close(); }
});

test('repeat infringer: the third upheld copyright takedown suspends the account; a restore removes a strike', async () => {
  const s = await boot();
  try {
    const author = addUser(s.db, 'infringer');
    const posts = [1, 2, 3].map((i) => addPost(s.db, { userId: author, title: `clip ${i}` }));
    await admin(s, 'POST', `/api/admin/posts/${posts[0]}/hide`, { reason: 'COPYRIGHT' });
    await admin(s, 'POST', `/api/admin/posts/${posts[1]}/hide`, { reason: 'COPYRIGHT' });
    assert.equal(s.db.get('SELECT suspended_at FROM users WHERE id = ?', [author]).suspended_at, null);

    await admin(s, 'POST', `/api/admin/posts/${posts[1]}/restore`); // a strike overturned
    await admin(s, 'POST', `/api/admin/posts/${posts[2]}/hide`, { reason: 'COPYRIGHT' });
    assert.equal(s.db.get('SELECT suspended_at FROM users WHERE id = ?', [author]).suspended_at, null, 'only 2 strikes stand');

    await admin(s, 'POST', `/api/admin/posts/${posts[1]}/hide`, { reason: 'COPYRIGHT' });
    assert.ok(s.db.get('SELECT suspended_at FROM users WHERE id = ?', [author]).suspended_at, 'third standing strike');

    // other reasons never count
    const other = addUser(s.db, 'other');
    for (let i = 0; i < 4; i++) await admin(s, 'POST', `/api/admin/posts/${addPost(s.db, { userId: other, title: 'x' })}/hide`, { reason: 'SPAM' });
    assert.equal(s.db.get('SELECT suspended_at FROM users WHERE id = ?', [other]).suspended_at, null);
  } finally { await s.close(); }
});

test('a suspended account cannot use the app or log in (403, not 401), and can be reinstated', async () => {
  const s = await boot();
  try {
    const u = addUser(s.db, 'suspended_one');
    s.db.run('UPDATE users SET suspended_at = ?, password_hash = ? WHERE id = ?', ['t', 'x', u]);
    const res = await s.api('GET', '/api/me', { user: 'suspended_one' });
    assert.equal(res.status, 403);
    assert.match(res.data.error, /suspended/);
    // a real login token of a suspended account is refused too
    const { createTokens } = require('../src/auth/tokens');
    const { TEST_SECRET } = require('./helpers');
    const token = createTokens(TEST_SECRET).signAccess(u);
    const withToken = await fetch(`${s.base}/api/me`, { headers: { authorization: `Bearer ${token}` } });
    assert.equal(withToken.status, 403);
    assert.equal((await admin(s, 'POST', `/api/admin/users/${u}/unsuspend`)).status, 200);
    assert.equal((await s.api('GET', '/api/me', { user: 'suspended_one' })).status, 200);
    assert.equal((await fetch(`${s.base}/api/me`, { headers: { authorization: `Bearer ${token}` } })).status, 200);
    assert.equal((await admin(s, 'POST', `/api/admin/users/${u}/unsuspend`)).status, 409);
    assert.deepEqual((await admin(s, 'GET', '/api/admin/log')).data.log.map((e) => e.action), ['UNSUSPEND']);
  } finally { await s.close(); }
});

test('suspension also blocks login with the right password', async () => {
  const { hashPassword } = require('../src/auth/password');
  const s = await boot();
  try {
    const u = addUser(s.db, 'locked');
    s.db.run('UPDATE users SET password_hash = ?, suspended_at = ? WHERE id = ?', [await hashPassword('a decent passphrase'), 't', u]);
    const res = await s.api('POST', '/api/auth/login', { json: { identifier: 'locked', password: 'a decent passphrase' } });
    assert.equal(res.status, 403);
  } finally { await s.close(); }
});

test('automatic first pass: a configured word in a transcript or a text reply hides the post and logs it', async () => {
  const s = await boot({ moderationBlocklist: ['badword'] });
  try {
    const author = addUser(s.db, 'author');
    const root = addPost(s.db, { userId: author, title: 'Root' });
    addUser(s.db, 'poster');

    // text reply
    const clean = await s.api('POST', '/api/posts', { user: 'poster', form: formOf({ kind: 'TEXT', parentId: root, body: 'A calm argument' }) });
    const dirty = await s.api('POST', '/api/posts', { user: 'poster', form: formOf({ kind: 'TEXT', parentId: root, body: 'this is BADWORD stuff' }) });
    assert.equal(s.db.get('SELECT status FROM posts WHERE id = ?', [clean.data.post.id]).status, 'READY');
    assert.equal(s.db.get('SELECT status FROM posts WHERE id = ?', [dirty.data.post.id]).status, 'HIDDEN');
    assert.equal((await s.api('GET', `/api/posts/${root}/thread`)).data.replies.length, 1);

    // video whose transcript matches
    const vs = await startServer({
      appOptions: { moderationToken: TOKEN, moderationBlocklist: ['badword'] },
      analyzer: { analyzeAudio: async () => ({ transcript: 'he said a Badword out loud', detectedStance: 'FOR', overallSummary: 's', claims: [] }) }
    });
    try {
      addUser(vs.db, 'v');
      const { videoForm } = require('./helpers');
      const created = await vs.api('POST', '/api/posts', { user: 'v', form: videoForm({ kind: 'VIDEO', title: 'clip' }) });
      await vs.idle();
      assert.equal(vs.db.get('SELECT status FROM posts WHERE id = ?', [created.data.post.id]).status, 'HIDDEN');
      const log = (await admin(vs, 'GET', '/api/admin/log')).data.log;
      assert.equal(log[0].actor, 'auto');
      assert.match(log[0].note, /badword/);
      assert.equal((await admin(vs, 'POST', `/api/admin/posts/${created.data.post.id}/restore`)).status, 200); // a person can overrule it
    } finally { await vs.close(); }
  } finally { await s.close(); }
});

test('the word list is whole-word, case-insensitive, and empty by default (nothing is hidden)', async () => {
  const { createModeration } = require('../src/moderation');
  const none = createModeration({ db: null });
  assert.equal(none.screenText('anything at all'), null);
  const m = createModeration({ db: null, blocklist: [' Cat ', 'a.b', ''] });
  assert.equal(m.screenText('the CAT sat'), 'cat');
  assert.equal(m.screenText('concatenate'), null, 'not inside another word');
  assert.equal(m.screenText('axb'), null, 'regex characters are literal');
  assert.equal(m.screenText('a.b here'), 'a.b');
});

test('complaints: anyone can send one, the officer can answer it, and the contact is published', async () => {
  const s = await boot({ grievanceOfficer: { name: 'Asha Verma', email: 'grievance@example.com' } });
  try {
    assert.deepEqual((await s.api('GET', '/api/legal/contact')).data, { grievanceOfficer: { name: 'Asha Verma', email: 'grievance@example.com' } });
    assert.equal((await s.api('POST', '/api/complaints', { json: { message: 'short' } })).status, 400);
    assert.equal((await s.api('POST', '/api/complaints', { json: { message: 'x'.repeat(2001) } })).status, 400);
    assert.equal((await s.api('POST', '/api/complaints', { json: { message: 'That post is about me and untrue', postId: 'nope' } })).status, 404);

    const author = addUser(s.db, 'author');
    const post = addPost(s.db, { userId: author, title: 'About someone' });
    addUser(s.db, 'complainer');
    const ok = await s.api('POST', '/api/complaints', { user: 'complainer', json: { message: 'Please look at this post, it is about me', contact: 'me@example.com', postId: post } });
    assert.equal(ok.status, 201);
    const anon = await s.api('POST', '/api/complaints', { json: { message: 'Signed out but I have a real problem' } });
    assert.equal(anon.status, 201);

    const list = (await admin(s, 'GET', '/api/admin/complaints')).data.complaints;
    assert.equal(list.length, 2);
    assert.equal(list.find((c) => c.id === ok.data.id).postId, post);
    assert.equal((await admin(s, 'POST', `/api/admin/complaints/${ok.data.id}/resolve`, { reply: '' })).status, 400);
    assert.equal((await admin(s, 'POST', `/api/admin/complaints/${ok.data.id}/resolve`, { reply: 'We reviewed it and removed it because...' })).status, 200);
    assert.equal((await admin(s, 'POST', `/api/admin/complaints/${ok.data.id}/resolve`, { reply: 'again' })).status, 404);
    assert.equal((await admin(s, 'GET', '/api/admin/complaints')).data.complaints.find((c) => c.id === ok.data.id).status, 'RESOLVED');
  } finally { await s.close(); }
});

test('until a grievance officer is chosen the contact endpoint says so', async () => {
  const s = await startServer();
  try {
    assert.deepEqual((await s.api('GET', '/api/legal/contact')).data, { grievanceOfficer: null });
  } finally { await s.close(); }
});

function formOf(fields) {
  const fd = new FormData();
  for (const [k, v] of Object.entries(fields)) fd.append(k, v);
  return fd;
}
