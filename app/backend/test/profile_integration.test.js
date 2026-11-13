// Where the profile page (profile.js) meets the rest of the server: privacy of drafts, account deletion, and the new tables upgrading old files.

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { startServer, addUser, addPost } = require('./helpers');

const get = (s, url, user) => s.api('GET', url, { user });

test('an AI-written summary is a draft: only its owner sees it until they approve it', async () => {
  const s = await startServer();
  try {
    const me = addUser(s.db, 'riya');
    addUser(s.db, 'aman');
    s.db.run("UPDATE users SET personality_summary = 'Curious and blunt', personality_summary_approved = 0, personality_keywords = '[\"curious\"]' WHERE id = ?", [me]);

    const owner = (await get(s, `/api/users/${me}/profile`, 'riya')).data;
    assert.equal(owner.personality.summary, 'Curious and blunt');
    assert.equal(owner.personality.summaryApproved, false);

    const other = (await get(s, `/api/users/${me}/profile`, 'aman')).data;
    assert.equal(other.personality.summary, null, 'a draft is not shown to anyone else');
    assert.deepEqual(other.personality.keywords, ['curious'], 'the keywords they chose are theirs to show');

    s.db.run('UPDATE users SET personality_summary_approved = 1 WHERE id = ?', [me]);
    assert.equal((await get(s, `/api/users/${me}/profile`, 'aman')).data.personality.summary, 'Curious and blunt');
  } finally { await s.close(); }
});

test('deleting an account wipes the profile page data and the saved posts', async () => {
  const s = await startServer();
  try {
    const riya = addUser(s.db, 'riya');
    const author = addUser(s.db, 'author');
    const post = addPost(s.db, { userId: author, title: 'worth saving' });
    s.db.run(`UPDATE users SET bio = 'my bio', personality_keywords = '["a"]', personality_summary = 'secret', personality_summary_approved = 1,
              interests = '["x"]', password_hash = ? WHERE id = ?`, [await require('../src/auth/password').hashPassword('a decent passphrase'), riya]);
    s.db.run("INSERT INTO bookmarks (user_id, post_id, created_at) VALUES (?, ?, 'x')", [riya, post]);
    s.db.run("INSERT INTO bookmarks (user_id, post_id, created_at) VALUES (?, ?, 'x')", [author, post]);

    const res = await fetch(`${s.base}/api/me`, {
      method: 'DELETE',
      headers: { 'x-dev-user': 'riya', 'content-type': 'application/json' },
      body: JSON.stringify({ password: 'a decent passphrase' })
    });
    assert.equal(res.status, 200, await res.clone().text());
    const row = s.db.get('SELECT * FROM users WHERE id = ?', [riya]);
    for (const col of ['bio', 'personality_keywords', 'personality_summary', 'interests']) assert.equal(row[col], null, col);
    assert.equal(row.personality_summary_approved, 0);
    assert.equal(s.db.get('SELECT COUNT(*) AS n FROM bookmarks WHERE user_id = ?', [riya]).n, 0);
    assert.equal(s.db.get('SELECT COUNT(*) AS n FROM bookmarks WHERE user_id = ?', [author]).n, 1, 'other people\'s saved posts stay');
    assert.equal((await get(s, `/api/users/${riya}/profile`, 'author')).status, 404, 'the profile is gone');
  } finally { await s.close(); }
});

test('both sets of new columns exist together on a fresh database', async () => {
  const s = await startServer();
  try {
    const cols = s.db.all('PRAGMA table_info(users)').map((c) => c.name);
    for (const c of ['personality_keywords', 'personality_summary', 'personality_summary_approved', 'interests', 'invite_code', 'invited_by', 'onboarded_at', 'google_sub', 'email_verified']) {
      assert.ok(cols.includes(c), c);
    }
    assert.ok(s.db.get("SELECT name FROM sqlite_master WHERE name = 'bookmarks'"));
    assert.ok(s.db.get("SELECT name FROM sqlite_master WHERE name = 'rooms'"));
  } finally { await s.close(); }
});
