// Direct messages: videos that were sent (routes/shares.js) and emoji reactions to them. There is no free text.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { startServer, addUser, addPost, follow } = require('./helpers');

/** me_user and riya are friends; aman only follows me (not friends); kabir is a stranger who posts the videos. */
async function world(opts) {
  const s = await startServer(opts);
  const me = addUser(s.db, 'me_user');
  const riya = addUser(s.db, 'riya');
  const aman = addUser(s.db, 'aman');
  const kabir = addUser(s.db, 'kabir');
  follow(s.db, me, riya); follow(s.db, riya, me);
  follow(s.db, aman, me);
  return { s, me, riya, aman, kabir };
}

const post = (s, author, title = 'Ban phones in class') => addPost(s.db, { userId: author, title });
const sendVideo = (s, from, postId, to) => s.api('POST', `/api/posts/${postId}/share`, { user: from, json: { recipientIds: [to] } });
const thread = (s, user, other, extra = '') => s.api('GET', `/api/messages/with/${other}${extra}`, { user });
const inbox = (s, user) => s.api('GET', '/api/messages/conversations', { user });
const react = (s, user, id, emoji) => s.api('PUT', `/api/messages/${id}/reaction`, { user, json: { emoji } });

test('every messages route needs a sign-in', async () => {
  const { s, riya } = await world();
  try {
    for (const [method, url] of [['GET', '/api/messages/conversations'], ['GET', '/api/messages/unread'],
      ['GET', `/api/messages/with/${riya}`], ['POST', `/api/messages/with/${riya}/read`],
      ['POST', '/api/messages/x/open'], ['PUT', '/api/messages/x/reaction'], ['DELETE', '/api/messages/x/reaction']]) {
      assert.equal((await s.api(method, url)).status, 401, `${method} ${url}`);
    }
  } finally { await s.close(); }
});

test('there is no way to send text: the route does not exist', async () => {
  const { s, riya } = await world();
  try {
    const r = await s.api('POST', `/api/messages/with/${riya}`, { user: 'me_user', json: { text: 'hello' } });
    assert.equal(r.status, 404);
    assert.equal(s.db.get('SELECT COUNT(*) n FROM messages').n, 0);
  } finally { await s.close(); }
});

test('a sent video shows in both threads on the right side, and nothing but videos is ever listed', async () => {
  const { s, me, riya, kabir } = await world();
  try {
    const p = post(s, kabir);
    assert.equal((await sendVideo(s, 'me_user', p, riya)).status, 200);
    const mine = await thread(s, 'me_user', riya);
    assert.deepEqual(mine.data.messages.map((m) => [m.video.id, m.fromMe]), [[p, true]]);
    const hers = await thread(s, 'riya', me);
    assert.deepEqual(hers.data.messages.map((m) => [m.video.id, m.fromMe]), [[p, false]]);
    assert.equal(hers.data.with.username, 'me_user');
    assert.ok(!JSON.stringify(hers.data).match(/"phone"|"email"|password|"text"/), 'no private fields and no text');
    assert.ok('coverUrl' in hers.data.messages[0].video, 'the same Video shape as Discover');
  } finally { await s.close(); }
});

test('inbox: newest conversation first, preview, unread until read; what you sent yourself is never unread', async () => {
  const { s, me, riya, kabir } = await world();
  try {
    const zed = addUser(s.db, 'zed');
    follow(s.db, me, zed); follow(s.db, zed, me);
    await sendVideo(s, 'riya', post(s, kabir, 'a'), me);
    await sendVideo(s, 'riya', post(s, kabir, 'b'), me);
    await sendVideo(s, 'zed', post(s, kabir, 'c'), me);

    let r = await inbox(s, 'me_user');
    assert.deepEqual(r.data.conversations.map((c) => c.with.username), ['zed', 'riya']);
    const riyaRow = r.data.conversations[1];
    assert.equal(riyaRow.unread, 2);
    assert.equal(riyaRow.last.preview, 'Sent you a video');
    assert.equal(riyaRow.last.fromMe, false);
    assert.equal(r.data.unreadTotal, 2, 'two conversations have something new');
    assert.equal((await s.api('GET', '/api/messages/unread', { user: 'me_user' })).data.unread, 2);

    assert.equal((await s.api('POST', `/api/messages/with/${riya}/read`, { user: 'me_user' })).status, 200);
    r = await inbox(s, 'me_user');
    assert.equal(r.data.conversations.find((c) => c.with.username === 'riya').unread, 0);
    assert.equal(r.data.unreadTotal, 1);

    await sendVideo(s, 'me_user', post(s, kabir, 'd'), riya);
    r = await inbox(s, 'me_user');
    assert.equal(r.data.conversations[0].last.preview, 'You sent a video');
    assert.equal(r.data.conversations[0].unread, 0);
    assert.equal((await inbox(s, 'riya')).data.conversations[0].unread, 1, 'but it is new for her');
  } finally { await s.close(); }
});

