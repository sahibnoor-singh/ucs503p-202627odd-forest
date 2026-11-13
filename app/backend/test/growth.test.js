const fs = require('fs');
const path = require('path');
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { startServer, addUser, follow, addPost, videoForm, TEST_SECRET } = require('./helpers');
const { PROMPTS, dayKey, promptFor, openDays } = require('../src/prompts');
const { TOPICS } = require('../src/topics');
const { createTokens } = require('../src/auth/tokens');
const { cleanProps } = require('../src/events');
const { computeInsights } = require('../src/insights');
const legal = require('../src/legalText');

const tokens = createTokens(TEST_SECRET);
// 2026-10-21 12:00 UTC is 17:30 that day in India
const NOON = Date.UTC(2026, 9, 21, 12, 0, 0);
const withClock = async (extra = {}, opts = {}) => {
  const clock = { now: NOON };
  const s = await startServer({ ...opts, appOptions: { clock: () => clock.now, ...extra } });
  return { s, clock };
};
const post = (s, url, json, user) => s.api('POST', url, { json, user });
const get = (s, url, user) => s.api('GET', url, { user });
const idsOf = (items) => items.map((i) => i.post.id);

// ---------------- the daily question ----------------

test('prompts: every question has a known topic, no two are the same, and a day always gives the same one', () => {
  const topics = new Set(TOPICS.map((t) => t.id));
  for (const p of PROMPTS) assert.ok(topics.has(p.topic), p.text);
  assert.equal(new Set(PROMPTS.map((p) => p.text)).size, PROMPTS.length);
  for (const p of PROMPTS) assert.ok(p.text.endsWith('?') && p.text.length < 120, p.text);
  assert.deepEqual(promptFor('2026-10-21'), promptFor('2026-10-21'));
  const week = new Set(Array.from({ length: PROMPTS.length }, (_, i) => promptFor(new Date(Date.UTC(2026, 0, 1 + i)).toISOString().slice(0, 10)).text));
  assert.equal(week.size, PROMPTS.length, 'a full cycle shows every question once');
  assert.equal(promptFor('nonsense'), null);
  assert.equal(promptFor('2026-13-40'), null);
});

test('the question changes at midnight in India, and today and yesterday are the two open ones', () => {
  assert.equal(dayKey(Date.UTC(2026, 9, 21, 18, 29)), '2026-10-21'); // 23:59 IST
  assert.equal(dayKey(Date.UTC(2026, 9, 21, 18, 31)), '2026-10-22'); // 00:01 IST
  assert.deepEqual(openDays(NOON), ['2026-10-21', '2026-10-20']);
});

test('GET /api/prompts/today: the question, how many answered, and whether I did', async () => {
  const { s } = await withClock();
  try {
    addUser(s.db, 'riya');
    addUser(s.db, 'aman');
    const first = (await get(s, '/api/prompts/today', 'riya')).data;
    assert.equal(first.day, '2026-10-21');
    assert.equal(first.text, promptFor('2026-10-21').text);
    assert.equal(first.answerCount, 0);
    assert.equal(first.answered, false);
    assert.equal((await s.api('GET', '/api/prompts/today')).status, 401);

    const a = await s.api('POST', '/api/posts', { user: 'riya', form: videoForm({ kind: 'VIDEO', title: 'my answer', promptDay: '2026-10-21' }) });
    assert.equal(a.status, 201, JSON.stringify(a.data));
    assert.equal(a.data.post.promptDay, '2026-10-21');
    await s.idle();
    const after = (await get(s, '/api/prompts/today', 'riya')).data;
    assert.equal(after.answerCount, 1);
    assert.equal(after.answered, true);
    assert.equal((await get(s, '/api/prompts/today', 'aman')).data.answered, false);

    const answers = (await get(s, '/api/prompts/today/answers', 'aman')).data.items;
    assert.equal(answers.length, 1);
    assert.equal(answers[0].post.promptDay, '2026-10-21');
  } finally { await s.close(); }
});

test('an answer may be tagged with today or yesterday only, and only a new opinion can carry it', async () => {
  const { s } = await withClock();
  try {
    addUser(s.db, 'riya');
    const mk = (promptDay) => s.api('POST', '/api/posts', { user: 'riya', form: videoForm({ kind: 'VIDEO', promptDay }) });
    assert.equal((await mk('2026-10-20')).status, 201, 'yesterday still open');
    const old = await mk('2026-10-19');
    assert.equal(old.status, 400);
    assert.equal(old.data.field, 'promptDay');
    assert.equal((await mk('2026-10-22')).status, 400, 'tomorrow is not open');
    assert.equal((await mk('garbage')).status, 400);
    await s.idle();
    const root = s.db.get('SELECT id FROM posts WHERE parent_id IS NULL LIMIT 1').id;
    const reply = await s.api('POST', '/api/posts', { user: 'riya', form: videoForm({ kind: 'VIDEO', parentId: root, promptDay: '2026-10-21' }) });
    assert.equal(reply.status, 400);
    assert.equal(s.db.get('SELECT COUNT(*) AS n FROM posts').n, 1, 'nothing was stored for the refused ones');
  } finally { await s.close(); }
});

