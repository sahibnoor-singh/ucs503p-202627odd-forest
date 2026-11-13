// Discover learns from friends, within limits: edge strength from what you did with what they sent, the share of a page friends may
// take, the exploration floor, the credibility floor, the off switch, and likes teaching the profile.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { v4: uuid } = require('uuid');
const { startServer, addUser, addPost, follow, iso } = require('./helpers');
const ft = require('../src/friendTaste');

const DAY = 24 * 60 * 60 * 1000;
const ids = (list) => list.map((v) => v.id);

function setProfile(db, userId, topics, creators = {}) {
  const data = { userId, topics, creators, recentViews: [], watchTimeTotal: 0, interactionCounts: { completions: 0, skips: 0, rewatches: 0, saves: 0, shares: 0, likes: 0 } };
  db.run('INSERT OR REPLACE INTO user_profiles (user_id, data, updated_at) VALUES (?, ?, ?)', [userId, JSON.stringify(data), iso(0)]);
}

function addShare(db, { from, to, post, daysAgo = 0, opened = false }) {
  const at = new Date(Date.now() - daysAgo * DAY).toISOString();
  db.run('INSERT INTO shares (id, sender_id, recipient_id, post_id, created_at, opened_at) VALUES (?, ?, ?, ?, ?, ?)', [uuid(), from, to, post, at, opened ? at : null]);
  return at;
}
const like = (db, user, post, atIso) => db.run('INSERT OR REPLACE INTO likes (user_id, post_id, created_at) VALUES (?, ?, ?)', [user, post, atIso]);
const view = (db, user, post, watchedMs, completed, atIso) =>
  db.run('INSERT INTO post_views (user_id, post_id, watched_ms, completed, created_at) VALUES (?, ?, ?, ?, ?)', [user, post, watchedMs, completed ? 1 : 0, atIso]);

/** me, riya (friends), a pool of posts to send. */
async function edgeWorld() {
  const s = await startServer();
  const me = addUser(s.db, 'me_user');
  const riya = addUser(s.db, 'riya');
  const author = addUser(s.db, 'author');
  follow(s.db, me, riya);
  follow(s.db, riya, me);
  const posts = Array.from({ length: 6 }, (_, i) => addPost(s.db, { userId: author, title: `post ${i}` }));
  return { s, me, riya, author, posts };
}
const edgeOf = (s, me, who) => ft.friendEdges(s.db, me, Date.now()).find((e) => e.senderId === who);

test('edges: "consistently" means at least 3 videos on at least 2 different days, however much you liked them', async () => {
  const { s, me, riya, posts } = await edgeWorld();
  try {
    for (let i = 0; i < 2; i++) { const at = addShare(s.db, { from: riya, to: me, post: posts[i] }); like(s.db, me, posts[i], new Date(Date.parse(at) + 1000).toISOString()); }
    assert.equal(edgeOf(s, me, riya).strength, 0, 'two videos');
    const at3 = addShare(s.db, { from: riya, to: me, post: posts[2] });
    like(s.db, me, posts[2], new Date(Date.parse(at3) + 1000).toISOString());
    assert.equal(edgeOf(s, me, riya).strength, 0, 'three videos but all on one day');
    const at4 = addShare(s.db, { from: riya, to: me, post: posts[3], daysAgo: 1 });
    like(s.db, me, posts[3], new Date(Date.parse(at4) + 1000).toISOString());
    assert.ok(edgeOf(s, me, riya).strength > 0.9, 'four liked videos over two days is a full-strength friendship');
  } finally { await s.close(); }
});