test('inbox hides conversations with someone you blocked, who blocked you, or whose account is gone', async () => {
  const { s, me, riya, kabir } = await world();
  try {
    await sendVideo(s, 'riya', post(s, kabir), me);
    assert.equal((await inbox(s, 'me_user')).data.conversations.length, 1);
    s.db.run('INSERT INTO blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, ?)', [me, riya, 'x']);
    assert.equal((await inbox(s, 'me_user')).data.conversations.length, 0);
    assert.equal((await s.api('GET', '/api/messages/unread', { user: 'me_user' })).data.unread, 0);
    assert.equal((await thread(s, 'me_user', riya)).status, 404);
    s.db.run('DELETE FROM blocks');
    s.db.run("UPDATE users SET deleted_at = 'x' WHERE id = ?", [riya]);
    assert.equal((await inbox(s, 'me_user')).data.conversations.length, 0);
  } finally { await s.close(); }
});

test('an old conversation stays readable after you stop being friends, but nothing new can be sent into it', async () => {
  const { s, me, riya, kabir } = await world();
  try {
    await sendVideo(s, 'riya', post(s, kabir), me);
    s.db.run('DELETE FROM follows WHERE follower_id = ? AND followee_id = ?', [riya, me]);
    assert.equal((await thread(s, 'me_user', riya)).data.messages.length, 1);
    const again = await sendVideo(s, 'me_user', post(s, kabir, 'new'), riya);
    assert.deepEqual(again.data.skipped, [{ userId: riya, reason: 'NOT_FRIENDS' }]);
  } finally { await s.close(); }
});

test('threads page backwards from the newest, without repeats', async () => {
  const { s, riya, kabir } = await world();
  try {
    const posts = Array.from({ length: 12 }, (_, i) => post(s, kabir, `v${i}`));
    for (const p of posts) await sendVideo(s, 'me_user', p, riya);
    const titles = (r) => r.data.messages.map((m) => m.video.title);
    const first = await thread(s, 'me_user', riya, '?limit=5');
    assert.deepEqual(titles(first), ['v7', 'v8', 'v9', 'v10', 'v11']);
    assert.equal(first.data.hasMore, true);
    const second = await thread(s, 'me_user', riya, `?limit=5&before=${first.data.messages[0].id}`);
    assert.deepEqual(titles(second), ['v2', 'v3', 'v4', 'v5', 'v6']);
    const third = await thread(s, 'me_user', riya, `?limit=5&before=${second.data.messages[0].id}`);
    assert.deepEqual(titles(third), ['v0', 'v1']);
    assert.equal(third.data.hasMore, false);
    assert.equal((await thread(s, 'me_user', riya, '?before=nonsense')).status, 400);
  } finally { await s.close(); }
});

test('a conversation with nobody yet is an empty thread, not an error', async () => {
  const { s, riya } = await world();
  try {
    const r = await thread(s, 'me_user', riya);
    assert.equal(r.status, 200);
    assert.deepEqual(r.data.messages, []);
    assert.deepEqual((await inbox(s, 'me_user')).data, { conversations: [], unreadTotal: 0 });
  } finally { await s.close(); }
});

test('a video that is no longer available says so instead of breaking the thread', async () => {
  const { s, me, riya, kabir } = await world();
  try {
    const gone = post(s, kabir, 'Soon hidden');
    const fine = post(s, kabir, 'Still here');
    await sendVideo(s, 'me_user', gone, riya);
    await sendVideo(s, 'me_user', fine, riya);
    s.db.run("UPDATE posts SET status = 'HIDDEN' WHERE id = ?", [gone]);
    const r = await thread(s, 'riya', me);
    assert.deepEqual(r.data.messages.map((m) => m.video && m.video.id), [null, fine]);
  } finally { await s.close(); }
});

test('opening a received video marks it opened; the sender opening their own changes nothing', async () => {
  const { s, me, riya, kabir } = await world();
  try {
    await sendVideo(s, 'me_user', post(s, kabir), riya);
    const id = (await thread(s, 'riya', me)).data.messages[0].id;
    assert.equal((await s.api('POST', `/api/messages/${id}/open`, { user: 'me_user' })).status, 200);
    assert.equal(s.db.get('SELECT opened_at FROM shares').opened_at, null);
    assert.equal((await s.api('POST', `/api/messages/${id}/open`, { user: 'riya' })).status, 200);
    assert.ok(s.db.get('SELECT opened_at FROM shares').opened_at);
  } finally { await s.close(); }
});