test('blocked people are left out of the answers and the count', async () => {
  const { s } = await withClock();
  try {
    const riya = addUser(s.db, 'riya');
    const mean = addUser(s.db, 'mean');
    const p = addPost(s.db, { userId: mean, title: 'x' });
    s.db.run("UPDATE posts SET prompt_day = '2026-10-21' WHERE id = ?", [p]);
    assert.equal((await get(s, '/api/prompts/today', 'riya')).data.answerCount, 1);
    s.db.run("INSERT INTO blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, 'x')", [riya, mean]);
    assert.equal((await get(s, '/api/prompts/today', 'riya')).data.answerCount, 0);
    assert.deepEqual((await get(s, '/api/prompts/today/answers', 'riya')).data.items, []);
  } finally { await s.close(); }
});

// ---------------- reply wanted ----------------

test('reply wanted: unanswered recent opinions first, never my own, never ones I answered, never blocked or old', async () => {
  const s = await startServer();
  try {
    const me = addUser(s.db, 'me_user');
    const other = addUser(s.db, 'other');
    const blocked = addUser(s.db, 'blocked');
    const lonely = addPost(s.db, { userId: other, title: 'nobody answered', minutesAgo: 60 });
    const busy = addPost(s.db, { userId: other, title: 'three answers', minutesAgo: 30 });
    for (let i = 0; i < 3; i++) addPost(s.db, { userId: other, parentId: busy, kind: 'TEXT', body: `r${i}` });
    const once = addPost(s.db, { userId: other, title: 'one answer', minutesAgo: 20 });
    addPost(s.db, { userId: other, parentId: once, kind: 'TEXT', body: 'only reply' });
    addPost(s.db, { userId: me, title: 'my own', minutesAgo: 5 });
    const answered = addPost(s.db, { userId: other, title: 'I replied already', minutesAgo: 10 });
    addPost(s.db, { userId: me, parentId: answered, kind: 'TEXT', body: 'mine' });
    addPost(s.db, { userId: blocked, title: 'from a blocked person', minutesAgo: 3 });
    s.db.run("INSERT INTO blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, 'x')", [me, blocked]);
    addPost(s.db, { userId: other, title: 'too old', minutesAgo: 60 * 24 * 9 });
    addPost(s.db, { userId: other, title: 'still processing', status: 'PROCESSING' });

    const r = await get(s, '/api/reply-wanted', 'me_user');
    assert.equal(r.status, 200);
    assert.deepEqual(idsOf(r.data.items), [lonely, once], 'fewest replies first; three replies is enough; the rest are excluded');
    assert.equal((await get(s, '/api/reply-wanted?limit=1', 'me_user')).data.items.length, 1);
    assert.equal((await s.api('GET', '/api/reply-wanted')).status, 401);
  } finally { await s.close(); }
});

test('reply wanted: a deleted or suspended author is left out', async () => {
  const s = await startServer();
  try {
    addUser(s.db, 'me_user');
    const gone = addUser(s.db, 'gone');
    const away = addUser(s.db, 'away');
    addPost(s.db, { userId: gone, title: 'a' });
    addPost(s.db, { userId: away, title: 'b' });
    s.db.run("UPDATE users SET deleted_at = 'x' WHERE id = ?", [gone]);
    s.db.run("UPDATE users SET suspended_at = 'x' WHERE id = ?", [away]);
    assert.deepEqual((await get(s, '/api/reply-wanted', 'me_user')).data.items, []);
  } finally { await s.close(); }
});

// ---------------- motion rooms ----------------

const room = { name: 'Debate society', motion: 'This house believes attendance should not be compulsory.' };

