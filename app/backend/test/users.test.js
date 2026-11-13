const { test } = require('node:test');
const assert = require('node:assert/strict');
const { startServer, addUser, follow, addPost } = require('./helpers');

test('suggested: people you could follow, never yourself, followed, blocked, blockers, or silent accounts', async () => {
  const s = await startServer();
  try {
    const me = addUser(s.db, 'me');
    const fresh = addUser(s.db, 'fresh'), old = addUser(s.db, 'old'), followed = addUser(s.db, 'followed');
    const blockedByMe = addUser(s.db, 'blocked_by_me'), blocksMe = addUser(s.db, 'blocks_me'), silent = addUser(s.db, 'silent');
    const unfinished = addUser(s.db, 'unfinished_only');
    addPost(s.db, { userId: old, title: 'old', minutesAgo: 500 });
    addPost(s.db, { userId: fresh, title: 'fresh', minutesAgo: 5 });
    for (const u of [followed, blockedByMe, blocksMe, me]) addPost(s.db, { userId: u, title: 'x', minutesAgo: 50 });
    addPost(s.db, { userId: unfinished, status: 'PROCESSING', title: 'x' });
    follow(s.db, me, followed);
    s.db.run('INSERT INTO blocks VALUES (?, ?, ?)', [me, blockedByMe, 'now']);
    s.db.run('INSERT INTO blocks VALUES (?, ?, ?)', [blocksMe, me, 'now']);

    const res = await s.api('GET', '/api/users/suggested', { user: 'me' });
    assert.equal(res.status, 200);
    assert.deepEqual(res.data.users.map((u) => u.user.username), ['fresh', 'old']); // most recently active first
    assert.equal(res.data.users[0].postCount, 1);
    assert.ok(silent && unfinished);

    assert.equal((await s.api('GET', '/api/users/suggested')).status, 401);
    const one = await s.api('GET', '/api/users/suggested?limit=1', { user: 'me' });
    assert.equal(one.data.users.length, 1);

    // following someone removes them from the list
    await s.api('POST', `/api/users/${fresh}/follow`, { user: 'me' });
    const after = await s.api('GET', '/api/users/suggested', { user: 'me' });
    assert.deepEqual(after.data.users.map((u) => u.user.username), ['old']);
  } finally { await s.close(); }
});

test('profile: counts, followedByMe, blockedByMe, isMe; unknown or blocked-by-them is a 404', async () => {
  const s = await startServer();
  try {
    const me = addUser(s.db, 'me'), a = addUser(s.db, 'a'), b = addUser(s.db, 'b'), hater = addUser(s.db, 'hater');
    addPost(s.db, { userId: a, title: 'one' });
    addPost(s.db, { userId: a, title: 'two' });
    addPost(s.db, { userId: a, title: 'hidden', status: 'PROCESSING' });
    follow(s.db, me, a); follow(s.db, b, a); follow(s.db, a, b);
    s.db.run('INSERT INTO blocks VALUES (?, ?, ?)', [hater, me, 'now']);
    s.db.run('INSERT INTO blocks VALUES (?, ?, ?)', [me, b, 'now']);

    let res = await s.api('GET', `/api/users/${a}`, { user: 'me' });
    assert.equal(res.status, 200);
    assert.equal(res.data.user.username, 'a');
    assert.equal(res.data.followerCount, 2);
    assert.equal(res.data.followingCount, 1);
    assert.equal(res.data.postCount, 2, 'unfinished posts are not counted');
    assert.equal(res.data.followedByMe, true);
    assert.equal(res.data.blockedByMe, false);
    assert.equal(res.data.isMe, false);

    res = await s.api('GET', `/api/users/${b}`, { user: 'me' }); // I blocked b: still viewable, so I can unblock
    assert.equal(res.data.blockedByMe, true);
    assert.equal(res.data.followedByMe, false);

    assert.equal((await s.api('GET', `/api/users/${me}`, { user: 'me' })).data.isMe, true);
    // 'hater' blocked me: I can't see their profile (404, we don't reveal why), but they can still see mine
    assert.equal((await s.api('GET', `/api/users/${hater}`, { user: 'me' })).status, 404);
    assert.equal((await s.api('GET', `/api/users/${me}`, { user: 'hater' })).status, 200);
    assert.equal((await s.api('GET', '/api/users/nobody', { user: 'me' })).status, 404);
    assert.equal((await s.api('GET', `/api/users/${a}`)).status, 401);
  } finally { await s.close(); }
});

test('my blocked list, newest first, and unblocking removes people from it', async () => {
  const s = await startServer();
  try {
    addUser(s.db, 'me');
    const a = addUser(s.db, 'a'), b = addUser(s.db, 'b');
    await s.api('POST', `/api/users/${a}/block`, { user: 'me' });
    await new Promise((r) => setTimeout(r, 5));
    await s.api('POST', `/api/users/${b}/block`, { user: 'me' });
    let res = await s.api('GET', '/api/me/blocks', { user: 'me' });
    assert.deepEqual(res.data.users.map((u) => u.username), ['b', 'a']);
    await s.api('DELETE', `/api/users/${b}/block`, { user: 'me' });
    res = await s.api('GET', '/api/me/blocks', { user: 'me' });
    assert.deepEqual(res.data.users.map((u) => u.username), ['a']);
    assert.equal((await s.api('GET', '/api/me/blocks')).status, 401);
  } finally { await s.close(); }
});
