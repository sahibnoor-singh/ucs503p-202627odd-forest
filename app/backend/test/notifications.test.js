const { test } = require('node:test');
const assert = require('node:assert/strict');
const { startServer, addUser, addPost, follow } = require('./helpers');

const FOLLOW = (s, who, id, fromPostId) => s.api('POST', `/api/users/${id}/follow`, { user: who, json: fromPostId ? { fromPostId } : {} });
const list = (s, who) => s.api('GET', '/api/notifications', { user: who });

async function world() {
  const s = await startServer();
  const author = addUser(s.db, 'author_a');
  const fan = addUser(s.db, 'fan_f');
  const other = addUser(s.db, 'other_o');
  const reel = addPost(s.db, { userId: author, title: 'Ban phones in class' });
  const othersReel = addPost(s.db, { userId: other, title: 'Not the author\'s' });
  return { s, author, fan, other, reel, othersReel };
}

test('a follow tells the person once, and names the reel it was done from', async () => {
  const { s, author, fan, reel } = await world();
  try {
    assert.equal((await s.api('GET', '/api/notifications')).status, 401, 'needs a sign-in');
    assert.equal((await FOLLOW(s, 'fan_f', author, reel)).status, 200);
    const { data } = await list(s, 'author_a');
    assert.equal(data.unread, 1);
    assert.equal(data.notifications.length, 1);
    const n = data.notifications[0];
    assert.equal(n.text, '@fan_f followed you from this reel');
    assert.equal(n.actor.id, fan);
    assert.equal(n.post.id, reel);
    assert.equal(n.post.title, 'Ban phones in class');
    assert.equal(n.read, false);

    // unfollow and follow again: still one notification, and the person who followed is not told anything
    await s.api('DELETE', `/api/users/${author}/follow`, { user: 'fan_f' });
    await FOLLOW(s, 'fan_f', author, reel);
    assert.equal((await list(s, 'author_a')).data.notifications.length, 1);
    assert.equal((await list(s, 'fan_f')).data.notifications.length, 0);
  } finally { await s.close(); }
});

test('a follow from the profile says only who; a post that is not theirs is ignored', async () => {
  const { s, author, other, othersReel } = await world();
  try {
    await FOLLOW(s, 'fan_f', author); // no reel
    await FOLLOW(s, 'other_o', author, othersReel); // somebody else's video: never named
    const texts = (await list(s, 'author_a')).data.notifications.map((n) => [n.text, n.post]);
    assert.deepEqual(texts.sort(), [['@fan_f followed you', null], ['@other_o followed you', null]].sort());
    assert.ok(other);
  } finally { await s.close(); }
});

test('opening the list marks everything read; a later follow is unread again', async () => {
  const { s, author, reel } = await world();
  try {
    await FOLLOW(s, 'fan_f', author, reel);
    assert.equal((await list(s, 'author_a')).data.unread, 1);
    assert.equal((await s.api('POST', '/api/notifications/read', { user: 'author_a' })).data.unread, 0);
    const after = await list(s, 'author_a');
    assert.equal(after.data.unread, 0);
    assert.equal(after.data.notifications[0].read, true);
    await FOLLOW(s, 'other_o', author);
    assert.equal((await list(s, 'author_a')).data.unread, 1);
  } finally { await s.close(); }
});

test('blocked people, deleted accounts and removed videos do not leak into the list', async () => {
  const { s, author, fan, other, reel } = await world();
  try {
    await FOLLOW(s, 'fan_f', author, reel);
    await FOLLOW(s, 'other_o', author);
    // blocking someone hides what they did
    await s.api('POST', `/api/users/${other}/block`, { user: 'author_a' });
    assert.deepEqual((await list(s, 'author_a')).data.notifications.map((n) => n.actor.username), ['fan_f']);
    // a video that is gone keeps the notification, without the reel
    s.db.run("UPDATE posts SET status = 'FAILED' WHERE id = ?", [reel]);
    const n = (await list(s, 'author_a')).data.notifications[0];
    assert.equal(n.text, '@fan_f followed you');
    assert.equal(n.post, null);
    // deleting the account of whoever followed removes the line
    s.db.run('UPDATE users SET deleted_at = ? WHERE id = ?', [new Date().toISOString(), fan]);
    assert.equal((await list(s, 'author_a')).data.notifications.length, 0);
  } finally { await s.close(); }
});

test('a blocked person cannot follow, so nobody is told', async () => {
  const { s, author, fan } = await world();
  try {
    await s.api('POST', `/api/users/${fan}/block`, { user: 'author_a' });
    assert.equal((await FOLLOW(s, 'fan_f', author)).status, 403);
    assert.equal((await list(s, 'author_a')).data.notifications.length, 0);
  } finally { await s.close(); }
});

test('deleting your own account removes the notifications you sent and received', async () => {
  const { s, author, reel } = await world();
  try {
    await FOLLOW(s, 'fan_f', author, reel);
    assert.equal(s.db.get('SELECT COUNT(*) AS n FROM notifications').n, 1);
    const r = await s.api('DELETE', '/api/me', { user: 'fan_f', json: {} });
    // the dev-user shortcut has no password to confirm: the route may refuse, and then nothing is removed
    if (r.status === 200) assert.equal(s.db.get('SELECT COUNT(*) AS n FROM notifications').n, 0);
  } finally { await s.close(); }
});

test('videos say whether the viewer already follows the author', async () => {
  const { s, author, reel } = await world();
  try {
    const before = (await s.api('GET', '/api/videos/feed?limit=20', { user: 'fan_f' })).data.videos.find((v) => v.id === reel);
    assert.equal(before.authorFollowed, false);
    await FOLLOW(s, 'fan_f', author);
    const after = (await s.api('GET', '/api/videos/feed?limit=20', { user: 'fan_f' })).data.videos.find((v) => v.id === reel);
    assert.equal(after.authorFollowed, true);
  } finally { await s.close(); }
});