test('a room: made by its owner, joined with a code, visible only to members', async () => {
  const { s } = await withClock();
  try {
    addUser(s.db, 'owner');
    addUser(s.db, 'member');
    addUser(s.db, 'outsider');
    const made = await post(s, '/api/rooms', room, 'owner');
    assert.equal(made.status, 201, JSON.stringify(made.data));
    const r = made.data.room;
    assert.match(r.code, /^[A-HJ-NP-Z2-9]{6}$/);
    assert.equal(r.role, 'OWNER');
    assert.equal(r.status, 'OPEN');
    assert.equal(r.memberCount, 1);
    assert.equal(r.owner.username, 'owner');

    assert.equal((await get(s, `/api/rooms/${r.id}`, 'outsider')).status, 404, 'a room is not visible to people who are not in it');
    const bad = await post(s, '/api/rooms/join', { code: 'ZZZZZZ' }, 'member');
    assert.equal(bad.status, 404);
    assert.equal(bad.data.field, 'code');

    const joined = await post(s, '/api/rooms/join', { code: ` ${r.code.toLowerCase().slice(0, 3)}-${r.code.slice(3)} ` }, 'member');
    assert.equal(joined.status, 200, 'any case, spaces and dashes are fine');
    assert.equal(joined.data.room.role, 'MEMBER');
    assert.equal(joined.data.room.memberCount, 2);
    assert.equal((await post(s, '/api/rooms/join', { code: r.code }, 'member')).data.room.memberCount, 2, 'joining twice changes nothing');

    const detail = (await get(s, `/api/rooms/${r.id}`, 'member')).data;
    assert.deepEqual(detail.members.map((m) => m.username), ['owner', 'member']);
    assert.equal(detail.room.code, r.code);
    const mine = (await get(s, '/api/rooms/mine', 'member')).data.rooms;
    assert.equal(mine.length, 1);
    assert.deepEqual((await get(s, '/api/rooms/mine', 'outsider')).data.rooms, []);
  } finally { await s.close(); }
});

test('room input is checked: name, motion, dates, and at most five open rooms per owner', async () => {
  const { s } = await withClock();
  try {
    addUser(s.db, 'owner');
    const bad = async (body, field) => {
      const r = await post(s, '/api/rooms', { ...room, ...body }, 'owner');
      assert.equal(r.status, 400, JSON.stringify(body));
      assert.equal(r.data.field, field);
    };
    await bad({ name: '' }, 'name');
    await bad({ name: 'x'.repeat(61) }, 'name');
    await bad({ motion: 'too short' }, 'motion');
    await bad({ motion: 'x'.repeat(201) }, 'motion');
    await bad({ description: 'x'.repeat(501) }, 'description');
    await bad({ startsAt: 'not a date' }, 'startsAt');
    await bad({ endsAt: new Date(NOON - 1000).toISOString() }, 'endsAt');
    await bad({ startsAt: new Date(NOON + 5000).toISOString(), endsAt: new Date(NOON + 1000).toISOString() }, 'endsAt');
    for (let i = 0; i < 5; i++) assert.equal((await post(s, '/api/rooms', { ...room, name: `Room ${i}` }, 'owner')).status, 201);
    assert.equal((await post(s, '/api/rooms', room, 'owner')).status, 429);
  } finally { await s.close(); }
});

test('a room that has not started cannot be posted into, one that is open can, and a closed one is read only', async () => {
  const { s, clock } = await withClock();
  try {
    addUser(s.db, 'owner');
    addUser(s.db, 'member');
    const start = new Date(NOON + 3600000).toISOString();
    const end = new Date(NOON + 86400000).toISOString();
    const r = (await post(s, '/api/rooms', { ...room, startsAt: start, endsAt: end }, 'owner')).data.room;
    assert.equal(r.status, 'UPCOMING');
    await post(s, '/api/rooms/join', { code: r.code }, 'member');
    const mk = (user, roomId) => s.api('POST', '/api/posts', { user, form: videoForm({ kind: 'VIDEO', title: 'for', roomId }) });
    const early = await mk('member', r.id);
    assert.equal(early.status, 409);
    assert.match(early.data.error, /not started/);

    clock.now = NOON + 2 * 3600000;
    const ok = await mk('member', r.id);
    assert.equal(ok.status, 201, JSON.stringify(ok.data));
    assert.deepEqual(ok.data.post.room, { id: r.id, name: room.name });
    await s.idle();
    assert.equal((await get(s, `/api/rooms/${r.id}/posts`, 'owner')).data.items.length, 1);

    clock.now = NOON + 2 * 86400000; // past the end
    assert.equal((await mk('member', r.id)).status, 409);
    assert.equal((await get(s, `/api/rooms/${r.id}`, 'member')).data.room.status, 'CLOSED');
    assert.equal((await get(s, `/api/rooms/${r.id}/posts`, 'member')).data.items.length, 1, 'still readable');
    assert.equal((await post(s, '/api/rooms/join', { code: r.code }, 'owner')).status, 409, 'nobody new joins a closed room');
  } finally { await s.close(); }
});

test('only members can post into a room; a room post cannot also answer the daily question or be a reply', async () => {
  const { s } = await withClock();
  try {
    addUser(s.db, 'owner');
    addUser(s.db, 'outsider');
    const r = (await post(s, '/api/rooms', room, 'owner')).data.room;
    const mk = (user, fields) => s.api('POST', '/api/posts', { user, form: videoForm({ kind: 'VIDEO', ...fields }) });
    assert.equal((await mk('outsider', { roomId: r.id })).status, 404);
    assert.equal((await mk('owner', { roomId: r.id, promptDay: '2026-10-21' })).status, 400);
    assert.equal((await mk('owner', { roomId: 'nope' })).status, 404);
    assert.equal(s.db.get('SELECT COUNT(*) AS n FROM posts').n, 0);
  } finally { await s.close(); }
});

