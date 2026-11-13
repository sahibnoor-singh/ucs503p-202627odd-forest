const { test } = require('node:test');
const assert = require('node:assert/strict');
const { startServer, addUser, addPost, follow, iso } = require('./helpers');

/** me_user and riya follow each other (friends); aman follows me only; kabir is a stranger. */
async function world(opts) {
  const s = await startServer(opts);
  const me = addUser(s.db, 'me_user');
  const riya = addUser(s.db, 'riya');
  const aman = addUser(s.db, 'aman');
  const kabir = addUser(s.db, 'kabir');
  follow(s.db, me, riya);
  follow(s.db, riya, me);
  follow(s.db, aman, me);
  const post = addPost(s.db, { userId: kabir, title: 'Ban phones in class' });
  return { s, me, riya, aman, kabir, post };
}

const send = (s, user, post, recipientIds) => s.api('POST', `/api/posts/${post}/share`, { user, json: { recipientIds } });

test('sending needs a sign-in, a real video and a sane list of people', async () => {
  const { s, riya, kabir, post } = await world();
  try {
    assert.equal((await s.api('POST', `/api/posts/${post}/share`, { json: { recipientIds: [riya] } })).status, 401);
    assert.equal((await send(s, 'me_user', 'no-such-post', [riya])).status, 404);
    const text = addPost(s.db, { userId: kabir, kind: 'TEXT', body: 'a text reply' });
    const t = await send(s, 'me_user', text, [riya]);
    assert.equal(t.status, 400);
    assert.match(t.data.error, /videos/i);
    const processing = addPost(s.db, { userId: kabir, status: 'PROCESSING' });
    assert.equal((await send(s, 'me_user', processing, [riya])).status, 404);
    for (const bad of [undefined, [], 'riya', [1], [riya, 5]]) {
      assert.equal((await send(s, 'me_user', post, bad)).status, 400, JSON.stringify(bad));
    }
    const many = Array.from({ length: 11 }, (_, i) => `id-${i}`);
    assert.equal((await send(s, 'me_user', post, many)).status, 400);
  } finally { await s.close(); }
});

test('only to friends: people you follow who follow you back. Everyone else is skipped with a reason', async () => {
  const { s, me, riya, aman, kabir, post } = await world();
  try {
    const bot = addUser(s.db, 'a_bot', { bot: true });
    follow(s.db, me, bot); follow(s.db, bot, me);
    const blocked = addUser(s.db, 'blocked_pal');
    follow(s.db, me, blocked); follow(s.db, blocked, me);
    s.db.run('INSERT INTO blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, ?)', [me, blocked, 'x']);
    const gone = addUser(s.db, 'gone');
    follow(s.db, me, gone); follow(s.db, gone, me);
    s.db.run("UPDATE users SET deleted_at = 'x' WHERE id = ?", [gone]);

    const r = await send(s, 'me_user', post, [riya, aman, kabir, bot, me, blocked, gone, 'unknown-id']);
    assert.equal(r.status, 200);
    assert.deepEqual(r.data.sent, [riya]);
    const why = Object.fromEntries(r.data.skipped.map((x) => [x.userId, x.reason]));
    assert.deepEqual(why, {
      [aman]: 'NOT_FRIENDS', [kabir]: 'NOT_FRIENDS', [bot]: 'BOT', [me]: 'SELF', [blocked]: 'UNAVAILABLE', [gone]: 'UNAVAILABLE', 'unknown-id': 'UNAVAILABLE'
    });
    assert.equal(s.db.get('SELECT COUNT(*) n FROM shares').n, 1, 'nothing was stored for the skipped ones');
  } finally { await s.close(); }
});

test('sending the same video to the same friend again is fine and changes nothing', async () => {
  const { s, riya, post } = await world();
  try {
    assert.deepEqual((await send(s, 'me_user', post, [riya])).data.sent, [riya]);
    const again = await send(s, 'me_user', post, [riya, riya]);
    assert.deepEqual(again.data.sent, [riya]);
    assert.equal(s.db.get('SELECT COUNT(*) n FROM shares').n, 1);
  } finally { await s.close(); }
});

