const { test } = require('node:test');
const assert = require('node:assert/strict');
const { startServer, addUser, addPost } = require('./helpers');
const rec = require('../src/recommendation');

const ids = (list) => list.map((v) => v.id);

async function world() {
  const s = await startServer();
  const aman = addUser(s.db, 'aman');
  const riya = addUser(s.db, 'riya');
  const me = addUser(s.db, 'me_user');
  const root1 = addPost(s.db, { userId: aman, title: 'Ban phones in lecture halls', minutesAgo: 30 });
  const root2 = addPost(s.db, { userId: riya, title: 'Regional language until class 12', minutesAgo: 20 });
  return { s, aman, riya, me, root1, root2 };
}

test('feed: only READY video opinions, shaped like the reels screens expect', async () => {
  const { s, aman, root1, root2 } = await world();
  try {
    addPost(s.db, { userId: aman, title: 'still processing', status: 'PROCESSING' });
    addPost(s.db, { userId: aman, title: 'failed', status: 'FAILED' });
    addPost(s.db, { userId: aman, kind: 'TEXT', body: 'text posts are not reels' });
    addPost(s.db, { userId: aman, parentId: root1, stance: 'FOR' }); // replies are not feed items

    const { status, data } = await s.api('GET', '/api/videos/feed'); // anonymous may browse
    assert.equal(status, 200);
    assert.deepEqual(ids(data.videos).sort(), [root1, root2].sort());
    const v = data.videos.find((x) => x.id === root1);
    assert.equal(v.userName, 'aman');
    assert.equal(v.role, 'PARENT');
    assert.equal(v.status, 'ready');
    assert.equal(v.filename, 'x.mp4');
    assert.equal(v.replyCount, 1);
    assert.equal(v.forCount, 1);
    assert.equal(v.liked, false);
    assert.equal(v.viewerSide, null);
    assert.equal(data.nextCursor, null);
    assert.ok(!JSON.stringify(data).match(/pips/i), 'ranking internals must not be sent to clients');
  } finally { await s.close(); }
});

test('feed: pages never repeat a video, bad cursor is a 400', async () => {
  const { s, aman } = await world();
  try {
    for (let i = 0; i < 7; i++) addPost(s.db, { userId: aman, title: `t${i}`, minutesAgo: i });
    const seen = [];
    let cursor = '';
    for (let page = 0; page < 10; page++) {
      const { data } = await s.api('GET', `/api/videos/feed?limit=3${cursor}`);
      seen.push(...ids(data.videos));
      if (!data.nextCursor) break;
      cursor = `&cursor=${data.nextCursor}`;
    }
    assert.equal(seen.length, 9); // 7 + the 2 from world()
    assert.equal(new Set(seen).size, 9);
    assert.equal((await s.api('GET', '/api/videos/feed?cursor=nonsense')).status, 400);
  } finally { await s.close(); }
});

test('feed hides people you blocked, and people who blocked you', async () => {
  const { s, aman, riya, me, root1, root2 } = await world();
  try {
    s.db.run('INSERT INTO blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, ?)', [me, aman, 'x']);
    s.db.run('INSERT INTO blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, ?)', [riya, me, 'x']);
    const { data } = await s.api('GET', '/api/videos/feed', { user: 'me_user' });
    assert.deepEqual(ids(data.videos), []);
    const other = await s.api('GET', '/api/videos/feed'); // anonymous still sees both
    assert.deepEqual(ids(other.data.videos).sort(), [root1, root2].sort());
  } finally { await s.close(); }
});

test('ranking: topics you finish watching move up, per user, and the watched video sinks', async () => {
  const s = await startServer();
  try {
    const a = addUser(s.db, 'creator_a');
    const b = addUser(s.db, 'creator_b');
    const c = addUser(s.db, 'creator_c');
    addUser(s.db, 'fan');
    addUser(s.db, 'other_fan');
    const watched = addPost(s.db, { userId: a, title: 'climate policy', minutesAgo: 700 });
    const sameTopic = addPost(s.db, { userId: c, title: 'climate subsidies', minutesAgo: 600 });
    const other = addPost(s.db, { userId: b, title: 'cricket selection', minutesAgo: 590 }); // newer
    let feed = await s.api('GET', '/api/videos/feed', { user: 'fan' });
    assert.equal(feed.data.videos[0].id, other);

    for (let i = 0; i < 6; i++) {
      const r = await s.api('POST', `/api/videos/${watched}/interactions`, {
        user: 'fan', json: { completed: true, saved: true } // no watch time: only the profile learns
      });
      assert.equal(r.status, 200);
    }
    feed = await s.api('GET', '/api/videos/feed', { user: 'fan' });
    assert.deepEqual(ids(feed.data.videos), [sameTopic, other, watched]);

    const control = await s.api('GET', '/api/videos/feed', { user: 'other_fan' });
    assert.equal(control.data.videos[0].id, other); // someone else is unaffected

    const profile = await s.api('GET', '/api/videos/profile', { user: 'fan' });
    assert.ok(profile.data.topics.climate > 0.9);
    await s.api('POST', '/api/videos/profile/reset', { user: 'fan' });
    feed = await s.api('GET', '/api/videos/feed', { user: 'fan' });
    assert.equal(feed.data.videos[0].id, other); // forgotten
  } finally { await s.close(); }
});