test('edges: what you did with each video decides it: like > finish > watch > opened; skipped and ignored count against', async () => {
  const { s, me, riya, posts } = await edgeWorld();
  try {
    const raw = () => edgeOf(s, me, riya).raw;
    const send = (post, daysAgo) => addShare(s.db, { from: riya, to: me, post, daysAgo });
    const t0 = send(posts[0], 5); like(s.db, me, posts[0], new Date(Date.parse(t0) + 1000).toISOString());
    const t1 = send(posts[1], 4); view(s.db, me, posts[1], 9000, true, new Date(Date.parse(t1) + 1000).toISOString());
    const t2 = send(posts[2], 4); view(s.db, me, posts[2], 4000, false, new Date(Date.parse(t2) + 1000).toISOString());
    send(posts[3], 4); // never touched, older than 3 days: ignored
    const before = raw();
    const t4 = send(posts[4], 4); view(s.db, me, posts[4], 500, false, new Date(Date.parse(t4) + 1000).toISOString()); // skipped
    assert.ok(raw() < before + 0.001 && raw() < before, 'a skipped video lowers it');
    assert.ok(before > 1.5 && before < 2.2, `like 1 + finished 0.7 + watched 0.4 - ignored 0.3, slightly decayed (got ${before})`);
  } finally { await s.close(); }
});

test('edges: a video you have not had time to react to yet (under 3 days) neither helps nor hurts; reactions before the share do not count', async () => {
  const { s, me, riya, posts } = await edgeWorld();
  try {
    like(s.db, me, posts[0], iso(60 * 24 * 10)); // liked long before it was sent
    addShare(s.db, { from: riya, to: me, post: posts[0], daysAgo: 1 });
    addShare(s.db, { from: riya, to: me, post: posts[1], daysAgo: 2 });
    addShare(s.db, { from: riya, to: me, post: posts[2], daysAgo: 0 });
    const e = edgeOf(s, me, riya);
    assert.ok(Math.abs(e.raw) < 1e-9, `all three are too new to judge, and the old like does not count (raw ${e.raw})`);
  } finally { await s.close(); }
});

test('edges: older reactions count for half after 60 days', async () => {
  const { s, me, riya, posts } = await edgeWorld();
  try {
    const t = addShare(s.db, { from: riya, to: me, post: posts[0], daysAgo: 60 });
    like(s.db, me, posts[0], new Date(Date.parse(t) + 1000).toISOString());
    assert.ok(Math.abs(edgeOf(s, me, riya).raw - 0.5) < 0.02);
  } finally { await s.close(); }
});

test('edges: only real friends count: mutual, not a bot, not blocked either way, nobody deleted', async () => {
  const { s, me, posts } = await edgeWorld();
  try {
    const mk = (name, opts = {}) => {
      const id = addUser(s.db, name, opts);
      if (opts.mutual !== false) { follow(s.db, me, id); follow(s.db, id, me); } else follow(s.db, id, me);
      for (let i = 0; i < 4; i++) {
        const t = addShare(s.db, { from: id, to: me, post: posts[i], daysAgo: i % 2 });
        like(s.db, me, posts[i], new Date(Date.parse(t) + 1000).toISOString());
      }
      return id;
    };
    const good = mk('good_friend');
    mk('a_bot', { bot: true });
    mk('one_way', { mutual: false });
    const blocked = mk('blocked_pal');
    s.db.run('INSERT INTO blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, ?)', [me, blocked, 'x']);
    const gone = mk('gone');
    s.db.run("UPDATE users SET deleted_at = 'x' WHERE id = ?", [gone]);
    assert.deepEqual(ft.friendEdges(s.db, me, Date.now()).map((e) => e.senderId), [good]);
  } finally { await s.close(); }
});

