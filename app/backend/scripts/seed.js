// Sample data for local development, shaped like the Home prototype.
//
//   npm run seed                              users + posts, no video files
//   npm run seed -- --media-dir D:\clips      also copies your own clips in
//   npm run seed -- --reset                   wipes the database first
//
// Every sample person is flagged is_bot=1 so the app labels them BOT: they
// are not real users (CLAUDE.md hard rule). Use founder-recorded clips only
// for --media-dir; never other platforms' videos.

const fs = require('fs');
const path = require('path');
const { v4: uuid } = require('uuid');
const { hashPassword } = require('../src/auth/password');

// The seeded developer account can log in with these (development databases only). The password is deliberately
// short and simple: the 8-character rule applies to sign-up, not to this seeded test account.
const DEV_LOGIN = { username: 'dev', phone: '+919999900001', password: 'dev_123' };
// A fixed id, so a reseed does not log you out: the app keeps a login token that names this id, and a new random id
// would make the saved token point at nobody (the server then answers 401 and the app signs out).
const DEV_USER_ID = '5f0e0000-0000-4000-8000-000000000001';

const ROOT = path.join(__dirname, '..');
const mins = (m) => new Date(Date.now() - m * 60000).toISOString();

async function seed(db, { mediaDir = null, uploadsDir = path.join(ROOT, 'uploads') } = {}) {
  if (db.get('SELECT 1 AS x FROM users LIMIT 1')) {
    throw new Error('Database already has users. Run with --reset to start over.');
  }

  // --- media: copy a few of your own clips into uploads/ ---
  let clips = [];
  if (mediaDir) {
    fs.mkdirSync(uploadsDir, { recursive: true });
    clips = fs.readdirSync(mediaDir)
      .filter((f) => /\.(mp4|webm|mov)$/i.test(f))
      .sort()
      .slice(0, 8)
      .map((f) => {
        const name = `seed-${f.replace(/[^a-zA-Z0-9.-]/g, '_')}`;
        fs.copyFileSync(path.join(mediaDir, f), path.join(uploadsDir, name));
        return name;
      });
  }
  let nextClip = 0;
  const clip = () => (clips.length ? clips[nextClip++ % clips.length] : null);

  const users = {};
  const addUser = (username, fullName, isBot, fixedId = null) => {
    const id = fixedId || uuid();
    db.run('INSERT INTO users (id, username, full_name, is_bot, created_at) VALUES (?, ?, ?, ?, ?)', [
      id, username, fullName, isBot ? 1 : 0, mins(5000)
    ]);
    users[username] = id;
  };
  addUser('dev', 'Dev You', false, DEV_USER_ID); // you, the developer: a real account
  db.run('UPDATE users SET phone = ?, phone_verified = 1, dob = ?, password_hash = ? WHERE username = ?',
    [DEV_LOGIN.phone, '1999-01-01', await hashPassword(DEV_LOGIN.password), DEV_LOGIN.username]);
  [
    ['aman_s', 'Aman Singh'], ['riya_k', 'Riya Kapoor'], ['kabir_m', 'Kabir Mehta'],
    ['simran.v', 'Simran Verma'], ['dev.p', 'Dev Patel'], ['priya_n', 'Priya Nair'],
    ['forest_daily', 'FOREST Daily Prompt']
  ].forEach(([u, n]) => addUser(u, n, true));

  const posts = {};
  function post(key, { by, kind = 'VIDEO', parent = null, title = null, body = null, stance, minutesAgo, summary = null }) {
    const id = uuid();
    const p = parent ? db.get('SELECT * FROM posts WHERE id = ?', [posts[parent]]) : null;
    db.run(
      `INSERT INTO posts (id, user_id, kind, parent_id, root_id, depth, title, body, media_filename,
                          stance, status, analysis, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'READY', ?, ?)`,
      [
        id, users[by], kind, p ? p.id : null, p ? p.root_id : id, p ? p.depth + 1 : 0,
        title, body, kind === 'VIDEO' ? clip() : null,
        stance || (p ? 'UNRESOLVED' : 'PARENT'),
        summary ? JSON.stringify({ transcript: summary, overallSummary: summary, claims: [] }) : null,
        mins(minutesAgo)
      ]
    );
    posts[key] = id;
  }

  db.tx(() => {
    post('p1', { by: 'aman_s', title: 'Should Punjabi be mandatory in schools till Class 12?', minutesAgo: 180,
      summary: 'Argues a state language should be compulsory through school: cultural continuity, job access in the state, and the cost for students who move in from other states.' });
    post('r1', { by: 'riya_k', parent: 'p1', stance: 'AGAINST', body: 'Mandates hurt students from other states', minutesAgo: 60 });
    post('r2', { by: 'simran.v', kind: 'TEXT', parent: 'p1', stance: 'AGAINST', body: 'Most states that did this saw dropout rates rise for migrant kids.', minutesAgo: 120 });
    post('r3', { by: 'kabir_m', parent: 'r1', stance: 'FOR', body: 'The problem is the rollout, not the language itself.', minutesAgo: 20 });
    post('x1', { by: 'priya_n', kind: 'TEXT', parent: 'p1', stance: 'FOR', body: 'Learning your state’s language is basic respect, and Class 12 is long enough to do it well.', minutesAgo: 150 });
    post('x2', { by: 'dev.p', kind: 'TEXT', parent: 'p1', stance: 'UNRESOLVED', body: 'Mandatory till Class 10 and optional after sounds like a fair middle.', minutesAgo: 170 });
    post('x3', { by: 'aman_s', kind: 'TEXT', parent: 'r2', stance: 'UNRESOLVED', body: 'Dropout data needs context. Which states and which years?', minutesAgo: 95 });
    post('p2', { by: 'forest_daily', title: 'Daily debate: should colleges ban phones in lecture halls?', minutesAgo: 300,
      summary: 'Daily prompt posted by the FOREST bot to start a conversation. Reply with a video or a short text.' });
    post('r4', { by: 'dev.p', kind: 'TEXT', parent: 'p2', stance: 'UNRESOLVED', body: 'Depends on the class. Taking notes on a laptop is different from scrolling reels.', minutesAgo: 240 });

    const follow = (who) => db.run('INSERT INTO follows (follower_id, followee_id, created_at) VALUES (?, ?, ?)', [users.dev, users[who], mins(4000)]);
    ['aman_s', 'riya_k', 'kabir_m', 'simran.v', 'forest_daily'].forEach(follow);

    const like = (who, key) => db.run('INSERT OR IGNORE INTO likes (user_id, post_id, created_at) VALUES (?, ?, ?)', [users[who], posts[key], mins(10)]);
    ['riya_k', 'kabir_m', 'simran.v', 'priya_n'].forEach((u) => like(u, 'p1'));
    ['aman_s', 'kabir_m'].forEach((u) => like(u, 'r1'));
    like('dev', 'r2');
  });

  return { users, posts, clips: clips.length };
}