test('the AI places each room post for or against the motion, and the room page counts them', async () => {
  const stances = ['FOR', 'AGAINST', 'FOR'];
  const asked = [];
  const { s } = await withClock({}, {
    analyzer: { analyzeAudio: async (audio, ctx) => { asked.push(ctx); return { transcript: 'words', detectedStance: stances[asked.length - 1], overallSummary: 'sum', claims: [] }; } }
  });
  try {
    addUser(s.db, 'owner');
    addUser(s.db, 'member');
    const r = (await post(s, '/api/rooms', room, 'owner')).data.room;
    await post(s, '/api/rooms/join', { code: r.code }, 'member');
    for (const user of ['owner', 'member', 'member']) {
      const res = await s.api('POST', '/api/posts', { user, form: videoForm({ kind: 'VIDEO', title: 't', roomId: r.id }) });
      assert.equal(res.status, 201);
      await s.idle();
    }
    assert.deepEqual(asked, [room.motion, room.motion, room.motion], 'the motion is what each video is judged against');
    const detail = (await get(s, `/api/rooms/${r.id}`, 'owner')).data.room;
    assert.equal(detail.forCount, 2);
    assert.equal(detail.againstCount, 1);
    assert.equal(detail.posts, 3);
    assert.equal(detail.undecided, 0);
    const items = (await get(s, `/api/rooms/${r.id}/posts`, 'owner')).data.items;
    assert.deepEqual(items.map((i) => i.post.roomStance).sort(), ['AGAINST', 'FOR', 'FOR']);
    assert.ok(items.every((i) => i.post.stance === 'PARENT'), 'the post is still an ordinary opinion');
  } finally { await s.close(); }
});

test('leaving and closing: members leave, the owner cannot, only the owner closes', async () => {
  const { s } = await withClock();
  try {
    addUser(s.db, 'owner');
    addUser(s.db, 'member');
    const r = (await post(s, '/api/rooms', room, 'owner')).data.room;
    await post(s, '/api/rooms/join', { code: r.code }, 'member');
    assert.equal((await post(s, `/api/rooms/${r.id}/close`, {}, 'member')).status, 403);
    assert.equal((await post(s, `/api/rooms/${r.id}/leave`, {}, 'owner')).status, 409);
    assert.equal((await post(s, `/api/rooms/${r.id}/leave`, {}, 'member')).status, 200);
    assert.equal((await get(s, `/api/rooms/${r.id}`, 'member')).status, 404, 'no longer a member');
    const closed = await post(s, `/api/rooms/${r.id}/close`, {}, 'owner');
    assert.equal(closed.data.room.status, 'CLOSED');
    // closing frees a place under the five-room limit
    for (let i = 0; i < 4; i++) await post(s, '/api/rooms', { ...room, name: `R${i}` }, 'owner');
    assert.equal((await post(s, '/api/rooms', { ...room, name: 'fifth' }, 'owner')).status, 201);
  } finally { await s.close(); }
});

// ---------------- invites ----------------

async function verifiedToken(s, email) {
  await post(s, '/api/auth/email/send', { email });
  const { code } = s.emailProvider.last(email);
  return (await post(s, '/api/auth/email/verify', { email, code })).data.signupToken;
}
const profile = (signupToken, over = {}) => ({ signupToken, fullName: 'New Person', username: 'new_person', dob: '2000-05-20', password: 'a decent passphrase', ...over });

test('an invite code is made once, is short and unambiguous, and comes with a link', async () => {
  const { s } = await withClock({ publicBaseUrl: 'https://forestapp.in/' });
  try {
    addUser(s.db, 'riya');
    const a = (await get(s, '/api/me/invite', 'riya')).data;
    assert.match(a.code, /^[A-HJ-NP-Z2-9]{7}$/);
    assert.equal(a.link, `https://forestapp.in/invite/${a.code}`);
    assert.equal(a.invitedCount, 0);
    assert.equal((await get(s, '/api/me/invite', 'riya')).data.code, a.code, 'the same code every time');
    assert.equal((await s.api('GET', '/api/me/invite')).status, 401);
  } finally { await s.close(); }
});

test('signing up with a friend\'s code makes you follow each other, and counts them as invited', async () => {
  const { s } = await withClock();
  try {
    const riya = addUser(s.db, 'riya');
    const { code } = (await get(s, '/api/me/invite', 'riya')).data;
    const token = await verifiedToken(s, 'new@example.com');
    const res = await post(s, '/api/auth/signup', profile(token, { inviteCode: ` ${code.slice(0, 3).toLowerCase()} ${code.slice(3)} ` }));
    assert.equal(res.status, 201, JSON.stringify(res.data));
    const id = res.data.user.id;
    assert.ok(s.db.get('SELECT 1 AS x FROM follows WHERE follower_id = ? AND followee_id = ?', [id, riya]));
    assert.ok(s.db.get('SELECT 1 AS x FROM follows WHERE follower_id = ? AND followee_id = ?', [riya, id]));
    assert.equal(s.db.get('SELECT invited_by FROM users WHERE id = ?', [id]).invited_by, riya);
    assert.equal((await get(s, '/api/me/invite', 'riya')).data.invitedCount, 1);
  } finally { await s.close(); }
});