test('the plan: friends take at most a quarter of a page, less when weak, nothing when off; exploration needs a known taste and a page of 5+', async () => {
  const strong = [{ senderId: 'a', strength: 1 }];
  assert.equal(ft.planPage({ edges: strong, limit: 10, friendsOn: true }).friendSlots, 2);
  assert.equal(ft.planPage({ edges: strong, limit: 24, friendsOn: true }).friendSlots, 6);
  assert.equal(ft.planPage({ edges: strong, limit: 3, friendsOn: true }).friendSlots, 0, 'a page of three has no room');
  assert.equal(ft.planPage({ edges: [{ senderId: 'a', strength: 0.2 }], limit: 24, friendsOn: true }).friendSlots, 1, 'a weak friendship gets a single post');
  assert.equal(ft.planPage({ edges: [{ senderId: 'a', strength: 0.1 }], limit: 24, friendsOn: true }).friends.length, 0, 'below the minimum is ignored');
  assert.equal(ft.planPage({ edges: strong, limit: 24, friendsOn: false }).friendSlots, 0, 'switched off');
  const many = ['a', 'b', 'c', 'd', 'e'].map((id) => ({ senderId: id, strength: 1 }));
  const p = ft.planPage({ edges: many, limit: 24, friendsOn: true });
  assert.equal(p.friends.length, ft.MAX_FRIENDS);
  assert.ok(p.friendSlots <= 6, 'more friends never means more than the cap');

  assert.equal(ft.planPage({ edges: [], limit: 10, friendsOn: true, knownTopics: 20 }).exploreSlots, 1);
  assert.equal(ft.planPage({ edges: [], limit: 30, friendsOn: true, knownTopics: 20 }).exploreSlots, 3);
  assert.equal(ft.planPage({ edges: [], limit: 10, friendsOn: false, knownTopics: 20 }).exploreSlots, 1, 'exploration stays when friends are switched off');
  assert.equal(ft.planPage({ edges: [], limit: 10, friendsOn: true, knownTopics: 2 }).exploreSlots, 0, 'a new person has no habits to explore away from');
  assert.equal(ft.planPage({ edges: [], limit: 4, friendsOn: true, knownTopics: 20 }).exploreSlots, 0);
});

const MY_TOPICS = { climate: 0.8, subsidies: 0.8, policy: 0.8, rainfall: 0.8, farming: 0.8, water: 0.8, solar: 0.8, wind: 0.8 };

/** me likes climate; riya (a consistent, well-liked friend) likes cricket; 14 posts of each, plus a few that riya sent. */
async function mixWorld({ cricketCredibility = 80 } = {}) {
  const s = await startServer();
  const me = addUser(s.db, 'me_user');
  const riya = addUser(s.db, 'riya');
  const creators = ['cr_a', 'cr_b', 'cr_c', 'cr_d'].map((n) => addUser(s.db, n));
  follow(s.db, me, riya);
  follow(s.db, riya, me);
  const cricket = [];
  const climate = [];
  for (let i = 0; i < 14; i++) {
    climate.push(addPost(s.db, { userId: creators[i % 4], title: `climate subsidies ${i}`, analysis: { transcript: 'x', claims: [{ credibilityScore: 80 }] }, minutesAgo: 10 + i }));
    cricket.push(addPost(s.db, { userId: creators[(i + 1) % 4], title: `cricket selection ${i}`, analysis: { transcript: 'x', claims: [{ credibilityScore: cricketCredibility }] }, minutesAgo: 30 + i }));
  }
  const sent = [addPost(s.db, { userId: creators[0], title: 'old one a', minutesAgo: 5000 }), addPost(s.db, { userId: creators[0], title: 'old one b', minutesAgo: 5000 }),
    addPost(s.db, { userId: creators[0], title: 'old one c', minutesAgo: 5000 }), addPost(s.db, { userId: creators[0], title: 'old one d', minutesAgo: 5000 })];
  sent.forEach((p, i) => {
    const t = addShare(s.db, { from: riya, to: me, post: p, daysAgo: i % 2 ? 1 : 0 });
    like(s.db, me, p, new Date(Date.parse(t) + 1000).toISOString());
  });
  setProfile(s.db, me, MY_TOPICS);
  setProfile(s.db, riya, { cricket: 0.95, selection: 0.9 });
  return { s, me, riya, cricket, climate, sent };
}

const feed = (s, extra = '') => s.api('GET', `/api/videos/feed?limit=10&explain=1${extra}`, { user: 'me_user' });

