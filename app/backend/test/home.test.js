const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { startServer, addUser, follow, addPost } = require('./helpers');

let s, me, aman, riya, kabir, outsider;
let p1, r1, r2, r3, pOutside;

before(async () => {
  s = await startServer();
  me = addUser(s.db, 'me');
  aman = addUser(s.db, 'aman_s');
  riya = addUser(s.db, 'riya_k');
  kabir = addUser(s.db, 'kabir_m');
  outsider = addUser(s.db, 'outsider');
  [aman, riya, kabir].forEach((id) => follow(s.db, me, id));

  p1 = addPost(s.db, { userId: aman, title: 'Punjabi mandatory?', minutesAgo: 180 });
  r1 = addPost(s.db, { userId: riya, parentId: p1, stance: 'AGAINST', body: 'caption', minutesAgo: 60 });
  r2 = addPost(s.db, { userId: riya, kind: 'TEXT', parentId: p1, stance: 'AGAINST', body: 'no', minutesAgo: 120 });
  r3 = addPost(s.db, { userId: kabir, parentId: r1, stance: 'FOR', minutesAgo: 20 });
  pOutside = addPost(s.db, { userId: outsider, title: 'not followed', minutesAgo: 5 });
});
after(() => s.close());

test('home needs a user', async () => {
  assert.equal((await s.api('GET', '/api/home')).status, 401);
  assert.equal((await s.api('GET', '/api/home', { user: 'nobody' })).status, 401);
});

test('someone who follows nobody gets an empty feed', async () => {
  const res = await s.api('GET', '/api/home', { user: 'outsider' });
  assert.equal(res.status, 200);
  assert.deepEqual(res.data, { items: [], nextCursor: null });
});

test('shows only followed people, newest first, with the right card type', async () => {
  const { data } = await s.api('GET', '/api/home', { user: 'me' });
  assert.deepEqual(data.items.map((i) => i.post.id), [r3, r1, r2, p1]);
  assert.deepEqual(data.items.map((i) => i.type), ['VIDEO_REPLY', 'VIDEO_REPLY', 'TEXT_REPLY', 'POST']);
  assert.ok(!data.items.some((i) => i.post.id === pOutside));
});

test('a reply carries its direct parent and, if different, the root debate', async () => {
  const { data } = await s.api('GET', '/api/home', { user: 'me' });
  const byId = Object.fromEntries(data.items.map((i) => [i.post.id, i]));

  assert.equal(byId[p1].parent, null);
  assert.equal(byId[p1].root, null);

  assert.equal(byId[r1].parent.post.id, p1);
  assert.equal(byId[r1].parent.actor.username, 'aman_s');
  assert.equal(byId[r1].root, null); // parent already is the root

  // r3 replies to r1 (a reply), inside aman's debate
  assert.equal(byId[r3].parent.post.id, r1);
  assert.equal(byId[r3].parent.actor.username, 'riya_k');
  assert.deepEqual(byId[r3].root, { id: p1, username: 'aman_s', title: 'Punjabi mandatory?' });
  assert.equal(byId[r3].post.depth, 2);
});

test('reply and stance counts include indirect replies', async () => {
  const { data } = await s.api('GET', '/api/home', { user: 'me' });
  const root = data.items.find((i) => i.post.id === p1).post;
  assert.equal(root.replyCount, 3); // r1, r2 direct + r3 indirect
  assert.equal(root.forCount, 1);
  assert.equal(root.againstCount, 2);
  const r1Post = data.items.find((i) => i.post.id === r1).post;
  assert.equal(r1Post.replyCount, 1);
});

test('a blocked author, and replies to a blocked author, disappear', async () => {
  const dev = await startServer();
  try {
    const u = addUser(dev.db, 'u'), a = addUser(dev.db, 'a'), b = addUser(dev.db, 'b');
    follow(dev.db, u, a); follow(dev.db, u, b);
    const pa = addPost(dev.db, { userId: a, title: 'a post', minutesAgo: 30 });
    const pb = addPost(dev.db, { userId: b, parentId: pa, minutesAgo: 10 });
    let res = await dev.api('GET', '/api/home', { user: 'u' });
    assert.equal(res.data.items.length, 2);

    await dev.api('POST', `/api/users/${a}/block`, { user: 'u' });
    res = await dev.api('GET', '/api/home', { user: 'u' });
    assert.deepEqual(res.data.items, []); // a's post gone, b's reply to a gone too
    assert.ok(pb);
  } finally { await dev.close(); }
});

test('the block filter itself works even if a follow row somehow survives', async () => {
  const dev = await startServer();
  try {
    const u = addUser(dev.db, 'u'), a = addUser(dev.db, 'a'), b = addUser(dev.db, 'b');
    follow(dev.db, u, a); follow(dev.db, u, b);
    const pa = addPost(dev.db, { userId: a, title: 'from a', minutesAgo: 30 });
    const pb = addPost(dev.db, { userId: b, title: 'from b', minutesAgo: 20 });
    const reply = addPost(dev.db, { userId: b, parentId: pa, minutesAgo: 10 }); // b replies to a
    // write the block straight into the table: blocking through the API would also delete the follow
    dev.db.run('INSERT INTO blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, ?)', [u, a, new Date().toISOString()]);
    const res = await dev.api('GET', '/api/home', { user: 'u' });
    assert.deepEqual(res.data.items.map((i) => i.post.id), [pb]); // a's post and b's reply to a are hidden
    assert.ok(reply);
  } finally { await dev.close(); }
});

test('unfinished and failed posts are not in the feed', async () => {
  const dev = await startServer();
  try {
    const u = addUser(dev.db, 'u'), a = addUser(dev.db, 'a');
    follow(dev.db, u, a);
    addPost(dev.db, { userId: a, status: 'PROCESSING' });
    addPost(dev.db, { userId: a, status: 'FAILED' });
    const ok = addPost(dev.db, { userId: a, status: 'READY' });
    const res = await dev.api('GET', '/api/home', { user: 'u' });
    assert.deepEqual(res.data.items.map((i) => i.post.id), [ok]);
  } finally { await dev.close(); }
});

test('cursor pagination walks the whole feed once', async () => {
  const dev = await startServer();
  try {
    const u = addUser(dev.db, 'u'), a = addUser(dev.db, 'a');
    follow(dev.db, u, a);
    const ids = [];
    for (let i = 0; i < 5; i++) ids.push(addPost(dev.db, { userId: a, minutesAgo: i })); // newest first = ids order
    const seen = [];
    let cursor = null;
    let pages = 0;
    do {
      const res = await dev.api('GET', `/api/home?limit=2${cursor ? `&cursor=${cursor}` : ''}`, { user: 'u' });
      assert.equal(res.status, 200);
      seen.push(...res.data.items.map((i) => i.post.id));
      cursor = res.data.nextCursor;
      pages++;
    } while (cursor && pages < 10);
    assert.deepEqual(seen, ids);
    assert.equal(pages, 3);
    assert.equal((await dev.api('GET', '/api/home?cursor=%%%bad', { user: 'u' })).status, 400);
  } finally { await dev.close(); }
});

test('bot accounts are flagged so the app can label them', async () => {
  const dev = await startServer();
  try {
    const u = addUser(dev.db, 'u'), bot = addUser(dev.db, 'forest_daily', { bot: true });
    follow(dev.db, u, bot);
    addPost(dev.db, { userId: bot, title: 'Daily debate' });
    const res = await dev.api('GET', '/api/home', { user: 'u' });
    assert.equal(res.data.items[0].actor.isBot, true);
  } finally { await dev.close(); }
});