test('a wrong invite code stops the sign-up with a clear message; a blank one is fine; bots and deleted people cannot invite', async () => {
  const { s } = await withClock();
  try {
    addUser(s.db, 'riya');
    const bot = addUser(s.db, 'botty', { bot: true });
    s.db.run("UPDATE users SET invite_code = 'BOTCODE' WHERE id = ?", [bot]);
    const gone = addUser(s.db, 'gone');
    s.db.run("UPDATE users SET invite_code = 'GONECOD', deleted_at = 'x' WHERE id = ?", [gone]);
    const token = await verifiedToken(s, 'new@example.com');
    for (const inviteCode of ['NOTREAL', 'BOTCODE', 'GONECOD', 'abc']) {
      const r = await post(s, '/api/auth/signup', profile(token, { inviteCode }));
      assert.equal(r.status, 400, inviteCode);
      assert.equal(r.data.field, 'inviteCode');
    }
    assert.equal(s.db.get("SELECT COUNT(*) AS n FROM users WHERE username = 'new_person'").n, 0, 'nothing was created');
    assert.equal((await post(s, '/api/auth/signup', profile(token, { inviteCode: '  ' }))).status, 201);
  } finally { await s.close(); }
});

// ---------------- events and the founders' numbers ----------------

test('props are kept small and flat, and anything odd is dropped', () => {
  assert.equal(cleanProps({ method: 'email', n: 3, ok: true }), '{"method":"email","n":3,"ok":true}');
  assert.equal(cleanProps({ 'Bad Key': 'x', nested: { a: 1 }, list: [1] }), null);
  assert.equal(cleanProps('text'), null);
  assert.equal(cleanProps([1, 2]), null);
  assert.equal(JSON.parse(cleanProps({ long: 'x'.repeat(500) })).long.length, 40);
});

test('the app can send known events only, in small batches, signed in', async () => {
  const { s } = await withClock();
  try {
    addUser(s.db, 'riya');
    const r = await post(s, '/api/events', { events: [
      { name: 'app_open' }, { name: 'prompt_opened', props: { from: 'home' } },
      { name: 'signup' }, // only the server may record this one
      { name: 'made_up' }, null, 'text', { props: {} }
    ] }, 'riya');
    assert.equal(r.status, 200);
    assert.equal(r.data.recorded, 2);
    assert.deepEqual(s.db.all('SELECT name, props FROM events ORDER BY id').map((e) => e.name), ['app_open', 'prompt_opened']);
    assert.equal((await post(s, '/api/events', { events: 'x' }, 'riya')).status, 400);
    assert.equal((await post(s, '/api/events', { events: Array.from({ length: 80 }, () => ({ name: 'app_open' })) }, 'riya')).data.recorded, 50);
    assert.equal((await s.api('POST', '/api/events', { json: { events: [] } })).status, 401);
  } finally { await s.close(); }
});

test('the server records sign-up, finishing onboarding, and posts, with no personal content in them', async () => {
  const { s } = await withClock();
  try {
    const token = await verifiedToken(s, 'new@example.com');
    const made = await post(s, '/api/auth/signup', profile(token));
    const bearer = { authorization: `Bearer ${made.data.token}`, 'content-type': 'application/json' };
    await fetch(`${s.base}/api/me/onboarding`, { method: 'POST', headers: bearer, body: JSON.stringify({ topics: ['politics', 'tech', 'jobs'] }) });
    await fetch(`${s.base}/api/me/onboarding`, { method: 'POST', headers: bearer, body: JSON.stringify({ topics: ['sports'] }) });
    const form = videoForm({ kind: 'VIDEO', title: 'My private opinion about something', promptDay: '2026-10-21' });
    await fetch(`${s.base}/api/posts`, { method: 'POST', headers: { authorization: bearer.authorization }, body: form });
    await s.idle();
    const rows = s.db.all('SELECT name, props, user_id FROM events ORDER BY id');
    assert.deepEqual(rows.map((e) => e.name), ['signup', 'onboarding_done', 'post_created', 'prompt_answered']);
    assert.deepEqual(JSON.parse(rows[0].props), { method: 'email', invited: false });
    assert.deepEqual(JSON.parse(rows[1].props), { topics: 3, skipped: false });
    assert.ok(!JSON.stringify(rows).includes('private opinion'));
    assert.ok(!JSON.stringify(rows).includes('new@example.com'));
  } finally { await s.close(); }
});