test('the page: mostly your own ranking, at most a quarter from a consistent friend\'s taste, and some exploration', async () => {
  const { s, cricket, climate } = await mixWorld();
  try {
    const page = (await feed(s)).data.videos;
    assert.equal(page.length, 10);
    const by = (src) => page.filter((v) => v.source === src);
    assert.ok(by('friend').length >= 1 && by('friend').length <= 2, `1-2 friend posts out of 10 (got ${by('friend').length})`);
    assert.ok(by('friend').every((v) => cricket.includes(v.id) && v.via === 'riya'), "chosen by riya's taste (cricket), and attributed only in the dev explanation");
    assert.equal(by('explore').length, 1);
    assert.ok(cricket.includes(by('explore')[0].id), 'exploration is away from your climate habit');
    assert.ok(by('own').length >= 7);
    assert.ok(by('own').filter((v) => climate.includes(v.id)).length >= 5, 'own picks are what you like');
    assert.equal(new Set(ids(page)).size, 10, 'no repeats within a page');
  } finally { await s.close(); }
});

test('without ?explain nothing about sources or friends is sent', async () => {
  const { s } = await mixWorld();
  try {
    const r = await s.api('GET', '/api/videos/feed?limit=10', { user: 'me_user' });
    const flat = JSON.stringify(r.data);
    assert.ok(!/"source"|"via"|riya_taste|"topics"|"creators"/.test(flat), 'no hint of why a post is there, and never a profile');
  } finally { await s.close(); }
});

test('people are told why: friend picks say whose taste, exploration says so, own picks say nothing, and no profile is ever sent', async () => {
  const { s } = await mixWorld();
  try {
    const page = (await s.api('GET', '/api/videos/feed?limit=10', { user: 'me_user' })).data.videos;
    const friend = page.filter((v) => v.why && v.why.kind === 'friend');
    const explore = page.filter((v) => v.why && v.why.kind === 'explore');
    assert.ok(friend.length >= 1 && friend.every((v) => v.why.by === 'riya' && Object.keys(v.why).sort().join() === 'by,kind'));
    assert.equal(explore.length, 1);
    assert.ok(explore.every((v) => Object.keys(v.why).join() === 'kind'));
    assert.ok(page.filter((v) => !v.why).length >= 7, 'the rest is just their own ranking');
    assert.ok(!/"source"|"via"|"topics"|"creators"|cricket_affinity/.test(JSON.stringify(page)));
    const off = await s.api('PUT', '/api/me/settings', { user: 'me_user', json: { friendTaste: false } });
    assert.equal(off.status, 200);
    const after = (await s.api('GET', '/api/videos/feed?limit=10', { user: 'me_user' })).data.videos;
    assert.ok(!after.some((v) => v.why && v.why.kind === 'friend'), 'switched off: nobody is credited');
  } finally { await s.close(); }
});

test('pages carry on without repeating, and the friend and exploration shares hold on every page', async () => {
  const { s } = await mixWorld();
  try {
    const seen = [];
    let cursor = '';
    for (let guard = 0; guard < 10; guard++) {
      const r = await s.api('GET', `/api/videos/feed?limit=10&explain=1${cursor}`, { user: 'me_user' });
      assert.equal(r.status, 200);
      const friend = r.data.videos.filter((v) => v.source === 'friend').length;
      assert.ok(friend <= 2, `page ${guard}: ${friend} friend posts`);
      seen.push(...ids(r.data.videos));
      if (!r.data.nextCursor) break;
      cursor = `&cursor=${r.data.nextCursor}`;
    }
    assert.equal(new Set(seen).size, seen.length, 'nothing served twice across pages');
    assert.equal(seen.length, 32, 'and nothing was lost');
  } finally { await s.close(); }
});

test('friend picks must clear the credibility floor; so must exploration', async () => {
  const { s, cricket } = await mixWorld({ cricketCredibility: 20 });
  try {
    const page = (await feed(s)).data.videos;
    const extras = page.filter((v) => v.source === 'friend' || v.source === 'explore');
    assert.ok(extras.every((v) => !cricket.includes(v.id)), 'a cricket post (fact-check score 20) is never added as a friend pick or as exploration');
  } finally { await s.close(); }
});