test('replies: direct video replies only, side filter, strongest first', async () => {
  const { s, aman, riya, root1 } = await world();
  try {
    const weak = addPost(s.db, { userId: aman, parentId: root1, stance: 'FOR', title: 'meh', minutesAgo: 10 });
    const strong = addPost(s.db, {
      userId: riya, parentId: root1, stance: 'FOR', title: 'ban phones lecture halls evidence', minutesAgo: 9,
      analysis: { claims: [{ claim: 'x', credibilityScore: 95 }] }
    });
    const against = addPost(s.db, { userId: riya, parentId: root1, stance: 'AGAINST', minutesAgo: 8 });
    addPost(s.db, { userId: riya, parentId: root1, kind: 'TEXT', body: 'text', stance: 'FOR' });
    addPost(s.db, { userId: riya, parentId: weak, stance: 'FOR' }); // reply-to-reply: not direct
    addPost(s.db, { userId: riya, parentId: root1, stance: 'FOR', status: 'PROCESSING' });

    let r = await s.api('GET', `/api/videos/${root1}/replies`);
    assert.deepEqual(ids(r.data).sort(), [weak, strong, against].sort());
    r = await s.api('GET', `/api/videos/${root1}/replies?side=for`);
    assert.deepEqual(ids(r.data)[0], strong);
    assert.equal(r.data.length, 2);
    assert.equal((await s.api('GET', `/api/videos/${root1}/replies?side=maybe`)).status, 400);

    const sr = await s.api('GET', `/api/videos/${root1}/strongest-reply?side=AGAINST`);
    assert.equal(sr.data.reply.id, against);
    const none = await s.api('GET', `/api/videos/${strong}/strongest-reply?side=FOR`);
    assert.equal(none.data.reply, null);
    assert.equal((await s.api('GET', '/api/videos/nope/replies')).status, 404);
  } finally { await s.close(); }
});

test('tree: the whole video debate from any node, text replies left out', async () => {
  const { s, aman, riya, root1 } = await world();
  try {
    const c1 = addPost(s.db, { userId: aman, parentId: root1, stance: 'FOR' });
    const c2 = addPost(s.db, { userId: riya, parentId: root1, stance: 'AGAINST' });
    const g1 = addPost(s.db, { userId: aman, parentId: c2, stance: 'FOR' });
    addPost(s.db, { userId: aman, parentId: c1, kind: 'TEXT', body: 'no', stance: 'FOR' });
    addPost(s.db, { userId: aman, parentId: c1, status: 'FAILED' });

    const fromRoot = await s.api('GET', `/api/videos/${root1}/tree`);
    const fromLeaf = await s.api('GET', `/api/videos/${g1}/tree`);
    assert.equal(fromRoot.data[0].id, root1);
    assert.deepEqual(ids(fromRoot.data).sort(), [root1, c1, c2, g1].sort());
    assert.deepEqual(ids(fromLeaf.data), ids(fromRoot.data));
  } finally { await s.close(); }
});

test('opinion: set, switch, undo; answers with the best reply from that side', async () => {
  const { s, aman, root1 } = await world();
  try {
    const against = addPost(s.db, { userId: aman, parentId: root1, stance: 'AGAINST' });
    let r = await s.api('PUT', `/api/videos/${root1}/opinion`, { user: 'me_user', json: { side: 'against' } });
    assert.equal(r.status, 200);
    assert.equal(r.data.side, 'AGAINST');
    assert.equal(r.data.strongestReply.id, against);

    r = await s.api('PUT', `/api/videos/${root1}/opinion`, { user: 'me_user', json: { side: 'FOR' } });
    assert.equal(r.data.side, 'FOR');
    assert.equal(r.data.strongestReply, null);
    assert.equal(s.db.all('SELECT * FROM viewer_opinions').length, 1);

    let feed = await s.api('GET', '/api/videos/feed', { user: 'me_user' });
    assert.equal(feed.data.videos.find((v) => v.id === root1).viewerSide, 'FOR');
    assert.equal((await s.api('PUT', `/api/videos/${root1}/opinion`, { user: 'me_user', json: { side: 'meh' } })).status, 400);

    await s.api('DELETE', `/api/videos/${root1}/opinion`, { user: 'me_user' });
    feed = await s.api('GET', '/api/videos/feed', { user: 'me_user' });
    assert.equal(feed.data.videos.find((v) => v.id === root1).viewerSide, null);
  } finally { await s.close(); }
});