test('reactions: six emojis, one per person per video, a new one replaces the old, each side sees both', async () => {
  const { s, me, riya, kabir } = await world();
  try {
    await sendVideo(s, 'me_user', post(s, kabir), riya);
    const m = (await thread(s, 'riya', me)).data.messages[0];

    assert.equal((await react(s, 'riya', m.id, '🍕')).status, 400, 'not in the set');
    assert.equal((await react(s, 'riya', m.id, undefined)).status, 400);
    assert.deepEqual((await react(s, 'riya', m.id, '❤️')).data.reactions, { mine: '❤️', theirs: null });
    assert.deepEqual((await react(s, 'riya', m.id, '😂')).data.reactions, { mine: '😂', theirs: null }, 'replaced, not added');
    assert.deepEqual((await react(s, 'me_user', m.id, '🔥')).data.reactions, { mine: '🔥', theirs: '😂' });

    assert.deepEqual((await thread(s, 'me_user', riya)).data.messages[0].reactions, { mine: '🔥', theirs: '😂' });
    assert.deepEqual((await thread(s, 'riya', me)).data.messages[0].reactions, { mine: '😂', theirs: '🔥' });
    assert.deepEqual((await s.api('DELETE', `/api/messages/${m.id}/reaction`, { user: 'riya' })).data.reactions, { mine: null, theirs: '🔥' });
    assert.equal(s.db.get('SELECT COUNT(*) n FROM message_reactions').n, 1);
  } finally { await s.close(); }
});

test('the sender is told about a reaction: it shows in their inbox as something new, and the thread still lists only videos', async () => {
  const { s, me, riya, kabir } = await world();
  try {
    await sendVideo(s, 'me_user', post(s, kabir), riya);
    await s.api('POST', `/api/messages/with/${riya}/read`, { user: 'me_user' });
    assert.equal((await inbox(s, 'me_user')).data.conversations[0].unread, 0);

    const m = (await thread(s, 'riya', me)).data.messages[0];
    await react(s, 'riya', m.id, '😮');
    let row = (await inbox(s, 'me_user')).data.conversations[0];
    assert.equal(row.last.preview, 'Reacted 😮 to your video');
    assert.equal(row.unread, 1);
    assert.equal((await s.api('GET', '/api/messages/unread', { user: 'me_user' })).data.unread, 1);
    assert.equal((await inbox(s, 'riya')).data.conversations[0].last.preview, 'You reacted 😮');

    await react(s, 'riya', m.id, '🔥');
    assert.equal(s.db.get("SELECT COUNT(*) n FROM messages WHERE kind = 'REACTION'").n, 1, 'one note per person per video: the newest');
    assert.equal((await inbox(s, 'me_user')).data.conversations[0].last.preview, 'Reacted 🔥 to your video');

    assert.equal((await thread(s, 'me_user', riya)).data.messages.length, 1, 'the note is not a message in the thread');

    await s.api('DELETE', `/api/messages/${m.id}/reaction`, { user: 'riya' });
    assert.equal(s.db.get("SELECT COUNT(*) n FROM messages WHERE kind = 'REACTION'").n, 0);
    row = (await inbox(s, 'me_user')).data.conversations[0];
    assert.equal(row.last.preview, 'You sent a video', 'taking it back takes the note away');
  } finally { await s.close(); }
});

test('only videos can be reacted to, and nobody outside the conversation can react to, open or read it', async () => {
  const { s, riya, aman, kabir } = await world();
  try {
    await sendVideo(s, 'me_user', post(s, kabir), riya);
    const m = (await thread(s, 'riya', (await s.db.get("SELECT id FROM users WHERE username = 'me_user'")).id)).data.messages[0];
    await react(s, 'riya', m.id, '👍');
    const note = s.db.get("SELECT id FROM messages WHERE kind = 'REACTION'").id;
    assert.equal((await react(s, 'me_user', note, '👍')).status, 404, 'a reaction note is not something to react to');

    assert.equal((await react(s, 'aman', m.id, '👍')).status, 404);
    assert.equal((await s.api('POST', `/api/messages/${m.id}/open`, { user: 'aman' })).status, 404);
    assert.equal((await s.api('DELETE', `/api/messages/${m.id}/reaction`, { user: 'aman' })).status, 404);
    assert.deepEqual((await thread(s, 'aman', riya)).data.messages, [], 'aman has his own (empty) conversation with riya, not theirs');
    assert.ok(aman);
  } finally { await s.close(); }
});

test('reacting is rate limited', async () => {
  const { s, me, riya, kabir } = await world({ appOptions: { rateLimit: { message: { max: 3, windowMs: 60000 } } } });
  try {
    await sendVideo(s, 'me_user', post(s, kabir), riya);
    const m = (await thread(s, 'riya', me)).data.messages[0];
    for (let i = 0; i < 3; i++) assert.equal((await react(s, 'riya', m.id, '👍')).status, 200);
    assert.equal((await react(s, 'riya', m.id, '🔥')).status, 429);
  } finally { await s.close(); }
});