test('at most 50 new sends a day; repeats do not count; the answer is a 429', async () => {
  const { s, me, riya, kabir } = await world();
  try {
    const posts = Array.from({ length: 51 }, (_, i) => addPost(s.db, { userId: kabir, title: `p${i}` }));
    for (let i = 0; i < 50; i++) assert.equal((await send(s, 'me_user', posts[i], [riya])).status, 200, `send ${i}`);
    const over = await send(s, 'me_user', posts[50], [riya]);
    assert.equal(over.status, 429);
    assert.ok(over.data.retryAfterSec > 0);
    assert.equal((await send(s, 'me_user', posts[0], [riya])).status, 200, 'a repeat costs nothing');

    // the day is a rolling 24 hours: a send from yesterday no longer counts
    s.db.run('UPDATE shares SET created_at = ? WHERE sender_id = ?', [iso(60 * 25), me]);
    assert.equal((await send(s, 'me_user', posts[50], [riya])).status, 200);
  } finally { await s.close(); }
});

test('the paper-plane is rate limited like other writes', async () => {
  const { s, riya, post } = await world({ appOptions: { rateLimit: { share: { max: 2, windowMs: 60000 } } } });
  try {
    assert.equal((await send(s, 'me_user', post, [riya])).status, 200);
    assert.equal((await send(s, 'me_user', post, [riya])).status, 200);
    assert.equal((await send(s, 'me_user', post, [riya])).status, 429);
  } finally { await s.close(); }
});

test('cannot send a video by someone who blocked you, or whose account is gone', async () => {
  const { s, me, riya, kabir, post } = await world();
  try {
    s.db.run('INSERT INTO blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, ?)', [kabir, me, 'x']);
    assert.equal((await send(s, 'me_user', post, [riya])).status, 404);
  } finally { await s.close(); }
});

test('friends list: mutual follows only, no bots, nobody blocked or gone, most-sent-to first', async () => {
  const { s, me, riya, aman } = await world();
  try {
    const zed = addUser(s.db, 'zed');
    follow(s.db, me, zed); follow(s.db, zed, me);
    const bot = addUser(s.db, 'a_bot', { bot: true });
    follow(s.db, me, bot); follow(s.db, bot, me);
    const blocked = addUser(s.db, 'blocked_pal');
    follow(s.db, me, blocked); follow(s.db, blocked, me);
    s.db.run('INSERT INTO blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, ?)', [blocked, me, 'x']);

    let r = await s.api('GET', '/api/users/friends', { user: 'me_user' });
    assert.equal(r.status, 200);
    assert.deepEqual(r.data.users.map((u) => u.username), ['riya', 'zed'], 'alphabetical until you have sent to someone');
    assert.ok(!JSON.stringify(r.data).match(/"phone"|"email"|password/i));

    const post = addPost(s.db, { userId: aman, title: 'x' });
    await send(s, 'me_user', post, [zed]);
    r = await s.api('GET', '/api/users/friends', { user: 'me_user' });
    assert.deepEqual(r.data.users.map((u) => u.username), ['zed', 'riya'], 'zed has been sent a video');
    assert.equal((await s.api('GET', '/api/users/friends')).status, 401);
    assert.ok(riya);
  } finally { await s.close(); }
});

test('a sent video arrives in the messages of the person it was sent to, once, and only their open marks it opened', async () => {
  const { s, me, riya, post } = await world();
  try {
    await send(s, 'me_user', post, [riya]);
    await send(s, 'me_user', post, [riya]); // again: no second message
    const thread = await s.api('GET', `/api/messages/with/${me}`, { user: 'riya' });
    assert.equal(thread.data.messages.length, 1);
    const m = thread.data.messages[0];
    assert.equal(m.fromMe, false);
    assert.equal(m.video.id, post);
    assert.equal(s.db.get('SELECT opened_at FROM shares').opened_at, null);
    assert.equal((await s.api('POST', `/api/messages/${m.id}/open`, { user: 'me_user' })).status, 200, 'the sender opening it changes nothing');
    assert.equal(s.db.get('SELECT opened_at FROM shares').opened_at, null);
    assert.equal((await s.api('POST', `/api/messages/${m.id}/open`, { user: 'riya' })).status, 200);
    assert.ok(s.db.get('SELECT opened_at FROM shares').opened_at);
  } finally { await s.close(); }
});