test('deleting an account removes them from rooms, closes rooms they ran, and unlinks their events', async () => {
  const { s } = await withClock();
  try {
    const token = await verifiedToken(s, 'new@example.com');
    const made = await post(s, '/api/auth/signup', profile(token));
    const bearer = { authorization: `Bearer ${made.data.token}`, 'content-type': 'application/json' };
    const r = await (await fetch(`${s.base}/api/rooms`, { method: 'POST', headers: bearer, body: JSON.stringify(room) })).json();
    await fetch(`${s.base}/api/events`, { method: 'POST', headers: bearer, body: JSON.stringify({ events: [{ name: 'app_open' }] }) });
    const del = await fetch(`${s.base}/api/me`, { method: 'DELETE', headers: bearer, body: JSON.stringify({ password: 'a decent passphrase' }) });
    assert.equal(del.status, 200);
    assert.equal(s.db.get('SELECT COUNT(*) AS n FROM room_members').n, 0);
    assert.ok(s.db.get('SELECT closed_at FROM rooms WHERE id = ?', [r.room.id]).closed_at);
    assert.equal(s.db.get('SELECT COUNT(*) AS n FROM events WHERE user_id IS NOT NULL').n, 0);
    assert.ok(s.db.get('SELECT COUNT(*) AS n FROM events').n >= 2, 'the counts stay');
    const row = s.db.get("SELECT invite_code, invited_by FROM users WHERE username LIKE 'deleted_%'");
    assert.equal(row.invite_code, null);
  } finally { await s.close(); }
});

test('insights: counts only real people, follows the first minute, and reads answers and returns', async () => {
  const { s } = await withClock();
  try {
    const iso = (offsetHours) => new Date(NOON + offsetHours * 3600000).toISOString();
    const mk = (name, createdHours, extra = {}) => {
      const id = addUser(s.db, name, { bot: !!extra.bot });
      s.db.run('UPDATE users SET created_at = ?, onboarded_at = ? WHERE id = ?', [iso(createdHours), extra.onboarded ? iso(createdHours) : null, id]);
      return id;
    };
    const a = mk('anna', -48, { onboarded: true });
    const b = mk('bala', -30, { onboarded: true });
    const c = mk('chen', -2);
    mk('robot', -48, { bot: true });
    // anna watched and posted the day after she joined; bala only watched on the day she joined; chen did nothing
    s.db.run("INSERT INTO post_views (user_id, post_id, created_at) VALUES (?, 'x', ?)", [a, iso(-20)]);
    s.db.run("INSERT INTO post_views (user_id, post_id, created_at) VALUES (?, 'x', ?)", [b, iso(-29)]);
    s.db.run("INSERT INTO likes (user_id, post_id, created_at) VALUES (?, 'x', ?)", [a, iso(-20)]);
    const rootA = addPost(s.db, { userId: a, title: 'anna asks', minutesAgo: 20 * 60 });
    s.db.run('UPDATE posts SET created_at = ?, prompt_day = ? WHERE id = ?', [iso(-20), '2026-10-20', rootA]);
    const reply = addPost(s.db, { userId: b, parentId: rootA, kind: 'TEXT', body: 'answer' });
    s.db.run('UPDATE posts SET created_at = ? WHERE id = ?', [iso(-18), reply]);
    s.db.run("INSERT INTO events (user_id, name, props, day, at) VALUES (?, 'app_open', NULL, '2026-10-21', ?)", [c, iso(-1)]);

    const i = computeInsights(s.db, { days: 7, clock: () => NOON });
    assert.equal(i.totals.people, 3, 'the bot is not a person');
    assert.deepEqual(i.funnel.map((f) => [f.step, f.people]), [
      ['Signed up', 3], ['Finished onboarding', 2], ['Watched a video', 2], ['Liked or took a side', 1], ['Posted or replied', 2]
    ]);
    const today = i.daily.find((d) => d.day === '2026-10-21');
    assert.equal(today.active, 1, 'chen opened the app today');
    assert.equal(today.signups, 1);
    const yesterday = i.daily.find((d) => d.day === '2026-10-20');
    assert.equal(yesterday.opinions, 1);
    assert.equal(yesterday.promptAnswers, 1);
    assert.equal(yesterday.replies, 1);
    assert.deepEqual(i.answers, { opinions: 1, answeredWithin24hPct: 100, medianHoursToFirstReply: 2 });
    assert.equal(i.nextDayReturn.people, 2, 'chen joined too recently to count');
    assert.equal(i.nextDayReturn.returned, 1, 'anna came back the next day, bala did not');
    assert.equal(i.nextDayReturn.pct, 50);
    assert.equal(i.daily.length, 7);
  } finally { await s.close(); }
});