test('the switch: with friend taste off a person gets no friend posts but keeps the exploration', async () => {
  const { s } = await mixWorld();
  try {
    assert.equal((await s.api('GET', '/api/me', { user: 'me_user' })).data.settings.friendTaste, true);
    assert.equal((await s.api('PUT', '/api/me/settings', { user: 'me_user', json: { friendTaste: 'yes' } })).status, 400);
    assert.equal((await s.api('PUT', '/api/me/settings')).status, 401);
    const off = await s.api('PUT', '/api/me/settings', { user: 'me_user', json: { friendTaste: false } });
    assert.deepEqual(off.data, { settings: { friendTaste: false } });
    assert.equal((await s.api('GET', '/api/me', { user: 'me_user' })).data.settings.friendTaste, false);
    const page = (await feed(s)).data.videos;
    assert.equal(page.filter((v) => v.source === 'friend').length, 0);
    assert.equal(page.filter((v) => v.source === 'explore').length, 1);
  } finally { await s.close(); }
});

test('a friend you ignore stops mattering: ignored videos remove their influence', async () => {
  const { s, me } = await mixWorld();
  try {
    s.db.run('DELETE FROM likes WHERE user_id = ?', [me]); // nothing was liked after all
    s.db.run("UPDATE shares SET created_at = ? WHERE recipient_id = ?", [iso(60 * 24 * 5), me]); // sent five days ago, never touched
    s.db.run("UPDATE shares SET created_at = created_at");
    const page = (await feed(s)).data.videos;
    assert.equal(page.filter((v) => v.source === 'friend').length, 0);
  } finally { await s.close(); }
});

test('the feed for someone signed out is just the ranking: no friends, no exploration slots', async () => {
  const { s } = await mixWorld();
  try {
    const r = await s.api('GET', '/api/videos/feed?limit=10&explain=1');
    assert.equal(r.status, 200);
    assert.ok(r.data.videos.every((v) => v.source === 'own'));
  } finally { await s.close(); }
});

test('likes teach the profile: topics and creator move up once, a repeat or an unlike changes nothing, and a like is not a view', async () => {
  const s = await startServer();
  try {
    const a = addUser(s.db, 'cr_a');
    addUser(s.db, 'fan');
    const post = addPost(s.db, { userId: a, title: 'climate subsidies' });
    const text = addPost(s.db, { userId: a, kind: 'TEXT', body: 'climate words' });
    const profile = async () => (await s.api('GET', '/api/videos/profile', { user: 'fan' })).data;

    assert.equal((await s.api('PUT', `/api/videos/${post}/like`, { user: 'fan' })).status, 200);
    const p1 = await profile();
    assert.ok(p1.topics.climate > 0.5 && p1.topics.subsidies > 0.5);
    assert.ok(p1.creators.cr_a > 0.5);
    assert.equal(p1.interactionCounts.likes, 1);
    assert.equal(p1.recentViews.length, 0, 'liking is not watching: it must not count as a repeat view');

    await s.api('PUT', `/api/videos/${post}/like`, { user: 'fan' });
    assert.deepEqual((await profile()).topics, p1.topics, 'the same like again');
    await s.api('DELETE', `/api/videos/${post}/like`, { user: 'fan' });
    assert.deepEqual((await profile()).topics, p1.topics, 'unliking does not undo what was learned');

    // Home's like route teaches it too, but only for videos
    await s.api('POST', `/api/posts/${text}/like`, { user: 'fan' });
    assert.equal((await profile()).interactionCounts.likes, 1, 'a text post teaches nothing');
    const other = addPost(s.db, { userId: a, title: 'cricket selection' });
    await s.api('POST', `/api/posts/${other}/like`, { user: 'fan' });
    assert.ok((await profile()).topics.cricket > 0.5);
  } finally { await s.close(); }
});
