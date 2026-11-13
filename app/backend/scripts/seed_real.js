// Fills the app with content that goes through the REAL pipeline, the way users' uploads do:
//
//   a bot account uploads a video  ->  ffmpeg takes the audio  ->  Gemini transcribes it, writes timed captions, detects the
//   language, fact-checks it  ->  the backend adds English captions, a heading and a description  ->  other bot accounts
//   upload video replies, and Gemini labels each one FOR / AGAINST / UNRESOLVED against what it replies to.
//
// Which videos are roots, which are replies and who posts them is in scripts/seed_content.json. Nothing about the content
// (titles, descriptions, captions, stances) is written by hand: it all comes out of the pipeline.
//
//   npm run seed:real -- --media-dir <folder of videos>
//   npm run seed:real -- --media-dir <folder> --debates 2     only the first 2 debates (a quick try)
//   npm run seed:real -- --media-dir <folder> --offline        no Gemini: videos and accounts only
//
// Needs a Gemini key (GEMINI_API_KEY or GEMINI_API_KEYS in app/backend/.env). It RESETS the local database, gives every
// account a drawn profile picture, and takes several minutes: videos are analysed one at a time. Every account it creates
// is a bot and is labelled BOT in the app. Videos are trimmed copies (<= 60 s) made here; your originals are never touched.
// Use only videos you are allowed to use. Afterwards: npm run snapshot:save  to share the result.

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
require('dotenv').config({ path: path.join(ROOT, '.env') });

const args = process.argv.slice(2);
const arg = (name, fallback = null) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : fallback; };
const mediaDir = arg('--media-dir') && path.resolve(arg('--media-dir'));
const manifestFile = path.resolve(arg('--manifest', path.join(__dirname, 'seed_content.json')));
const debateLimit = arg('--debates') ? Math.max(1, Number(arg('--debates'))) : Infinity;
const offline = args.includes('--offline');

function die(msg) { console.error('\n' + msg + '\n'); process.exit(1); }
if (!mediaDir || !fs.existsSync(mediaDir)) die('Give a folder of videos:  npm run seed:real -- --media-dir <folder>');
if (!fs.existsSync(manifestFile)) die('Manifest not found: ' + manifestFile);

const keys = [...new Set(
  [process.env.GEMINI_API_KEYS, process.env.GEMINI_API_KEY, ...Object.keys(process.env)
    .filter((k) => /^GEMINI_(API_)?KEY_\d+$/.test(k)).map((k) => process.env[k])]
    .filter(Boolean).flatMap((v) => String(v).split(',')).map((v) => v.trim()).filter(Boolean)
)];
if (!keys.length && !offline) {
  die('No Gemini key found. Put  GEMINI_API_KEY=your-key  in app/backend/.env  (several keys: GEMINI_API_KEYS=a,b,c)\n' +
      'and run this again. Without a key nothing can transcribe a video. (--offline posts the videos with placeholder text.)');
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));

// a small deterministic random generator, so two runs give the same likes and times
function rng(seed) { let s = seed >>> 0; return () => { s = (Math.imul(s, 1664525) + 1013904223) >>> 0; return s / 4294967296; }; }