test('the founders\' page and numbers need the moderation token, like the rest of the back office', async () => {
  const { s } = await withClock({ moderationToken: 'secret-token-for-tests' });
  try {
    assert.equal((await s.api('GET', '/api/admin/insights')).status, 401);
    const ok = await fetch(`${s.base}/api/admin/insights?days=3`, { headers: { authorization: 'Bearer secret-token-for-tests' } });
    assert.equal(ok.status, 200);
    assert.equal((await ok.json()).days, 3);
    const page = await fetch(`${s.base}/admin/insights`);
    assert.equal(page.status, 200);
    assert.match(await page.text(), /FOREST numbers/);
  } finally { await s.close(); }
  const off = await startServer();
  try {
    assert.equal((await off.api('GET', '/admin/insights')).status, 404);
    assert.equal((await off.api('GET', '/api/admin/insights')).status, 404);
  } finally { await off.close(); }
});

// ---------------- public pages ----------------

test('a shared debate page shows the opinion and its replies, escaped, with link-preview tags', async () => {
  const s = await startServer({ appOptions: { publicBaseUrl: 'https://forestapp.in', playStoreUrl: 'https://play.google.com/store/apps/details?id=x' } });
  try {
    const riya = addUser(s.db, 'riya');
    const aman = addUser(s.db, 'aman');
    const root = addPost(s.db, { userId: riya, title: '<script>alert(1)</script> Should "phones" be banned?' });
    s.db.run("UPDATE posts SET cover_filename = 'c.jpg', analysis = ? WHERE id = ?", [JSON.stringify({ overallSummary: 'A <b>summary</b> & more' }), root]);
    addPost(s.db, { userId: aman, parentId: root, kind: 'TEXT', body: 'I <img src=x onerror=alert(1)> disagree', stance: 'AGAINST' });
    const res = await fetch(`${s.base}/p/${root}`);
    const html = await res.text();
    assert.equal(res.status, 200);
    assert.match(res.headers.get('content-security-policy'), /default-src 'none'/);
    assert.ok(!html.includes('<script>'), 'a title can never become markup');
    assert.ok(!html.includes('<img src=x'), 'nor a reply');
    assert.match(html, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
    assert.match(html, /A &lt;b&gt;summary&lt;\/b&gt; &amp; more/);
    assert.match(html, /@riya/);
    assert.match(html, /1 AGAINST/);
    assert.match(html, /<meta property="og:image" content="https:\/\/forestapp\.in\/uploads\/c\.jpg">/);
    assert.match(html, /<meta property="og:url" content="https:\/\/forestapp\.in\/p\//);
    assert.match(html, /<video controls/);
    assert.match(html, /play\.google\.com/);
    assert.match(html, /noindex/);
  } finally { await s.close(); }
});

test('a debate page is a plain 404 for anything that is not public: unknown, processing, hidden, deleted or suspended author', async () => {
  const s = await startServer();
  try {
    const riya = addUser(s.db, 'riya');
    const states = {
      processing: addPost(s.db, { userId: riya, status: 'PROCESSING' }),
      hidden: addPost(s.db, { userId: riya, status: 'HIDDEN' }),
      failed: addPost(s.db, { userId: riya, status: 'FAILED' })
    };
    for (const [name, id] of Object.entries(states)) assert.equal((await fetch(`${s.base}/p/${id}`)).status, 404, name);
    assert.equal((await fetch(`${s.base}/p/does-not-exist`)).status, 404);
    assert.equal((await fetch(`${s.base}/p/${'x'.repeat(500)}`)).status, 404);
    const ok = addPost(s.db, { userId: riya, title: 'fine' });
    assert.equal((await fetch(`${s.base}/p/${ok}`)).status, 200);
    s.db.run("UPDATE users SET suspended_at = 'x' WHERE id = ?", [riya]);
    assert.equal((await fetch(`${s.base}/p/${ok}`)).status, 404);
    s.db.run("UPDATE users SET suspended_at = NULL, deleted_at = 'x' WHERE id = ?", [riya]);
    assert.equal((await fetch(`${s.base}/p/${ok}`)).status, 404);
  } finally { await s.close(); }
});

test('the invite page names the inviter and shows the code; a made-up code says nothing', async () => {
  const s = await startServer();
  try {
    addUser(s.db, 'riya');
    const { code } = (await get(s, '/api/me/invite', 'riya')).data;
    const res = await fetch(`${s.base}/invite/${code.toLowerCase()}`);
    const html = await res.text();
    assert.equal(res.status, 200);
    assert.match(html, /@riya invited you/);
    assert.ok(html.includes(`>${code}<`));
    const bad = await fetch(`${s.base}/invite/NOTACODE`);
    assert.equal(bad.status, 404);
    assert.ok(!(await bad.text()).includes('@riya'));
  } finally { await s.close(); }
});

test('the Terms and Privacy pages carry the same words as the app', async () => {
  const s = await startServer();
  try {
    for (const [url, key] of [['/terms', 'terms'], ['/privacy', 'privacy']]) {
      const res = await fetch(s.base + url);
      assert.equal(res.status, 200);
      const html = await res.text();
      for (const sec of legal[key]) {
        assert.ok(html.includes(sec.heading.replace(/&/g, '&amp;')), sec.heading);
      }
      assert.ok(!/noindex/.test(html), 'the policy pages may be found');
    }
  } finally { await s.close(); }
});

test('legalText.js is in step with the Dart screen the app shows', () => {
  const dart = fs.readFileSync(path.join(__dirname, '..', '..', 'lib', 'features', 'legal', 'legal_screens.dart'), 'utf8').replace(/\r\n/g, '\n');
  const unescape = (t) => t.replace(/\\(['\\$nt])/g, (m, c) => ({ n: '\n', t: '\t' }[c] || c));
  const parse = (name) => {
    const block = new RegExp(`const ${name} = <_Section>\\[([\\s\\S]*?)\\n\\];`).exec(dart)[1];
    const out = [];
    const re = /_Section\(\s*'((?:[^'\\]|\\.)*)'\s*,\s*\[([\s\S]*?)\]\s*\)/g;
    let m;
    while ((m = re.exec(block))) out.push({ heading: unescape(m[1]), body: [...m[2].matchAll(/'((?:[^'\\]|\\.)*)'/g)].map((x) => unescape(x[1])) });
    return out;
  };
  assert.deepEqual(legal.terms, parse('_terms'), 'run the generator and commit src/legalText.js');
  assert.deepEqual(legal.privacy, parse('_privacy'));
  assert.equal(legal.updated, /const _updated = '([^']+)'/.exec(dart)[1]);
});

test('rooms and events do not break an old database file: the new columns are added and the old rows stay', async () => {
  const os = require('os');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'forest-growth-'));
  const file = path.join(dir, 'old.db');
  try {
    const SQL = await require('sql.js')();
    const old = new SQL.Database();
    old.run(`CREATE TABLE users (id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE COLLATE NOCASE, full_name TEXT NOT NULL,
      is_bot INTEGER NOT NULL DEFAULT 0, avatar_url TEXT, bio TEXT, phone TEXT, phone_verified INTEGER NOT NULL DEFAULT 0,
      email TEXT, dob TEXT, password_hash TEXT, created_at TEXT NOT NULL)`);
    old.run(`CREATE TABLE posts (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, kind TEXT NOT NULL, parent_id TEXT, root_id TEXT NOT NULL,
      depth INTEGER NOT NULL DEFAULT 0, title TEXT, body TEXT, media_filename TEXT, stance TEXT NOT NULL DEFAULT 'PARENT',
      status TEXT NOT NULL DEFAULT 'READY', analysis TEXT, created_at TEXT NOT NULL)`);
    old.run("INSERT INTO users (id, username, full_name, created_at) VALUES ('u1', 'veteran', 'Old', '2026-01-01T00:00:00Z')");
    old.run("INSERT INTO posts (id, user_id, kind, root_id, title, created_at) VALUES ('p1', 'u1', 'VIDEO', 'p1', 'old post', '2026-01-02T00:00:00Z')");
    fs.writeFileSync(file, Buffer.from(old.export()));
    old.close();
    const { openDb } = require('../src/db');
    const db = await openDb({ file });
    const cols = (t) => db.all(`PRAGMA table_info(${t})`).map((c) => c.name);
    for (const c of ['prompt_day', 'room_id', 'room_stance']) assert.ok(cols('posts').includes(c), c);
    for (const c of ['invite_code', 'invited_by']) assert.ok(cols('users').includes(c), c);
    assert.equal(db.get("SELECT title FROM posts WHERE id = 'p1'").title, 'old post');
    assert.ok(db.get("SELECT name FROM sqlite_master WHERE name = 'rooms'"));
    assert.ok(db.get("SELECT name FROM sqlite_master WHERE name = 'events'"));
    db.close();
    (await openDb({ file })).close(); // a second start is harmless
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});

test('follow helper sanity: invited people are mutual follows (friends), so they can send each other videos', async () => {
  const { s } = await withClock();
  try {
    const riya = addUser(s.db, 'riya');
    const { code } = (await get(s, '/api/me/invite', 'riya')).data;
    const token = await verifiedToken(s, 'friend@example.com');
    const made = await post(s, '/api/auth/signup', profile(token, { inviteCode: code, username: 'friend_one' }));
    const friends = await fetch(`${s.base}/api/users/friends`, { headers: { authorization: `Bearer ${made.data.token}` } });
    assert.deepEqual((await friends.json()).users.map((u) => u.username ?? u.user?.username), ['riya']);
    assert.ok(riya);
  } finally { await s.close(); }
});