test('like shares the same rows as Home, and is idempotent', async () => {
  const { s, root1 } = await world();
  try {
    let r = await s.api('PUT', `/api/videos/${root1}/like`, { user: 'me_user' });
    assert.deepEqual(r.data, { liked: true, likeCount: 1 });
    r = await s.api('PUT', `/api/videos/${root1}/like`, { user: 'me_user' });
    assert.equal(r.data.likeCount, 1);
    const home = await s.api('GET', `/api/posts/${root1}`, { user: 'me_user' });
    assert.equal(home.data.post.likedByMe, true); // liked in Discover == liked in Home
    r = await s.api('DELETE', `/api/videos/${root1}/like`, { user: 'me_user' });
    assert.deepEqual(r.data, { liked: false, likeCount: 0 });
  } finally { await s.close(); }
});

test('writes need sign-in and a READY video; inputs are clamped', async () => {
  const { s, aman, root1 } = await world();
  try {
    const processing = addPost(s.db, { userId: aman, status: 'PROCESSING' });
    const text = addPost(s.db, { userId: aman, kind: 'TEXT', body: 'hi' });
    for (const [m, u, body] of [
      ['PUT', `/api/videos/${root1}/like`], ['PUT', `/api/videos/${root1}/opinion`, { side: 'FOR' }],
      ['POST', `/api/videos/${root1}/views`, {}], ['POST', `/api/videos/${root1}/interactions`, {}],
      ['POST', `/api/videos/${root1}/report`, { reason: 'SPAM' }], ['GET', '/api/videos/profile']
    ]) {
      assert.equal((await s.api(m, u, { json: body })).status, 401, `${m} ${u}`);
    }
    for (const id of [processing, text, 'missing']) {
      assert.equal((await s.api('PUT', `/api/videos/${id}/like`, { user: 'me_user' })).status, 404);
      assert.equal((await s.api('POST', `/api/videos/${id}/views`, { user: 'me_user', json: {} })).status, 404);
    }
    await s.api('POST', `/api/videos/${root1}/views`, { user: 'me_user', json: { watchedMs: 1e15, completed: true } });
    await s.api('POST', `/api/videos/${root1}/views`, { user: 'me_user', json: { watchedMs: -5, completed: 'yes' } });
    const rows = s.db.all('SELECT watched_ms, completed FROM post_views ORDER BY id');
    assert.deepEqual(rows, [{ watched_ms: 6 * 60 * 60 * 1000, completed: 1 }, { watched_ms: 0, completed: 0 }]);
  } finally { await s.close(); }
});

test('views feed the predicted-watch signal; interaction profile stays bounded', async () => {
  const { s, root1 } = await world();
  try {
    await s.api('POST', `/api/videos/${root1}/interactions`, { user: 'me_user', json: { watchDurationMs: 5000, completed: true } });
    const feed = await s.api('GET', '/api/videos/feed', { user: 'me_user' });
    const v = feed.data.videos.find((x) => x.id === root1);
    assert.equal(v.totalViews, 1);
    assert.equal(v.completedViews, 1);

    const profile = { topics: {}, creators: {} };
    for (let i = 0; i < 400; i++) profile.topics[`t${i}`] = i % 2 ? 0.9 : 0.1;
    profile.topics.neutral = 0.5;
    rec.pruneProfile(profile);
    assert.equal(Object.keys(profile.topics).length, 300);
    assert.equal(profile.topics.neutral, undefined); // the least informative goes first
  } finally { await s.close(); }
});

test('report: files into the shared review queue, odd reasons become OTHER, not your own', async () => {
  const { s, root1 } = await world();
  try {
    let r = await s.api('POST', `/api/videos/${root1}/report`, { user: 'me_user', json: { reason: 'Inappropriate content' } });
    assert.equal(r.status, 200);
    await s.api('POST', `/api/videos/${root1}/report`, { user: 'me_user', json: { reason: 'SPAM' } }); // once per person
    assert.deepEqual(s.db.all('SELECT reason FROM reports'), [{ reason: 'OTHER' }]);
    r = await s.api('POST', `/api/videos/${root1}/report`, { user: 'aman', json: { reason: 'SPAM' } });
    assert.equal(r.status, 400);
  } finally { await s.close(); }
});

test('GET /:id and /status: unfinished videos are visible only to their author; route order is safe', async () => {
  const { s, aman, root1 } = await world();
  try {
    const processing = addPost(s.db, { userId: aman, status: 'PROCESSING' });
    assert.equal((await s.api('GET', `/api/videos/${processing}`)).status, 404);
    assert.equal((await s.api('GET', `/api/videos/${processing}`, { user: 'riya' })).status, 404);
    const own = await s.api('GET', `/api/videos/${processing}/status`, { user: 'aman' });
    assert.equal(own.data.status, 'processing');
    assert.equal((await s.api('GET', `/api/videos/${root1}`)).data.id, root1);
    assert.equal((await s.api('GET', '/api/videos/all')).status, 200); // legacy list still wins over /:id
  } finally { await s.close(); }
});