async function main() {
  const { v4: uuid } = require('uuid');
  const { openDb } = require('../src/db');
  const { createApp } = require('../src/app');
  const { createProvider } = require('../src/auth/providers');
  const { seed } = require('./seed');
  const { renderAvatar } = require('./lib/avatar');

  // ---- 1. the debates to post, flattened level by level (a reply can only be posted once its parent is READY) ----
  const debates = manifest.debates.slice(0, debateLimit);
  const nodes = [];
  const walk = (node, parent, debateIdx, depth) => {
    const n = { file: node.file, by: node.by, parent, debate: debateIdx, depth, id: null, children: [] };
    nodes.push(n);
    if (parent) parent.children.push(n);
    (node.replies || []).forEach((r) => walk(r, n, debateIdx, depth + 1));
    return n;
  };
  debates.forEach((d, i) => {
    const root = walk(d.root, null, i, 0);
    (d.replies || []).forEach((r) => walk(r, root, i, 1));
  });
  const botNames = new Set(manifest.bots.map((b) => b.username));
  for (const n of nodes) {
    if (!botNames.has(n.by)) die(`The manifest posts as "${n.by}" but that account is not in "bots".`);
    if (!fs.existsSync(path.join(mediaDir, n.file))) die(`Video not found: ${path.join(mediaDir, n.file)}`);
    if (n.parent && n.parent.by === n.by) die(`${n.by} replies to their own video (${n.file}); use another account.`);
  }

  // ---- 2. trimmed copies of the videos, with their sound ----
  const work = path.join(ROOT, 'data', 'seed-real-clips');
  fs.mkdirSync(work, { recursive: true });
  const ffmpeg = require('ffmpeg-static');
  console.log(`Preparing ${nodes.length} video(s) (trimmed to 60 s, with sound)...`);
  for (const n of nodes) {
    const src = path.join(mediaDir, n.file);
    n.clip = path.join(work, n.file.replace(/[^a-zA-Z0-9._-]/g, '_').replace(/\.[^.]+$/, '') + '.mp4');
    if (fs.existsSync(n.clip) && fs.statSync(n.clip).size > 0 && fs.statSync(n.clip).mtimeMs > fs.statSync(src).mtimeMs) continue;
    const r = spawnSync(ffmpeg, ['-y', '-loglevel', 'error', '-i', src, '-t', '60', '-vf', 'scale=540:-2',
      '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '28', '-preset', 'veryfast', '-c:a', 'aac', '-b:a', '64k', '-movflags', '+faststart', n.clip]);
    if (r.status !== 0) die(`Could not convert ${n.file}: ${String(r.stderr).slice(-300)}`);
  }

  // ---- 3. a fresh database, the accounts and their pictures ----
  const dbFile = path.resolve(ROOT, process.env.DB_FILE || 'data/forest-app.db');
  const uploadsDir = path.resolve(ROOT, process.env.UPLOADS_DIR || 'uploads');
  fs.rmSync(dbFile, { force: true });
  const db = await openDb({ file: dbFile, saveDelayMs: 0 });
  await seed(db, { mediaDir: null, uploadsDir });
  db.run('DELETE FROM likes');
  db.run('DELETE FROM posts');
  fs.mkdirSync(uploadsDir, { recursive: true });
  const now = Date.now();
  const iso = (ms) => new Date(ms).toISOString();
  console.log(`\nSetting up ${manifest.bots.length} accounts with profile pictures...`);
  for (const b of manifest.bots) {
    const file = `avatar-${b.username.replace(/[^a-zA-Z0-9]/g, '_')}.png`;
    fs.writeFileSync(path.join(uploadsDir, file), renderAvatar(b.username, b.avatar || {}));
    const url = `/uploads/${file}`;
    const isBot = b.username === 'dev' ? 0 : 1;
    const row = db.get('SELECT id FROM users WHERE username = ?', [b.username]);
    if (row) db.run('UPDATE users SET full_name = ?, bio = ?, avatar_url = ?, is_bot = ? WHERE id = ?', [b.fullName, b.bio || null, url, isBot, row.id]);
    else db.run('INSERT INTO users (id, username, full_name, is_bot, avatar_url, bio, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [uuid(), b.username, b.fullName, isBot, url, b.bio || null, iso(now - 30 * 86400000)]);
  }
  // the dev account follows every bot, so Home shows all of it
  const dev = db.get("SELECT id FROM users WHERE username = 'dev'");
  for (const b of manifest.bots) {
    if (b.username === 'dev') continue;
    db.run('INSERT OR IGNORE INTO follows (follower_id, followee_id, created_at) VALUES (?, ?, ?)',
      [dev.id, db.get('SELECT id FROM users WHERE username = ?', [b.username]).id, iso(now - 20 * 86400000)]);
  }

  // ---- 4. the real backend, in this process, on a free port (same wiring as src/server.js) ----
  const secretFile = path.join(path.dirname(dbFile), '.jwt-secret');
  if (!fs.existsSync(secretFile)) fs.writeFileSync(secretFile, crypto.randomBytes(32).toString('hex'), { mode: 0o600 });
  const app = createApp({
    db, uploadsDir, allowDevUser: true, jwtSecret: fs.readFileSync(secretFile, 'utf8').trim(),
    otpProvider: createProvider('console', { production: false }), minAge: 18, defaultCountryCode: '+91',
    allowLegacyUpload: false, rateLimit: false, corsOrigins: '*', trustProxy: false, jobTimeoutMs: 240000,
    otpDailyBudget: 500, otpPerIpPerDay: 20,
  });
  const server = await new Promise((res) => { const s = app.listen(0, '127.0.0.1', () => res(s)); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = async (as, method, url, form) => {
    const res = await fetch(base + url, { method, headers: { 'X-Dev-User': as }, body: form });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(`${res.status} ${body.error || ''}`);
    return body;
  };
  const status = (id) => db.get('SELECT status FROM posts WHERE id = ?', [id]).status;

  // ---- 5. post level by level: roots first, then replies to them, then replies to those ----
  const maxDepth = Math.max(...nodes.map((n) => n.depth));
  const started = Date.now();
  for (let depth = 0; depth <= maxDepth; depth++) {
    const level = nodes.filter((n) => n.depth === depth);
    if (!level.length) continue;
    console.log(`\n${depth === 0 ? 'Root videos' : `Replies, level ${depth}`}: posting ${level.length} video(s), analysed one at a time (about 30-60 s each)...`);
    for (const n of level) {
      const form = new FormData();
      form.set('kind', 'VIDEO');
      if (n.parent) form.set('parentId', n.parent.id);
      form.set('video', await fs.openAsBlob(n.clip, { type: 'video/mp4' }), path.basename(n.clip));
      n.id = (await call(n.by, 'POST', '/api/posts', form)).post.id;
      console.log(`  queued  @${n.by.padEnd(11)} ${n.file}`);
    }
    let last = '';
    for (;;) {
      const done = level.filter((n) => status(n.id) !== 'PROCESSING').length;
      const line = `  analysed ${done}/${level.length}`;
      if (line !== last) { console.log(line); last = line; }
      if (done === level.length) break;
      if (Date.now() - started > 90 * 60000) die('Gave up waiting after 90 minutes.');
      await sleep(3000);
    }
    for (const n of level.filter((x) => status(x.id) === 'FAILED')) { // one more try for anything that failed
      console.warn(`  FAILED, retrying: ${n.file}`);
      try {
        await call(n.by, 'POST', `/api/posts/${n.id}/retry`);
        while (status(n.id) === 'PROCESSING') await sleep(3000);
      } catch (e) { console.warn('  retry not possible: ' + e.message); }
    }
    for (const n of level.filter((x) => status(x.id) !== 'READY')) {
      console.warn(`  NOT READY: ${n.file}; its replies are skipped`);
      const skip = (m) => { m.skipped = true; m.children.forEach(skip); };
      n.children.forEach(skip);
      n.skipped = true;
    }
    // children of anything that did not work cannot be posted
    nodes.filter((n) => n.depth === depth + 1 && n.parent && n.parent.skipped).forEach((n) => { n.skipped = true; });
    for (let i = nodes.length - 1; i >= 0; i--) if (nodes[i].skipped && nodes[i].depth === depth + 1) nodes.splice(i, 1);
  }

  // ---- 6. make it look lived in: spread the posts over the last days and add likes from the other accounts ----
  const rand = rng(20260414);
  const live = nodes.filter((n) => n.id && status(n.id) === 'READY');
  const roots = live.filter((n) => !n.parent);
  const created = new Map();
  roots.forEach((n, i) => created.set(n, now - (6 - i * (5 / Math.max(1, roots.length - 1 || 1))) * 86400000 + Math.floor(rand() * 4) * 3600000));
  for (const n of live.filter((x) => x.parent).sort((a, b) => a.depth - b.depth)) {
    const after = created.get(n.parent) + (30 + Math.floor(rand() * 420)) * 60000;
    created.set(n, Math.min(after, now - 5 * 60000 - Math.floor(rand() * 3600000)));
  }
  for (const [n, t] of created) db.run('UPDATE posts SET created_at = ? WHERE id = ?', [iso(t), n.id]);
  const users = db.all('SELECT id, username FROM users');
  for (const n of live) {
    const author = db.get('SELECT user_id FROM posts WHERE id = ?', [n.id]).user_id;
    const likes = Math.floor(rand() * (n.parent ? 6 : 10));
    for (let i = 0; i < likes; i++) {
      const u = users[Math.floor(rand() * users.length)];
      if (u.id !== author) db.run('INSERT OR IGNORE INTO likes (user_id, post_id, created_at) VALUES (?, ?, ?)', [u.id, n.id, iso(created.get(n) + 600000)]);
    }
  }

  // ---- 7. what came out ----
  console.log('\n==== Result ====');
  for (let i = 0; i < debates.length; i++) {
    const inDebate = live.filter((n) => n.debate === i);
    const root = inDebate.find((n) => !n.parent);
    if (!root) continue;
    const row = (n) => db.get('SELECT title, body, stance, analysis FROM posts WHERE id = ?', [n.id]);
    const r = row(root);
    const a = r.analysis ? JSON.parse(r.analysis) : {};
    console.log(`\n${r.title || '(no title)'}   [@${root.by}, ${a.language || '?'}, ${(a.captions || []).length} caption lines, English: ${a.language === 'en' ? 'spoken' : (a.captionTracks && a.captionTracks.en ? 'made' : 'MISSING')}]`);
    console.log(`  ${r.body || '(no description)'}`);
    for (const n of inDebate.filter((x) => x.parent)) {
      const c = row(n);
      console.log(`  ${'  '.repeat(n.depth - 1)}- ${String(c.stance).padEnd(10)} @${n.by.padEnd(11)} ${(c.body || '').slice(0, 100)}`);
    }
  }
  const totals = db.get("SELECT COUNT(*) AS n FROM posts WHERE status = 'READY'").n;

  await new Promise((r) => server.close(r));
  db.close();
  console.log(`\nDone. ${totals} video(s) ready. Start the backend with  npm start  and sign in as dev / dev_123.`);
  console.log('To share this with a teammate:  npm run snapshot:save  and commit the snapshot folder.');
  process.exit(0);
}

main().catch((e) => die(e.stack || e.message));