module.exports = { seed, DEV_LOGIN };

if (require.main === module) {
  (async () => {
    require('dotenv').config({ path: path.join(ROOT, '.env') });
    const { openDb } = require('../src/db');
    const args = process.argv.slice(2);
    const arg = (name) => {
      const i = args.indexOf(name);
      return i >= 0 ? args[i + 1] : null;
    };
    const dbFile = path.resolve(ROOT, process.env.DB_FILE || 'data/forest-app.db');
    const uploadsDir = path.resolve(ROOT, process.env.UPLOADS_DIR || 'uploads');

    if (args.includes('--reset')) fs.rmSync(dbFile, { force: true });
    const db = await openDb({ file: dbFile });
    try {
      const out = await seed(db, { mediaDir: arg('--media-dir'), uploadsDir });
      console.log(`Seeded ${Object.keys(out.users).length} users and ${Object.keys(out.posts).length} posts into ${dbFile}`);
      console.log(out.clips ? `Copied ${out.clips} clip(s) into ${uploadsDir}` : 'No --media-dir given: video posts have no file (the app should show a placeholder).');
      console.log('Send "X-Dev-User: dev" to see their Home feed, or log in as dev / dev_123 (or phone +919999900001).');
    } catch (err) {
      console.error(err.message);
      process.exitCode = 1;
    } finally {
      db.close();
    }
  })();
}
