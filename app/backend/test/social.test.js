const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { startServer, addUser, follow, addPost } = require('./helpers');

let s, me, a, b, post;
before(async () => {
  s = await startServer();
  me = addUser(s.db, 'me'); a = addUser(s.db, 'a'); b = addUser(s.db, 'b');
  post = addPost(s.db, { userId: a, title: 'hello' });
});
after(() => s.close());

test('like and unlike are idempotent and counts are right', async () => {
  assert.equal((await s.api('POST', `/api/posts/${post}/like`)).status, 401);

  let res = await s.api('POST', `/api/posts/${post}/like`, { user: 'me' });
  assert.deepEqual(res.data, { liked: true, likeCount: 1 });
  res = await s.api('POST', `/api/posts/${post}/like`, { user: 'me' }); // again: still 1
  assert.deepEqual(res.data, { liked: true, likeCount: 1 });
  res = await s.api('POST', `/api/posts/${post}/like`, { user: 'b' });
  assert.equal(res.data.likeCount, 2);

  const mine = (await s.api('GET', `/api/posts/${post}`, { user: 'me' })).data.post;
  assert.equal(mine.likedByMe, true);
  assert.equal(mine.likeCount, 2);
  const anon = (await s.api('GET', `/api/posts/${post}`)).data.post;
  assert.equal(anon.likedByMe, false);

  res = await s.api('DELETE', `/api/posts/${post}/like`, { user: 'me' });
  assert.deepEqual(res.data, { liked: false, likeCount: 1 });
  res = await s.api('DELETE', `/api/posts/${post}/like`, { user: 'me' }); // again: no error
  assert.deepEqual(res.data, { liked: false, likeCount: 1 });

  assert.equal((await s.api('POST', '/api/posts/missing/like', { user: 'me' })).status, 404);
});

test('cannot like a post that is not finished', async () => {
  const busy = addPost(s.db, { userId: a, status: 'PROCESSING' });
  assert.equal((await s.api('POST', `/api/posts/${busy}/like`, { user: 'me' })).status, 404);
});

test('follow / unfollow, and what you cannot do', async () => {
  let res = await s.api('POST', `/api/users/${b}/follow`, { user: 'me' });
  assert.deepEqual(res.data, { following: true });
  await s.api('POST', `/api/users/${b}/follow`, { user: 'me' }); // idempotent
  assert.equal(s.db.get('SELECT COUNT(*) AS n FROM follows WHERE follower_id = ?', [me]).n, 1);

  const info = (await s.api('GET', '/api/me', { user: 'me' })).data;
  assert.equal(info.user.username, 'me');
  assert.equal(info.followingCount, 1);
  assert.equal((await s.api('GET', '/api/me', { user: 'b' })).data.followerCount, 1);

  res = await s.api('DELETE', `/api/users/${b}/follow`, { user: 'me' });
  assert.deepEqual(res.data, { following: false });

  assert.equal((await s.api('POST', `/api/users/${me}/follow`, { user: 'me' })).status, 400); // self
  assert.equal((await s.api('POST', '/api/users/nobody/follow', { user: 'me' })).status, 404);
  assert.equal((await s.api('POST', `/api/users/${b}/follow`)).status, 401);
});

test('block removes follows both ways, stops new ones, and can be undone', async () => {
  const x = addUser(s.db, 'x'), y = addUser(s.db, 'y');
  follow(s.db, x, y); follow(s.db, y, x);

  assert.deepEqual((await s.api('POST', `/api/users/${y}/block`, { user: 'x' })).data, { blocked: true });
  assert.equal(s.db.get('SELECT COUNT(*) AS n FROM follows WHERE follower_id IN (?, ?)', [x, y]).n, 0);

  assert.equal((await s.api('POST', `/api/users/${y}/follow`, { user: 'x' })).status, 403); // I blocked them
  assert.equal((await s.api('POST', `/api/users/${x}/follow`, { user: 'y' })).status, 403); // they can't follow me

  assert.deepEqual((await s.api('DELETE', `/api/users/${y}/block`, { user: 'x' })).data, { blocked: false });
  assert.equal((await s.api('POST', `/api/users/${y}/follow`, { user: 'x' })).status, 200);
});

test('report: valid reasons only, one per person, not your own post', async () => {
  const p = addPost(s.db, { userId: b, title: 'reportable' });
  assert.equal((await s.api('POST', `/api/posts/${p}/report`, { json: { reason: 'SPAM' } })).status, 401);
  assert.equal((await s.api('POST', `/api/posts/${p}/report`, { user: 'me', json: {} })).status, 400);
  assert.equal((await s.api('POST', `/api/posts/${p}/report`, { user: 'me', json: { reason: 'because' } })).status, 400);
  assert.equal((await s.api('POST', `/api/posts/${p}/report`, { user: 'b', json: { reason: 'SPAM' } })).status, 400);
  assert.equal((await s.api('POST', '/api/posts/missing/report', { user: 'me', json: { reason: 'SPAM' } })).status, 404);

  const ok = await s.api('POST', `/api/posts/${p}/report`, { user: 'me', json: { reason: 'misinformation' } });
  assert.equal(ok.status, 201);
  await s.api('POST', `/api/posts/${p}/report`, { user: 'me', json: { reason: 'SPAM' } }); // duplicate ignored
  const rows = s.db.all('SELECT reason FROM reports WHERE post_id = ?', [p]);
  assert.deepEqual(rows, [{ reason: 'MISINFORMATION' }]);
  // nothing is removed automatically
  assert.equal((await s.api('GET', `/api/posts/${p}`)).status, 200);
});

test('the dev-user header only works when enabled', async () => {
  const prod = await startServer();
  try {
    // rebuild the same app with the header disabled
    const { createApp } = require('../src/app');
    const app = createApp({ db: prod.db, uploadsDir: prod.uploadsDir, allowDevUser: false, jwtSecret: 'another-test-secret-0123456789',
      analyzer: { extractAudio: async () => {}, analyzeAudio: async () => ({}), classifyReplyText: async () => 'FOR' } });
    const server = await new Promise((r) => { const sv = app.listen(0, '127.0.0.1', () => r(sv)); });
    addUser(prod.db, 'u');
    const base = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${base}/api/home`, { headers: { 'x-dev-user': 'u' } });
    assert.equal(res.status, 401);
    assert.equal((await fetch(`${base}/api/dev/users`)).status, 404);
    assert.equal((await fetch(`${base}/api/health`)).status, 200);
    await new Promise((r) => server.close(r));
  } finally { await prod.close(); }
});

test('bad JSON and unknown API paths give JSON errors, not crashes', async () => {
  const res = await fetch(`${s.base}/api/posts/x/report`, {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-dev-user': 'me' }, body: '{oops'
  });
  assert.equal(res.status, 400);
  assert.ok((await res.json()).error);
  assert.equal((await s.api('GET', '/api/nope')).status, 404);
  assert.equal((await s.api('GET', '/api/health')).data.ok, true);
});
